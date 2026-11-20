"""Google Drive 데이터 백엔드 — 나스(Synology FileStation) 대체 클라이언트

목표: 프록시(proxy_server.py)의 NAS 호출부를 **수정 없이** 그대로 두고,
      데이터 저장소만 나스 → 구글드라이브로 교체한다.

프록시는 `NAS.list/read_bytes/read/write/mkdir/delete/move/rename/get_info/
write_stream/exists/warm` 만 사용한다. 이 클래스는 동일한 시그니처와
반환 형태({"ok":True,"files":[{"name","isdir","size","path"}]} 등)를 제공한다.

[경로 매핑]
  프록시는 `/92_Tiger_app_data/TSAK_인가자관리/행사관리/2026` 같은 **절대경로**를
  쓴다. 이 클라이언트는 그 접두사(base_path)를 떼고, 나머지 경로를
  구글드라이브의 **루트 폴더**(root_id) 아래에 **동일한 트리**로 매핑한다.
      /92_Tiger_app_data/TSAK_인가자관리            → <root>
      /92_Tiger_app_data/TSAK_인가자관리/행사관리    → <root>/행사관리
      ...
  → 프록시 코드/설정/하드코딩 경로를 하나도 바꾸지 않아도 된다.

[성능]
  · 경로 → 파일ID 해석 결과를 메모리 + 디스크(.gdrive_idcache.json)에 캐시하여
    경로당 API 왕복을 1회로 줄인다(캐시 히트 시 0회).
  · 폴더 목록 조회는 페이지네이션으로 1000개씩 가져온다.

[인증]
  서비스 계정 키(권장):
    config.json.gdrive.service_account  = "/home/user/nas_proxy/gdrive_sa.json"
    또는 환경변수 TSAK_GDRIVE_SA
  OAuth 토큰(대안):
    config.json.gdrive.client_secret / oauth_token  (+ 최초 1회 브라우저 동의)
"""
import io
import json
import os
import tempfile
import threading
import time

try:
    from google.oauth2 import service_account
    from google.oauth2.credentials import Credentials as _OAuthCreds
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaIoBaseUpload, MediaIoBaseDownload
    from googleapiclient.errors import HttpError
    _GOOGLE_OK = True
except Exception:                       # 라이브러리 미설치 시 친절히 안내
    _GOOGLE_OK = False

_SCOPES = ["https://www.googleapis.com/auth/drive"]
_FOLDER_MIME = "application/vnd.google-apps.folder"
_HERE = os.path.dirname(os.path.abspath(__file__))
#  [가비아 이전 2026-11-20] 코드 위치와 상태 위치를 분리한다.
#   ID 캐시·OAuth 토큰은 **릴리스 교체에도 살아남아야** 한다.
#   (릴리스마다 사라지면 매 배포 후 드라이브 경로 해석을 처음부터 다시 한다)
#   TSAK_STATE_DIR 이 없으면 종전과 동일하게 _HERE 를 쓴다 → 동작 무변화.
_STATE = os.environ.get("TSAK_STATE_DIR") or _HERE
_IDCACHE = os.path.join(_STATE, ".gdrive_idcache.json")


class GDriveAuthError(RuntimeError):
    pass


