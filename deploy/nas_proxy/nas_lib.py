"""Synology DSM FileStation API 클라이언트 (쿠키 세션 방식)

[성능] NAS(원격, HTTPS)와의 통신은 매 호출마다 새 TLS 연결을 열면
핸드셰이크 비용으로 무겁다. 전역 keep-alive **연결 풀**을 재사용한다.

⚠️ 종전에는 전역 락(_CONN_LOCK) + 단일 연결이라 **모든 NAS 호출이 직렬화**
되어, 행사 1건 조회에 NAS를 5~10회 부르면 230ms×N = 1~3초가 걸렸다
(실측: 병렬 3회 = 718ms → 완전 직렬). 이제 연결 풀(기본 8개)로 **병렬 수행**
하여 동일 작업이 약 1회 왕복(≈230ms)으로 끝난다.
"""
import os, urllib.request, urllib.parse, ssl, json, time, threading, hashlib

#  ─────────────────────────────────────────────────────────────────────────
#  [가비아 이전 2026-11-20] ★ TLS 검증을 "끄지 않고" 고정(pinning)한다 ★
#
#  ## 왜 껐었나
#   NAS 는 자체서명 인증서(CN=synology, Synology Inc. CA)를 쓴다.
#   기본 컨텍스트로는 검증에 실패하므로 `CERT_NONE` 으로 **검증을 통째로 껐다.**
#   그런데 가비아로 이전하면 서버↔NAS 구간이 **공인 인터넷을 지난다.**
#   검증이 꺼진 상태에서는 중간자가 인증서만 바꿔치기하면 비밀번호와 자료가
#   그대로 노출된다. "같은 방 안의 위험"이 "인터넷에 노출된 위험"이 되는 순간이다.
#
#  ## 왜 그냥 켜면 안 되나
#   `verify_mode = CERT_REQUIRED` 로 바꾸면 Synology 사설 CA 를 신뢰하지 않으므로
#   **모든 NAS 호출이 즉시 실패**한다. 앱이 통째로 죽는다.
#
#  ## 그래서: 인증서 지문 고정 (TOFU)
#   자체서명서명이어도 **우리가 아는 그 인증서인지**는 검증할 수 있다.
#   현재 인증서의 SHA-256 지문을 박아 두고, 접속할 때마다 대조한다.
#     · 지문 일치  → 통과 (자체서명이어도 안전: 다른 인증서로 바꿔치기 불가)
#     · 지문 불일치 → 즉시 실패 (중간자 또는 NAS 인증서 교체)
#
#   실측 지문 (2026-11-20, 39.123.241.4:5001):
#     6B:3A:01:8E:77:F9:9B:24:D5:D4:82:73:32:86:96:4A:
#     F2:EA:69:2B:00:15:0E:90:EC:DF:84:31:6A:C7:E5:2B
#   유효기간: 2026-05-01 ~ 2027-05-02
#
#  ## ⚠️ NAS 인증서를 갱신하면 지문이 바뀐다 → 그때는 이 값을 교체해야 한다.
#     교체 방법:  TSAK_NAS_CERT_SHA256=<새지문> 환경변수로 임시 통과시킨 뒤
#                 아래 상수에 반영. (환경변수만으로도 동작하므로 긴급 우회 가능)
#     DSM 이 자체서명을 다시 만들면 지문이 달라진다. 로그에 무엇이 기대값인지
#     찍히므로 원인 파악이 어렵지 않다.
#  ─────────────────────────────────────────────────────────────────────────
NAS_CERT_SHA256 = (
    "6b3a018e77f99b24d5d48273328"
    "6964af2ea692b00150e90ecdf84316ac7e52b"
)

#  검증 정책:  "pin"    = 지문 고정 (권장, 기본)
#              "strict" = 공인 CA 체인 검증 (NAS 에 공인인증서를 설치했을 때)
#              "off"    = 검증 안 함 (개발/응급 전용 — 절대 운영 기본값으로 두지 말 것)
TLS_MODE = (os.environ.get("TSAK_NAS_TLS_MODE") or "pin").strip().lower()


class _CertPinError(ssl.SSLError):
    """NAS 인증서 지문이 기대값과 다를 때 발생. 원인을 사람이 읽을 수 있게 남긴다."""