class GDriveClient:
    """구글드라이브 파일 백엔드 — NasClient 와 동일 인터페이스."""

    def __init__(self, conf):
        if not _GOOGLE_OK:
            raise GDriveAuthError(
                "google-api-python-client / google-auth 가 필요합니다. "
                "pip install google-api-python-client google-auth-oauthlib")
        conf = conf or {}
        self.root_id = str(conf.get("root_id", "")).strip()
        self.base_path = str(
            conf.get("base_path", "/92_Tiger_app_data/TSAK_인가자관리")
        ).rstrip("/")
        self.sa_file = str(
            conf.get("service_account") or os.environ.get("TSAK_GDRIVE_SA", "")
        ).strip()
        self.client_secret = str(conf.get("client_secret", "")).strip()
        self.token_file = str(
            conf.get("oauth_token") or os.path.join(_STATE, ".gdrive_token.json")
        ).strip()
        self._lock = threading.Lock()
        self._cache = {}          # rel_path -> file id
        self._svc = None
        self._load_cache()
        if not self.root_id:
            raise GDriveAuthError(
                "gdrive.root_id 가 비어 있습니다(config.json). "
                "드라이브 폴더 URL 의 .../folders/<ID> 값을 넣어 주세요.")

    # ---------------------------------------------------------------- auth
    def _service(self):
        if self._svc is not None:
            return self._svc
        creds = None
        if self.sa_file and os.path.isfile(self.sa_file):
            creds = service_account.Credentials.from_service_account_file(
                self.sa_file, scopes=_SCOPES)
        elif os.path.isfile(self.token_file):
            info = json.load(open(self.token_file, encoding="utf-8"))
            if info.get("type") == "authorized_user":
                creds = _OAuthCreds.from_authorized_user_info(info, _SCOPES)
            else:
                creds = service_account.Credentials.from_service_account_info(
                    info, scopes=_SCOPES)
        if creds is None and self.client_secret and os.path.isfile(self.client_secret):
            from google_auth_oauthlib.flow import InstalledAppFlow
            flow = InstalledAppFlow.from_client_secrets_file(
                self.client_secret, _SCOPES)
            creds = flow.run_local_server(port=0)
            try:
                with open(self.token_file, "w", encoding="utf-8") as f:
                    f.write(creds.to_json())
            except Exception:
                pass
        if creds is None:
            raise GDriveAuthError(
                "구글 인증 정보가 없습니다. 서비스 계정 키(gdrive_sa.json)를 "
                "config.json.gdrive.service_account 에 지정하거나, "
                "client_secret + oauth_token 을 설정하세요.")
        self._svc = build("drive", "v3", credentials=creds,
                          cache_discovery=False)
        return self._svc

    # ------------------------------------------------------------- cache
    def _load_cache(self):
        try:
            with open(_IDCACHE, encoding="utf-8") as f:
                d = json.load(f)
            if isinstance(d, dict) and d.get("root") == self.root_id:
                self._cache = d.get("paths") or {}
        except Exception:
            self._cache = {}

    def _save_cache(self):
        try:
            tmp = _IDCACHE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump({"root": self.root_id, "paths": self._cache},
                          f, ensure_ascii=False)
            os.replace(tmp, _IDCACHE)
        except Exception:
            pass

    def _rel(self, path):
        p = str(path or "").rstrip("/")
        bp = self.base_path
        if bp and p.startswith(bp):
            p = p[len(bp):]
        p = p.strip("/")
        return p  # '' = 루트, '행사관리/2026' = 하위

    def _segments(self, rel):
        return [s for s in rel.split("/") if s]

    # ------------------------------------------------------------- lookup
    def _children(self, parent_id):
        """폴더 직계 자식 전체(페이지네이션)."""
        out = []
        page = None
        svc = self._service()
        while True:
            kw = dict(q="'%s' in parents and trashed=false" % parent_id,
                      fields="nextPageToken, files(id,name,mimeType,size)",
                      pageSize=1000, supportsAllDrives=True,
                      includeItemsFromAllDrives=True)
            if page:
                kw["pageToken"] = page
            res = svc.files().list(**kw).execute()
            out.extend(res.get("files", []))
            page = res.get("nextPageToken")
            if not page:
                break
        return out

    def _resolve(self, rel, create=False):
        """rel 경로(루트 기준) → 폴더/파일 ID. create=True 면 폴더 생성."""
        rel = rel.strip("/")
        if rel == "":
            return self.root_id
        with self._lock:
            hit = self._cache.get(rel)
        if hit:
            return hit
        # 부모부터 재귀 해석
        parts = self._segments(rel)
        cur = self.root_id
        cur_rel = ""
        for i, seg in enumerate(parts):
            cur_rel = seg if not cur_rel else cur_rel + "/" + seg
            with self._lock:
                cached = self._cache.get(cur_rel)
            if cached:
                cur = cached
                continue
            found = None
            for f in self._children(cur):
                if f.get("name") == seg:
                    found = f
                    break
            if found:
                cur = found["id"]
            elif create:
                cur = self._create_folder(cur, seg)
            else:
                return None
            with self._lock:
                self._cache[cur_rel] = cur
            if i == len(parts) - 1:
                self._save_cache()
        return cur

    def _create_folder(self, parent_id, name):
        svc = self._service()
        meta = {"name": name, "mimeType": _FOLDER_MIME, "parents": [parent_id]}
        return svc.files().create(body=meta, fields="id",
                                  supportsAllDrives=True).execute()["id"]

    # ----------------------------------------------------------- interface
    def warm(self):
        try:
            self._service()
            # 루트 접근 확인
            self._service().files().get(fileId=self.root_id, fields="id",
                                        supportsAllDrives=True).execute()
            return True
        except Exception as e:
            print("GDrive warm skipped:", e)
            return None

    def list(self, path):
        rel = self._rel(path)
        fid = self._resolve(rel, create=False)
        if not fid:
            return {"ok": False, "error": "not found", "files": []}
        try:
            files = self._children(fid)
        except HttpError as e:
            return {"ok": False, "error": str(e), "files": []}
        out = []
        for f in files:
            isdir = f.get("mimeType") == _FOLDER_MIME
            try:
                size = int(f.get("size", 0) or 0)
            except Exception:
                size = 0
            out.append({"name": f.get("name", ""), "isdir": isdir,
                        "size": size,
                        "path": (self.base_path + "/" + rel + "/" + f.get("name", "")).replace("//", "/")})
        return {"ok": True, "files": out}

    def exists(self, path):
        rel = self._rel(path)
        if rel == "":
            return True
        if rel in self._cache:
            return True
        return self._resolve(rel, create=False) is not None

    def read_bytes(self, path):
        rel = self._rel(path)
        fid = self._resolve(rel, create=False)
        if not fid:
            raise FileNotFoundError(path)
        buf = io.BytesIO()
        dl = MediaIoBaseDownload(buf, self._service().files().get_media(
            fileId=fid, supportsAllDrives=True))
        done = False
        while not done:
            _, done = dl.next_chunk()
        return buf.getvalue()

    def read(self, path):
        return self.read_bytes(path).decode("utf-8", errors="replace")

    def _find_child(self, parent_id, name):
        for f in self._children(parent_id):
            if f.get("name") == name:
                return f
        return None

    def write(self, path, content_bytes):
        rel = self._rel(path)
        parts = self._segments(rel)
        if not parts:
            return {"ok": False, "error": "bad path"}
        name = parts[-1]
        parent_rel = "/".join(parts[:-1])
        pid = self._resolve(parent_rel, create=True)
        # 동일 이름이 파일/폴더로 있으면 id 재사용
        existing = self._find_child(pid, name)
        media = MediaIoBaseUpload(io.BytesIO(content_bytes),
                                  mimetype="application/octet-stream",
                                  resumable=False)
        svc = self._service()
        if existing:
            fid = existing["id"]
            svc.files().update(fileId=fid, media_body=media,
                               supportsAllDrives=True).execute()
        else:
            fid = svc.files().create(
                body={"name": name, "parents": [pid]}, media_body=media,
                fields="id", supportsAllDrives=True).execute()["id"]
        with self._lock:
            self._cache[rel] = fid
        self._save_cache()
        return {"ok": True, "id": fid, "name": name}

    def write_stream(self, path, chunks, size=None,
                     content_type="application/octet-stream"):
        """대용량 업로드 — 청크를 임시파일로 흘려 메모리를 아끼고 리줌 업로드."""
        rel = self._rel(path)
        parts = self._segments(rel)
        if not parts:
            return {"ok": False, "error": "bad path"}
        name = parts[-1]
        parent_rel = "/".join(parts[:-1])
        pid = self._resolve(parent_rel, create=True)
        tmp = tempfile.NamedTemporaryFile(delete=False, prefix="tsak_up_")
        try:
            n = 0
            for c in chunks:
                tmp.write(c)
                n += len(c)
            tmp.flush()
            tmp.close()
            with open(tmp.name, "rb") as fh:
                media = MediaIoBaseUpload(fh, mimetype=content_type,
                                          chunksize=10 * 1024 * 1024,
                                          resumable=True)
                existing = self._find_child(pid, name)
                svc = self._service()
                if existing:
                    fid = existing["id"]
                    req = svc.files().update(fileId=fid, media_body=media,
                                             supportsAllDrives=True)
                else:
                    req = svc.files().create(
                        body={"name": name, "parents": [pid]},
                        media_body=media, fields="id", supportsAllDrives=True)
                resp = None
                while resp is None:
                    _, resp = req.next_chunk()
                fid = (resp or {}).get("id") or (existing or {}).get("id")
            with self._lock:
                self._cache[rel] = fid
            self._save_cache()
            return {"ok": True, "id": fid, "size": n}
        finally:
            try:
                os.remove(tmp.name)
            except Exception:
                pass

    def mkdir(self, parent, name):
        rel_parent = self._rel(parent)
        pid = self._resolve(rel_parent, create=True)
        existing = self._find_child(pid, name)
        if existing:
            # 이미 있으면 그대로(멱등) — FileStation 의 409 대신 조용히 성공 처리
            with self._lock:
                self._cache[(rel_parent + "/" + name).strip("/")] = existing["id"]
            self._save_cache()
            return {"ok": True, "existed": True, "id": existing["id"]}
        fid = self._create_folder(pid, name)
        with self._lock:
            self._cache[(rel_parent + "/" + name).strip("/")] = fid
        self._save_cache()
        return {"ok": True, "id": fid}

    def _id_of(self, path, allow_create_folder=False):
        rel = self._rel(path)
        fid = self._resolve(rel, create=allow_create_folder)
        if fid:
            return fid, rel
        # 파일명이 캐시에 없으면 부모에서 이름 검색
        parts = self._segments(rel)
        if len(parts) >= 2:
            pid = self._resolve("/".join(parts[:-1]), create=False)
            if pid:
                f = self._find_child(pid, parts[-1])
                if f:
                    with self._lock:
                        self._cache[rel] = f["id"]
                    return f["id"], rel
        return None, rel

    def delete(self, path):
        fid, rel = self._id_of(path)
        if not fid:
            return {"ok": False, "error": "not found"}
        try:
            self._service().files().delete(fileId=fid,
                                           supportsAllDrives=True).execute()
        except HttpError as e:
            return {"ok": False, "error": str(e)}
        with self._lock:
            for k in list(self._cache.keys()):
                if k == rel or k.startswith(rel + "/"):
                    self._cache.pop(k, None)
        self._save_cache()
        return {"ok": True}

    def rename(self, path, new_name):
        fid, rel = self._id_of(path)
        if not fid:
            return {"ok": False, "error": "not found"}
        self._service().files().update(
            fileId=fid, body={"name": new_name},
            supportsAllDrives=True).execute()
        with self._lock:
            for k in list(self._cache.keys()):
                if k == rel or k.startswith(rel + "/"):
                    self._cache.pop(k, None)
            self._cache[("/".join(rel.split("/")[:-1]) + "/" + new_name).strip("/")] = fid
        self._save_cache()
        return {"ok": True}

    def move(self, src, dest_parent):
        fid, rel = self._id_of(src)
        if not fid:
            return {"ok": False, "error": "not found"}
        old_parent = self._resolve("/".join(rel.split("/")[:-1]), create=False)
        new_parent = self._resolve(self._rel(dest_parent), create=True)
        svc = self._service()
        kw = dict(fileId=fid, supportsAllDrives=True)
        if new_parent:
            kw["addParents"] = new_parent
        if old_parent:
            kw["removeParents"] = old_parent
        svc.files().update(**kw).execute()
        with self._lock:
            for k in list(self._cache.keys()):
                if k == rel or k.startswith(rel + "/"):
                    self._cache.pop(k, None)
        self._save_cache()
        return {"ok": True}

    def get_info(self, path):
        fid, rel = self._id_of(path)
        if not fid:
            return {"ok": False, "error": "not found"}
        try:
            f = self._service().files().get(
                fileId=fid, fields="id,name,size,mimeType",
                supportsAllDrives=True).execute()
        except HttpError as e:
            return {"ok": False, "error": str(e)}
        try:
            size = int(f.get("size", 0) or 0)
        except Exception:
            size = 0
        return {"ok": True, "size": size, "name": f.get("name", "")}