def build_tls_context():
    """NAS 접속용 SSL 컨텍스트를 만든다 (정책에 따라 세 갈래).

    반환: (ctx, applied_mode)
    """
    expect = (os.environ.get("TSAK_NAS_CERT_SHA256") or NAS_CERT_SHA256)
    expect = expect.replace(":", "").replace(" ", "").strip().lower()
    mode = TLS_MODE

    if mode == "off":
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        print("[tls] ⚠️ NAS TLS 검증 꺼짐(off) — 운영에서 쓰지 마세요")
        return ctx, "off"

    if mode == "strict":
        ctx = ssl.create_default_context()
        ctx.check_hostname = True
        ctx.verify_mode = ssl.CERT_REQUIRED
        print("[tls] NAS TLS = strict (공인 CA 체인 검증)")
        return ctx, "strict"

    # 기본: 지문 고정. 자체서명을 허용하되 **그 인증서만** 허용한다.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False          # CN=synology 는 IP와 불일치 → 이름검사 생략
    ctx.verify_mode = ssl.CERT_NONE     # 체인검증 생략 (자체서명) ...

    # ... 대신 **핸드셰이크 직후 지문을 직접 대조**한다.
    #  파이썬은 SSLContext 에 post-handshake 훅을 주지 않으므로,
    #  `wrap_socket` 을 감싸 지문을 검사한다.
    _orig_wrap = ctx.wrap_socket

    def _wrap_pinned(sock, *a, **kw):
        ssock = _orig_wrap(sock, *a, **kw)
        try:
            der = ssock.getpeercert(binary_form=True) or b""
            got = hashlib.sha256(der).hexdigest()
        except Exception as e:
            try: ssock.close()
            except Exception: pass
            raise _CertPinError("NAS 인증서를 읽지 못했습니다: %s" % e)
        if not got:
            try: ssock.close()
            except Exception: pass
            raise _CertPinError("NAS 가 인증서를 제시하지 않았습니다")
        if expect and got != expect:
            try: ssock.close()
            except Exception: pass
            raise _CertPinError(
                "NAS 인증서 지문 불일치 — 중간자 또는 NAS 인증서 교체 의심\n"
                "  기대: %s\n  실제: %s\n"
                "  · NAS 인증서를 정상 갱신했다면 nas_lib.py 의 NAS_CERT_SHA256 을 갱신하세요.\n"
                "  · TSAK_NAS_CERT_SHA256=<지문> 으로 임시 통과도 가능합니다." % (expect, got))
        return ssock

    try:
        ctx.wrap_socket = _wrap_pinned      # type: ignore[assignment]
    except Exception as e:
        print("[tls] ⚠️ 지문 고정 훅 설치 실패 — strict 로 대체 시도:", e)
        ctx2 = ssl.create_default_context()
        ctx2.check_hostname = True
        ctx2.verify_mode = ssl.CERT_REQUIRED
        return ctx2, "strict"
    print("[tls] NAS TLS = pin (지문 고정 %s…)" % (expect[:16] or "(미설정)"))
    return ctx, "pin"


# ---- 전역 keep-alive 연결 풀 (호스트별 N개) ----
_CONN_TTL = 100.0          # 초. 이 시간 넘게 미사용이면 연결 폐기



class _ConnPool:
    """호스트별 keep-alive 연결 풀 — 동시 NAS 호출을 병렬로 처리한다."""

    def __init__(self, max_size=8):
        self.max_size = max(1, int(max_size))
        self._idle = {}                     # host -> [(conn, ts), ...]
        self._lock = threading.Lock()
        self._sem = threading.Semaphore(self.max_size)

    def acquire(self, host, ctx):
        self._sem.acquire()
        now = time.time()
        with self._lock:
            stack = self._idle.get(host)
            while stack:
                conn, ts = stack.pop()
                if now - ts < _CONN_TTL:
                    return conn
                try:
                    conn.close()
                except Exception:
                    pass
        import http.client
        return http.client.HTTPSConnection(host, timeout=90, context=ctx)

    def release(self, host, conn):
        with self._lock:
            self._idle.setdefault(host, []).append((conn, time.time()))
        self._sem.release()

    def discard(self, host, conn):
        try:
            conn.close()
        except Exception:
            pass
        self._sem.release()

    def stats(self):
        with self._lock:
            return {h: len(s) for h, s in self._idle.items()}