# ============================================================================
# 마이그레이션 — 나스 전체 트리를 구글드라이브로 복사
# ============================================================================
def migrate_from_nas(nas, gdrive, base_path, *, on_progress=None,
                     skip_ext=(), dry_run=False):
    """나스(base_path 이하 전체)를 구글드라이브로 재귀 복사한다.

    · 폴더 구조를 그대로 재현하고, 파일(JSON·이미지·동영상 등)을 업로드한다.
    · 이미 같은 이름/크기의 파일이 드라이브에 있으면 건너뛴다(재개 가능).
    · on_progress(done, total, path) 콜백으로 진행률을 보고한다.
    반환: {"ok":bool, "files":n, "folders":n, "skipped":n, "errors":[...]}
    """
    stats = {"files": 0, "folders": 0, "skipped": 0, "errors": []}
    base_path = base_path.rstrip("/")
    skip_low = tuple(x.lower() for x in skip_ext)

    def _walk(nas_dir, gd_dir):
        try:
            r = nas.list(nas_dir)
        except Exception as e:
            stats["errors"].append("%s: %s" % (nas_dir, e))
            return
        if not r.get("ok"):
            return
        for f in r.get("files", []):
            nm = f.get("name", "")
            if not nm or nm.startswith("."):
                continue
            npath = nas_dir + "/" + nm
            gpath = gd_dir + "/" + nm
            if f.get("isdir"):
                if on_progress:
                    on_progress(npath, "folder")
                if not dry_run:
                    try:
                        gdrive.mkdir(gd_dir, nm)
                    except Exception as e:
                        stats["errors"].append("mkdir %s: %s" % (gpath, e))
                        continue
                stats["folders"] += 1
                _walk(npath, gpath)
            else:
                ext = ("." + nm.rsplit(".", 1)[-1].lower()) if "." in nm else ""
                if skip_low and ext in skip_low:
                    stats["skipped"] += 1
                    continue
                if on_progress:
                    on_progress(npath, "file")
                if dry_run:
                    stats["files"] += 1
                    continue
                try:
                    # 이미 있고 크기가 같으면 건너뜀(재개)
                    try:
                        gi = gdrive.get_info(gpath)
                    except Exception:
                        gi = {"ok": False}
                    if gi.get("ok") and int(gi.get("size", -1)) == int(f.get("size", -2)):
                        stats["skipped"] += 1
                        continue
                    data = nas.read_bytes(npath)
                    gdrive.write(gpath, data)
                    stats["files"] += 1
                except Exception as e:
                    stats["errors"].append("copy %s: %s" % (npath, e))

    def _walk_root():
        try:
            r = nas.list(base_path)
        except Exception as e:
            stats["errors"].append("root: %s" % e)
            return
        if not r.get("ok"):
            stats["errors"].append("root list 실패")
            return
        for f in r.get("files", []):
            nm = f.get("name", "")
            if not nm or nm.startswith("."):
                continue
            npath = base_path + "/" + nm
            gpath = "/" + nm           # base_path 아래를 드라이브 루트로 매핑
            if f.get("isdir"):
                if not dry_run:
                    try:
                        gdrive.mkdir("/", nm)
                    except Exception as e:
                        stats["errors"].append("mkdir %s: %s" % (gpath, e))
                        continue
                stats["folders"] += 1
                if on_progress:
                    on_progress(npath, "folder")
                _walk(npath, gpath)
            else:
                if on_progress:
                    on_progress(npath, "file")
                if dry_run:
                    stats["files"] += 1
                    continue
                try:
                    gi = gdrive.get_info(gpath)
                except Exception:
                    gi = {"ok": False}
                if gi.get("ok") and int(gi.get("size", -1)) == int(f.get("size", -2)):
                    stats["skipped"] += 1
                    continue
                try:
                    data = nas.read_bytes(npath)
                    gdrive.write(gpath, data)
                    stats["files"] += 1
                except Exception as e:
                    stats["errors"].append("copy %s: %s" % (npath, e))

    _walk_root()
    stats["ok"] = len(stats["errors"]) == 0
    return stats