_POOL = _ConnPool(int(os.environ.get("TSAK_NAS_POOL", "8")))


class NasClient:
    def __init__(self, base, user, pw):
        self.base = base.rstrip('/')
        self.user = user
        self.pw = pw
        self.ctx, self.tls_mode = build_tls_context()
        self.cookie = None
        self._host = self.base.split("//", 1)[-1]

    # ---- 저수준: keep-alive 연결(풀)로 리소스 경로에 POST 바디 전송 ----
    def _conn_post(self, path, body, cookie=None, content_type=None,
                   extra_headers=None):
        """풀에서 연결을 빌려 POST 수행 후 (status, headers, bytes) 반환.

        연결이 끊겨 있으면(RemoteDisconnected 등) 새 연결로 1회 재시도한다.
        응답 후 연결은 풀에 반납(release)되어 다음 호출이 즉시 재사용한다.
        """
        headers = {}
        if content_type:
            headers["Content-Type"] = content_type
        if cookie:
            headers["Cookie"] = cookie
        if extra_headers:
            headers.update(extra_headers)
        last_err = None
        for attempt in (0, 1):
            conn = _POOL.acquire(self._host, self.ctx)
            try:
                conn.request("POST", path, body=body, headers=headers)
                resp = conn.getresponse()
                data = resp.read()
                hdrs = resp.headers
                status = resp.status
                _POOL.release(self._host, conn)
                return status, hdrs, data
            except Exception as e:
                last_err = e
                _POOL.discard(self._host, conn)
        raise last_err

    def _login(self):
        p = {"api":"SYNO.API.Auth","version":"6","method":"login",
             "account":self.user,"passwd":self.pw,"session":"FileStation","format":"cookie"}
        data = urllib.parse.urlencode(p).encode()
        status, hdrs, raw = self._conn_post(
            "/webapi/entry.cgi", data,
            content_type="application/x-www-form-urlencoded")
        sc = hdrs.get_all("Set-Cookie") or []
        j = json.loads(raw.decode())
        if not j.get("success"):
            raise RuntimeError("NAS login failed: %s" % j)
        self.cookie = "; ".join([c.split(";")[0] for c in sc])
        return j

    def _post(self, params, cookie=None, timeout=60):
        """entry.cgi 로 params POST → JSON dict. (연결 재사용)"""
        data = urllib.parse.urlencode(params).encode()
        status, hdrs, raw = self._conn_post(
            "/webapi/entry.cgi", data, cookie=cookie,
            content_type="application/x-www-form-urlencoded")
        return json.loads(raw.decode())

    def call(self, params, retry=True):
        if not self.cookie:
            self._login()
        try:
            return self._post(params, cookie=self.cookie)
        except Exception as e:
            if retry:
                self.cookie = None
                self._login()
                return self.call(params, retry=False)
            raise

    def warm(self):
        """기동 워밍: TLS 연결 + 로그인 + 경량 조회를 미리 수행.

        첫 사용자 요청 시 콜드 TLS 핸드셰이크·인증 지연이 발생하지 않도록
        프록시 부팅 직후 백그라운드 스레드에서 호출한다. 실패해도 치명적이지
        않다(다음 실제 요청에서 정상 재시도됨).
        """
        try:
            if not self.cookie:
                self._login()
            # 경량 API 1회로 연결/세션 유효성까지 확인
            return self.call({"api": "SYNO.API.Info", "version": "1",
                              "method": "query", "query": "SYNO.FileStation.List"})
        except Exception:
            return None

    # --- high level ---
    def list(self, path):
        r = self.call({"api":"SYNO.FileStation.List","version":"2","method":"list",
                       "folder_path":path, "additional":'["real_path","size","type","perm"]'})
        if not r.get("success"):
            return {"ok": False, "error": r}
        return {"ok": True, "files": [
            {"name":f["name"], "isdir":f.get("isdir",False),
             "size":f.get("additional",{}).get("size",0),
             "path":f.get("path","")} for f in r["data"]["files"]]}

    def read_bytes(self, path):
        if not self.cookie: self._login()
        p = {"api":"SYNO.FileStation.Download","version":"2","method":"download",
             "path":'["%s"]' % path, "mode":"open"}
        try:
            data = urllib.parse.urlencode(p).encode()
            status, hdrs, raw = self._conn_post(
                "/webapi/entry.cgi", data, cookie=self.cookie,
                content_type="application/x-www-form-urlencoded")
            return raw
        except Exception:
            # 연결이 끊긴 경우: 재로그인 후 1회 재시도
            self.cookie = None
            self._login()
            data = urllib.parse.urlencode(p).encode()
            status, hdrs, raw = self._conn_post(
                "/webapi/entry.cgi", data, cookie=self.cookie,
                content_type="application/x-www-form-urlencoded")
            return raw

    def read(self, path):
        return self.read_bytes(path).decode("utf-8", errors="replace")

    def read_range(self, path, start, length):
        """[start, start+length) 구간만 내려받는다.

        ## 왜 필요한가 (turn53)
         추모관 업로드 상한을 500MB 로 올리면서, 영상 재생·탐색(Range 요청)을
         지원해야 했다. 종전에는 파일 전체를 받아 잘라 보냈으므로 500MB 영상을
         1초 보려 해도 500MB 를 내려받았다.

        ## 실측 (2026-11-04)
         Synology FileStation.Download 에 `Range` 헤더를 붙이면 **정말로 206** 과
         `Content-Range` 를 돌려주고, 본문도 요청한 구간만 온다.
         (3,038,408 바이트 파일에 `bytes=1000-1999` → 정확히 1000 바이트 수신 확인)

        ## 실패 시
         서버가 Range 를 무시하고 전체를 주면(=길이가 요청보다 크면) 그중 구간만
         잘라 돌려준다. 헤더 자체를 거부하면 b"" 를 돌려주고 호출부가 다른
         경로(전체 읽기)로 폴백한다.
        """
        if length <= 0:
            return b""
        if not self.cookie:
            self._login()
        p = {"api": "SYNO.FileStation.Download", "version": "2",
             "method": "download", "path": '["%s"]' % path, "mode": "open"}
        data = urllib.parse.urlencode(p).encode()
        hdrs = {"Range": "bytes=%d-%d" % (start, start + length - 1)}
        for attempt in (0, 1):
            try:
                status, hh, raw = self._conn_post(
                    "/webapi/entry.cgi", data, cookie=self.cookie,
                    content_type="application/x-www-form-urlencoded",
                    extra_headers=hdrs)
                if status == 206:
                    return raw[:length]
                if status == 200:
                    # Range 를 무시하고 전체를 준 경우 — 구간만 잘라낸다.
                    return raw[start:start + length]
                if status == 416:
                    return b""
                return b""
            except Exception:
                if attempt == 0:
                    self.cookie = None
                    self._login()
                    continue
                raise
        return b""

    def write(self, path, content_bytes):
        boundary = "----TSAKBOUNDARY7d01"
        # multipart with fields + file
        def field(name, value):
            return (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n").encode()
        body = b""
        body += field("api","SYNO.FileStation.Upload")
        body += field("version","2")
        body += field("method","upload")
        body += field("path","/".join(path.split("/")[:-1]) or "/")
        body += field("create_parents","true")
        body += field("overwrite","true")
        fname = path.split("/")[-1]
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{fname}\"\r\n"
                 f"Content-Type: application/octet-stream\r\n\r\n").encode()
        body += content_bytes
        body += b"\r\n"
        body += f"--{boundary}--\r\n".encode()
        if not self.cookie: self._login()
        req = urllib.request.Request(self.base+"/webapi/entry.cgi", data=body)
        req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
        req.add_header("Cookie", self.cookie)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=120) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            self.cookie = None; self._login()
            req2 = urllib.request.Request(self.base+"/webapi/entry.cgi", data=body)
            req2.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
            req2.add_header("Cookie", self.cookie)
            with urllib.request.urlopen(req2, context=self.ctx, timeout=120) as r:
                return json.loads(r.read().decode())

    def mkdir(self, parent, name):
        r = self.call({"api":"SYNO.FileStation.CreateFolder","version":"2","method":"create",
                       "folder_path":parent, "name":'["%s"]' % name})
        return r

    def delete(self, path):
        r = self.call({"api":"SYNO.FileStation.Delete","version":"2","method":"delete",
                       "path":'["%s"]' % path})
        return r

    def move(self, src, dest_parent):
        r = self.call({"api":"SYNO.FileStation.Move","version":"2","method":"move",
                       "path":'["%s"]' % src, "dest_folder_path":dest_parent,
                       "overwrite":"true", "remove_src":"true"})
        return r

    def rename(self, path, new_name):
        """동일 위치에서 이름 변경 (FileStation.Rename)."""
        r = self.call({"api":"SYNO.FileStation.Rename","version":"2","method":"rename",
                       "path":'["%s"]' % path, "name":'["%s"]' % new_name})
        return r

    def get_info(self, path):
        r = self.call({"api":"SYNO.FileStation.List","version":"2","method":"getinfo",
                       "path":'["%s"]' % path,
                       "additional":'["real_path","size","type","perm"]'})
        if not r.get("success"):
            return {"ok": False, "error": r}
        f = r["data"]["files"][0]
        return {"ok": True, "size": f.get("additional", {}).get("size", 0),
                "name": f.get("name", "")}

    def write_stream(self, path, chunks, size=None, content_type="application/octet-stream"):
        """대용량 파일 스트리밍 업로드 (메모리 절약).

        chunks: bytes 이터러블(file.read 청크 등). 전체를 메모리에 올리지 않는다.
        """
        boundary = "----TSAKSTREAM9f13"
        parent = "/".join(path.split("/")[:-1]) or "/"
        fname = path.split("/")[-1]
        head = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"api\"\r\n\r\n"
            f"SYNO.FileStation.Upload\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"version\"\r\n\r\n2\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"method\"\r\n\r\nupload\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"path\"\r\n\r\n{parent}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"create_parents\"\r\n\r\ntrue\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{fname}\"\r\n"
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode()
        tail = f"\r\n--{boundary}--\r\n".encode()
        total = None
        if size is not None:
            total = len(head) + int(size) + len(tail)

        class _Body:
            def __init__(self):
                self._parts = [head]
                self._chunks = iter(chunks)
                self._done_head = False
                self._done_body = False
                self._finished = False
                self._buf = b""

            def read(self, n=-1):
                if n is None or n < 0:
                    n = 65536
                # 스트림 종료(EOF) 후에는 반드시 빈 바이트를 반환해야 한다.
                # (이전 구현은 EOF 를 알리지 못하고 boundary tail 을 무한 반복 반환해
                #  업로드 본문이 '------TSAKSTREAM…' 경계 문자열로 오염되었다.)
                if self._finished and not self._buf:
                    return b""
                while len(self._buf) < n and not self._finished:
                    if not self._done_head:
                        self._buf += self._parts.pop()
                        if not self._parts:
                            self._done_head = True
                        continue
                    if not self._done_body:
                        try:
                            self._buf += next(self._chunks)
                            continue
                        except StopIteration:
                            self._done_body = True
                            continue
                    # 본문 끝 → boundary tail 1회만 추가하고 스트림 종료
                    self._buf += tail
                    self._finished = True
                out, self._buf = self._buf[:n], self._buf[n:]
                return out

            def __len__(self):
                return total if total is not None else 0

        if not self.cookie:
            self._login()
        body = _Body()
        headers = {"Content-Type": f"multipart/form-data; boundary={boundary}",
                   "Cookie": self.cookie}
        if total is not None:
            headers["Content-Length"] = str(total)
        req = urllib.request.Request(self.base + "/webapi/entry.cgi", data=body, headers=headers)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=600) as r:
                return json.loads(r.read().decode())
        except Exception:
            self.cookie = None
            self._login()
            body = _Body()
            headers["Cookie"] = self.cookie
            req = urllib.request.Request(self.base + "/webapi/entry.cgi", data=body, headers=headers)
            with urllib.request.urlopen(req, context=self.ctx, timeout=600) as r:
                return json.loads(r.read().decode())

    def exists(self, path):
        parent = "/".join(path.split("/")[:-1]) or "/"
        name = path.split("/")[-1]
        r = self.list(parent)
        if not r.get("ok"): return False
        return any(f["name"] == name for f in r["files"])
