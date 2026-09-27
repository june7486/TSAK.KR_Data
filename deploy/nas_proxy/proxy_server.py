"""
TSAK 인가자 관리 — NAS 프록시 서버
브라우저(Flutter Web)는 NAS에 직접 접속할 수 없으므로(자체서명 인증서/CORS),
이 프록시가 앱과 Synology NAS 사이를 중계한다.

Endpoints:
  GET  /api/health
  POST /api/login           {tier, value}
  GET  /api/members
  POST /api/members         {members:[...]}
  GET  /api/meta
  GET  /api/backups
  POST /api/backup          {name}
  POST /api/restore         {name}
  POST /api/photo/<no>      (raw body)
  GET  /api/photo/<no>
  GET  /api/config
  POST /api/config
"""
import json, os, re, ssl, sys, threading, time, datetime, base64, gzip, hashlib, urllib.parse

# brotli(선택) — 있으면 gzip 대신 더 작은 압축 전송
try:
    import brotli as _brotli  # type: ignore
except Exception:
    _brotli = None

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nas_lib import NasClient

HERE = os.path.dirname(os.path.abspath(__file__))
CONF = json.load(open(os.path.join(HERE, "config.json"), encoding="utf-8"))

NAS = NasClient(CONF["nas"]["base"], CONF["nas"]["user"], CONF["nas"]["pw"])
BASE = CONF["nas"]["base_path"]          # /92_Tiger_app_data/TSAK_인가자관리
DB_FILE = BASE + "/db/members.json"
META_FILE = BASE + "/db/meta.json"
CFG_FILE = BASE + "/db/config.json"
FIN_FILE = BASE + "/db/finance.json"
IMP_FILE = BASE + "/db/import_log.json"
MAT_FILE = BASE + "/db/mat_rules.json"      # 입금자 자동분류 규칙/별칭
DATA_DIR = BASE + "/기본자료"
EVENT_DIR = BASE + "/행사관리"              # 행사 사진·동영상 갤러리 (무제한)
EVENT_THUMB_DIR = EVENT_DIR + "/.thumbnails"
EVENT_MEDIA_FILE = BASE + "/db/event_media.json"  # 행사 파일 메타(썸네일/태그)
EVENTS_FILE = BASE + "/db/events.json"       # 행사 정의(연도/행사명/정보/참석자/상태)
REGULAR_FILE = BASE + "/db/regular_passwords.json"  # 일반회원(비인가자) 접속 비번
INQUIRY_FILE = BASE + "/db/inquiries.json"   # 문의 접수 로그 (동의·개인정보)
INQUIRY_DIR = BASE + "/문의첨부"             # 문의 첨부파일 저장 폴더
ACCESS_LOG_FILE = BASE + "/db/access_log.json"  # 회원 접속 로그(로그인 이력)
LOCK = threading.Lock()

# 행사별 하위 폴더(항목) — 번호+한글명, 업로드 가능 폴더엔 "_(업로드가능)" 꼬리말
EVENT_SUBFOLDERS = [
    ("01_계획서_(업로드가능)", "plan", True),
    ("02_참석자_(업로드가능)", "attendees", True),
    ("03_사진+동영상_(업로드가능)", "media", True),
    ("04_참가비·후원금", "fee", False),
    ("05_행사비지출내역", "expense", False),
]
# 항목 key → 폴더명
EVENT_SUB_BY_KEY = {k: n for (n, k, _) in EVENT_SUBFOLDERS}
# 참가자(개인) 접근이 허용되는 하위 폴더 key (사진+동영상만)
PARTICIPANT_KEYS = {"media"}
# 업로드 가능(색인/샘플 생성 대상) key
UPLOAD_KEYS = {k for (_, k, up) in EVENT_SUBFOLDERS if up}
# 참석자 항목(복수 선택)
ATTENDEE_ROLES = [
    "지도자", "멘토지도자", "비버", "스카우트", "벤처",
    "로버", "본부", "학부모", "기타",
]

# 기본자료 하위 폴더 (파일 첨부 → 자동분석)
SUB_FOLDERS = {
    "member_list": "인가자명단",
    "roster": "명단",
    "bank": "은행거래내역",
    "donation": "후원현황",
    "expense": "지출내역",
    "event": "행사자료",
}
HIST_FILE = BASE + "/db/finance_history.json"  # 연도/월별 스냅샷(집계 캐시)

MASTER_PW = CONF["auth"]["master"]        # Corbuser7!@@ (immutable)
APP_PW = CONF["auth"]["app"]              # Tsak1988!!

# 영구 마스터 인가번호 — 해당 인가번호는 마스터 비번 없이도 마스터 작업 가능.
# 앱은 master 필드에 "PM:<인가번호>" 토큰을 보낸다.
PERMANENT_MASTERS = {"415"}
_BROKEN_JPEG = None  # 손상 이미지 대체용 플레이스홀더 캐시


def _is_master_val(v):
    """마스터 권한 확인값이 유효한지 (비번 또는 영구 마스터 토큰)."""
    s = str(v or "")
    if s == MASTER_PW:
        return True
    if s.startswith("PM:"):
        no = re.sub(r"[^0-9]", "", s[3:])
        return no in PERMANENT_MASTERS
    return False


# ============================================================================
#  서버측 세션 인증 (보안 감사 F01/F02 대응)
#  - 로그인 성공 시 서버가 1회용 세션토큰을 발급한다.
#  - 세션토큰 없이는 민감 API(members/finance/backups/files/... )가 응답하지 않는다.
#  - 웹 앱은 동일 출처라 쿠키(tsak_sid)로 자동 전송, 비웹 클라이언트는
#    X-TSAK-Session 헤더 또는 ?sid= 쿼리로 전달한다.
# ============================================================================
_SESS = {}                      # sid -> {tier, who, exp}
_SESS_TTL = 60 * 60 * 8         # 8시간
_SESS_LOCK = threading.Lock()
# 암호학적 난수 (토큰 추측 방지)
import secrets as _secrets

# CORS 허용 출처 (보안 감사 F02)
#  · 동일 출처는 자동 허용. 여기에는 앱 배포 도메인만 명시한다.
CORS_ALLOW_ORIGINS = [
    "https://tsak.kr",
    "https://www.tsak.kr",
    ".sandbox.novita.ai",   # 앱 배포(샌드박스) 출처
]


def _sess_new(tier, who=""):
    sid = _secrets.token_urlsafe(32)
    with _SESS_LOCK:
        # 오래된 세션 정리
        now = time.time()
        for k in [k for k, v in _SESS.items() if v.get("exp", 0) < now]:
            _SESS.pop(k, None)
        _SESS[sid] = {"tier": tier, "who": who, "exp": now + _SESS_TTL}
    return sid


def _sess_get(sid):
    if not sid:
        return None
    with _SESS_LOCK:
        v = _SESS.get(sid)
    if not v:
        return None
    if v.get("exp", 0) < time.time():
        with _SESS_LOCK:
            _SESS.pop(sid, None)
        return None
    return v


def _sess_del(sid):
    with _SESS_LOCK:
        _SESS.pop(sid, None)


# ============================================================================
#  회원 접속 로그 (요구: 마스터만 열람, 개인 페이지 하단 최근 100건, 기기명 등)
# ============================================================================
_ACCESS_LOG_MAX = 2000            # 파일에 보관하는 최대 로그 수(최신 우선)
_ACCESS_LOG_LOCK = threading.Lock()


def _ua_device_name(ua):
    """User-Agent 문자열 → 사람이 읽는 기기명."""
    ua = str(ua or "")
    low = ua.lower()
    os_name = "기타"
    if "windows" in low:
        os_name = "Windows"
    elif "android" in low:
        os_name = "Android"
    elif "iphone" in low or "ipad" in low or "ios" in low:
        os_name = "iOS"
    elif "mac os" in low or "macintosh" in low:
        os_name = "macOS"
    elif "linux" in low:
        os_name = "Linux"
    browser = "브라우저"
    if "edg" in low:
        browser = "Edge"
    elif "whale" in low:
        browser = "Whale"
    elif "chrome" in low:
        browser = "Chrome"
    elif "safari" in low:
        browser = "Safari"
    elif "firefox" in low:
        browser = "Firefox"
    elif "kakao" in low:
        browser = "카카오"
    return f"{os_name} · {browser}"


def _access_log_all():
    return _load_json(ACCESS_LOG_FILE, {"logs": []})


def _access_log_append(entry):
    """접속 로그 1건 추가 (최신 우선, 최대 _ACCESS_LOG_MAX 유지)."""
    try:
        with _ACCESS_LOG_LOCK:
            doc = _load_json(ACCESS_LOG_FILE, {"logs": []})
            logs = doc.get("logs", [])
            logs.insert(0, entry)
            doc["logs"] = logs[:_ACCESS_LOG_MAX]
            doc["updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            _save_json(ACCESS_LOG_FILE, doc)
    except Exception as e:
        print("access log append fail", e)


def _access_log_for(ident):
    """특정 회원(인가번호/전화)의 로그 — 최신 100건."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d:
        return []
    out = []
    for it in _access_log_all().get("logs", []):
        if str(it.get("ident", "")) == d:
            out.append(it)
            if len(out) >= 100:
                break
    return out


def _log_access_login(tier, role, ident, who, ua, ip, extra=None):
    """로그인 성공 시 접속 로그 1건 기록.

    ident: 조회 키(개인=인가번호, 손님=전화숫자) — 비어도 기록은 남긴다.
    who:   표시용 신원(인가번호/전화).
    """
    ident = re.sub(r"[^0-9]", "", str(ident or ""))
    who = str(who or "")
    name = ""
    try:
        m = _ev_member_by_ident(ident) if ident else None
        if m:
            name = str(m.get("name", ""))
            if not ident:
                ident = re.sub(r"[^0-9]", "", str(m.get("number", "")))
    except Exception:
        pass
    entry = {
        "ts": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "tier": str(tier or ""),
        "role": str(role or ""),
        "ident": ident,
        "who": who,
        "name": name,
        "device": _ua_device_name(ua),
        "ua": str(ua or "")[:300],
        "ip": str(ip or ""),
    }
    if extra:
        entry.update(extra)
    _access_log_append(entry)
    return entry


def _scope_members(tier, who, members):
    """역할별 최소 항목 제공(대량 명단 열람 최소화).

    - 관리자(app)·마스터: 전체
    - 개인(personal): 본인 1건만 + 민감 필드 제거
    - 비인가자(guest): 본인 1건만 + 민감 필드 제거
    """
    who = re.sub(r"[^0-9]", "", str(who or ""))
    if tier in ("app", "master"):
        return members
    out = []
    for m in members:
        num = re.sub(r"[^0-9]", "", str(m.get("number", "")))
        lid = re.sub(r"[^0-9]", "", str(m.get("loginId", "")))
        ph = re.sub(r"[^0-9]", "", str(m.get("phone", "")))
        if who and who in (num, lid, ph):
            out.append(_redact_member(m))
    return out


def _redact_member(m):
    """일반 열람 응답에서 제외해야 하는 민감 필드 제거(F01)."""
    m = dict(m)
    for k in ("personalPassword", "password", "pw", "memo", "photoPath", "address"):
        m.pop(k, None)
    return m


# ---- 일반회원 승인 시스템 --------------------------------------------------
#  approvalStatus: 'pending'(미승인) | 'approved'(승인) | 'held'(보류)
#  · 기존 회원(필드 없음)은 approved 로 간주(하위 호환).
#  · 승인 여부와 무관하게 로그인/권한은 제약하지 않는다(요구). 단지 표시/알림용.
def _approval_of(m):
    s = str(m.get("approvalStatus") or "").strip()
    if s in ("pending", "approved", "held"):
        return s
    return "approved"


def _set_member_approval(ident, status):
    """회원 승인 상태 변경(단일). 반환: (ok, name)"""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d or status not in ("pending", "approved", "held"):
        return False, ""
    with _MEMBER_WRITE_LOCK:
        members = _ev_members()
        for i, m in enumerate(members):
            if (re.sub(r"[^0-9]", "", str(m.get("number", ""))) == d
                    or re.sub(r"[^0-9]", "", str(m.get("accessPhone")
                                                 or m.get("phone") or "")) == d
                    or str(m.get("id", "")) == str(ident)):
                m["approvalStatus"] = status
                members[i] = m
                _save_json(DB_FILE, members)
                _touch_meta({"count": len(members), "updatedBy": "approval"})
                return True, str(m.get("name", ""))
    return False, ""


def _pending_members():
    """미승인(pending) 일반회원 목록."""
    out = []
    for m in _ev_members():
        if m.get("isRegular") and _approval_of(m) == "pending":
            out.append({
                "id": str(m.get("id", "")),
                "number": str(m.get("number", "")),
                "name": str(m.get("name", "")),
                "phone": str(m.get("phone", "")),
                "loginId": str(m.get("loginId", "")),
                "unit": str(m.get("unit", "")),
                "league": str(m.get("league", "")),
                "created": str(m.get("created", "")),
                "approvalStatus": "pending",
            })
    return out



def _scope_finance(tier, who, fin):
    """재무는 관리자·마스터만 전체. 개인·비인가자에게는 빈 구조(F02)."""
    if tier in ("app", "master"):
        return fin
    return {"transactions": [], "restricted": True}


def _apply_scope_finance_full(tier, who, fin):
    """행사 참가비 등 부가 재무도 동일 스코프 적용."""
    return _scope_finance(tier, who, fin)


STATIC_DIR = "/home/user/flutter_app/build/web"
MIME = {
    ".html": "text/html; charset=utf-8", ".js": "application/javascript",
    ".css": "text/css", ".json": "application/json", ".png": "image/png",
    ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".ico": "image/x-icon",
    ".wasm": "application/wasm", ".ttf": "font/ttf", ".woff": "font/woff",
    ".woff2": "font/woff2", ".map": "application/json", ".txt": "text/plain",
    ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif",
    ".mp4": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm",
    ".m4v": "video/x-m4v", ".avi": "video/x-msvideo", ".mkv": "video/x-matroska",
    ".pdf": "application/pdf",
}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".heic"}
VIDEO_EXT = {".mp4", ".mov", ".webm", ".m4v", ".avi", ".mkv", ".3gp"}
# gzip 압축 대상(텍스트/JS/WASM/SVG/폰트) — 이미지·동영상은 제외
_COMPRESSIBLE_EXT = {".js", ".mjs", ".css", ".html", ".htm", ".json",
                     ".map", ".svg", ".wasm", ".txt", ".xml", ".manifest",
                     ".ttf", ".otf", ".woff", ".woff2"}

# ---- 정적파일 압축 결과 디스크 캐시 ----------------------------------------
# 매 요청마다 5MB JS 를 실시간 압축하면 CPU 를 잡아먹어 첫 로딩이 느려진다.
# 압축 결과를 (원본크기, mtime) 키로 디스크에 저장해 재사용한다.
_COMPRESS_CACHE_DIR = "/home/user/nas_proxy/.static_compress_cache"
_COMPRESS_CACHE_LOCK = threading.Lock()
_COMPRESS_MEM = {}          # key -> bytes (프로세스 메모리 캐시, 가장 빠름)


def _comp_cache_path(fp, enc, data):
    key = hashlib.md5(
        ("%s|%s|%d|%d" % (fp, enc, len(data),
                          int(os.path.getmtime(fp)))).encode()).hexdigest()
    return key


def _get_compressed(fp, data, ext, accept_enc):
    """압축 캐시 조회/생성. (bytes, encoding) 반환. 캐시 불가 시 (None, None)."""
    if ext not in _COMPRESSIBLE_EXT or len(data) < 1024:
        return None, None
    acc = accept_enc.lower()
    # 우선순위: brotli > gzip
    enc = None
    if "br" in acc and _brotli is not None:
        enc = "br"
    elif "gzip" in acc:
        enc = "gzip"
    if not enc:
        return None, None
    key = _comp_cache_path(fp, enc, data)
    mkey = "%s:%s" % (enc, key)
    # 1) 메모리 캐시
    hit = _COMPRESS_MEM.get(mkey)
    if hit is not None:
        return hit, enc
    # 2) 디스크 캐시
    cpath = os.path.join(_COMPRESS_CACHE_DIR, "%s.%s" % (key, enc))
    try:
        if os.path.isfile(cpath):
            with open(cpath, "rb") as f:
                blob = f.read()
            _COMPRESS_MEM[mkey] = blob
            return blob, enc
    except Exception:
        pass
    # 3) 생성 후 저장
    try:
        if enc == "br":
            blob = _brotli.compress(data, quality=6)
        else:
            blob = gzip.compress(data, 6)
    except Exception:
        return None, None
    try:
        with _COMPRESS_CACHE_LOCK:
            os.makedirs(_COMPRESS_CACHE_DIR, exist_ok=True)
            tmp = cpath + ".tmp%d" % os.getpid()
            with open(tmp, "wb") as f:
                f.write(blob)
            os.replace(tmp, cpath)
    except Exception:
        pass
    _COMPRESS_MEM[mkey] = blob
    return blob, enc


def _precompress_static():
    """부팅 시 정적 자산을 미리 압축해 캐시에 적재(첫 사용자 지연 제거)."""
    try:
        acc = "br" if _brotli is not None else "gzip"
        n = 0
        for root, _dirs, files in os.walk(STATIC_DIR):
            for fn in files:
                fp = os.path.join(root, fn)
                ext = os.path.splitext(fn)[1].lower()
                if ext not in _COMPRESSIBLE_EXT:
                    continue
                try:
                    sz = os.path.getsize(fp)
                    if sz < 1024 or sz > 30 * 1024 * 1024:
                        continue
                    with open(fp, "rb") as f:
                        data = f.read()
                    blob, enc = _get_compressed(fp, data, ext, acc)
                    if blob:
                        n += 1
                except Exception:
                    continue
        print("static pre-compressed:", n, "files (", acc, ")")
    except Exception as e:
        print("pre-compress skipped:", e)


def _ensure_structure():
    for sub in ["db", "backups", "photos", "exports", "data", "data/excel", "data/지출"]:
        if not NAS.exists(f"{BASE}/{sub}"):
            parent = "/".join((BASE + "/" + sub).split("/")[:-1])
            NAS.mkdir(parent, sub.split("/")[-1])
    # 기본자료 (원본 첨부 폴더)
    if not NAS.exists(DATA_DIR):
        NAS.mkdir(BASE, "기본자료")
    for sub in SUB_FOLDERS.values():
        if not NAS.exists(f"{DATA_DIR}/{sub}"):
            NAS.mkdir(DATA_DIR, sub)
    # 행사관리 (행사 사진·동영상 갤러리) — 무제한 업로드
    for sub in (BASE, EVENT_DIR):
        if not NAS.exists(sub):
            parent = "/".join(sub.split("/")[:-1]) or "/"
            NAS.mkdir(parent, sub.split("/")[-1])
    if not NAS.exists(EVENT_THUMB_DIR):
        NAS.mkdir(EVENT_DIR, ".thumbnails")
    # 연회비 연도 폴더 자동 생성 (현재 연도 + 다음 연도)
    now_year = datetime.datetime.now().year
    if not NAS.exists(f"{BASE}/연회비"):
        NAS.mkdir(BASE, "연회비")
    for y in (now_year, now_year + 1):
        if not NAS.exists(f"{BASE}/연회비/{y}"):
            NAS.mkdir(f"{BASE}/연회비", str(y))


def _load_json(path, default):
    try:
        if NAS.exists(path):
            return json.loads(NAS.read(path))
    except Exception as e:
        print("load fail", path, e)
    return default


def _save_json(path, obj):
    NAS.write(path, json.dumps(obj, ensure_ascii=False, indent=1).encode("utf-8"))


def _send_inquiry_mail(rec):
    """문의를 관리자 메일로 발송한다.

    config.json 에 smtp 설정이 있으면 실제 발송, 없으면 False 를 반환한다
    (이 경우에도 문의는 서버(inquiries.json)에 접수된다).
    """
    smtp = CONF.get("smtp") or {}
    host = smtp.get("host", "")
    if not host:
        return False
    try:
        import smtplib, email.message, email.mime.base, email.mime.multipart, email.mime.text
        from email import encoders
        port = int(smtp.get("port", 587))
        user = smtp.get("user", "")
        pw = smtp.get("pw", "")
        to = smtp.get("to", "") or "june7558@gmail.com"
        msg = email.mime.multipart.MIMEMultipart()
        msg["From"] = user or to
        msg["To"] = to
        msg["Subject"] = f"[TSAK 문의] {rec.get('subject') or '문의 접수'} — {rec.get('name')}"
        body = (
            f"이름(실명): {rec.get('name')}\n"
            f"인가번호: {rec.get('number') or '(미입력)'}\n"
            f"휴대폰: {rec.get('phone') or '(미입력)'}\n"
            f"보낸사람 메일: {rec.get('email')}\n"
            f"개인정보 동의: 동의함 (사진 활용 포함)\n"
            f"접수시각: {rec.get('at')}\n"
            f"첨부: {', '.join(rec.get('files') or []) or '없음'}\n"
            f"----------\n{rec.get('message')}\n"
        )
        msg.attach(email.mime.text.MIMEText(body, "plain", "utf-8"))
        se = smtplib.SMTP(host, port, timeout=15)
        try:
            se.starttls()
        except Exception:
            pass
        if user:
            se.login(user, pw)
        se.sendmail(msg["From"], [to], msg.as_string())
        se.quit()
        return True
    except Exception:
        return False


def _touch_meta(extra=None):
    m = _load_json(META_FILE, {"version": 0, "updated": None, "updatedBy": ""})
    m["version"] = int(m.get("version", 0)) + 1
    m["updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if extra:
        m.update(extra)
    _save_json(META_FILE, m)
    return m


def _default_config():
    return {
        "adminEmail": "june7558@gmail.com",
        "appName": "TSAK 인가자 관리",
        "developer": {"name": "이승준", "unit": "범스카우트415", "email": "june7558@gmail.com"},
        "donations": [
            {"label": "후원계좌", "bank": "기업은행", "account": "1005-202-281140"},
            {"label": "수품구매계좌", "bank": "기업은행", "account": "1005-102-281143"},
            {"label": "행사비계좌", "bank": "기업은행", "account": "1005-003-886274"},
        ],
        "donationHolder": "한국범스카우트중앙회",
        "appAccessUrl": "",
        # ---- 마스터 앱관리 ----
        "appPassword": APP_PW,          # 앱 접근 비번 (마스터 변경 가능)
        "personalPasswords": {},        # 인가번호 → 개인비번 (미설정 시 "{no}!@@")
        "serverPaused": False,          # 앱 서버 일시 정지
    }


# --- seed members into NAS on first boot ---
SEED = os.path.join(HERE, "members_seed.json")
if not SEED.endswith("json") or not os.path.exists(SEED):
    SEED = "/home/user/flutter_app/assets/data/members_seed.json"


def _boot():
    _ensure_structure()
    with LOCK:
        if not NAS.exists(DB_FILE):
            members = []
            try:
                members = json.load(open(SEED, encoding="utf-8"))
            except Exception as e:
                print("seed read fail", e)
            _save_json(DB_FILE, members)
            _touch_meta({"note": "초기 시딩 %d명" % len(members), "count": len(members)})
            print("seeded", len(members))
        if not NAS.exists(CFG_FILE):
            _save_json(CFG_FILE, _default_config())
        if not NAS.exists(FIN_FILE):
            _save_json(FIN_FILE, _default_finance())
        if not NAS.exists(IMP_FILE):
            _save_json(IMP_FILE, {"files": []})
        if not NAS.exists(MAT_FILE):
            _save_json(MAT_FILE, _default_mat())
    print("boot done")


def _touch_fin(extra=None):
    f = _load_json(FIN_FILE, _default_finance())
    f["version"] = int(f.get("version", 0)) + 1
    f["updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if extra:
        f.update(extra)
    _save_json(FIN_FILE, f)
    return f


def _default_finance():
    return {
        "transactions": [],
        "income_categories": ["후원", "수품구매", "참가비", "연회비", "평생회비", "기타"],
        "expense_categories": ["행사비", "운영비", "수품구매", "후원금집행", "기타"],
        "updated": None,
        "version": 0,
    }


def _log_import(folder, name, summary):
    log = _load_json(IMP_FILE, {"files": []})
    log["files"].insert(0, {
        "folder": folder, "name": name,
        "at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "summary": summary,
    })
    log["files"] = log["files"][:200]
    _save_json(IMP_FILE, log)


def _default_mat():
    """입금자 자동분류 규칙.
    aliases: 입금자 텍스트에 포함된 별칭 → 인가번호 매핑
    events : 행사명으로 인식할 키워드 → 분류 카테고리
    """
    return {"aliases": {}, "events": {}, "updated": None}


# 단일 거래 금액 상한(원). 이보다 크면 계좌번호/요약행 오인으로 간주한다.
_AMOUNT_MAX = 1_000_000_000  # 10억

# 은행 거래내역서의 머리말/꼬리말(거래가 아닌 메타) 감지 키워드
_META_ROW_KWS = (
    "조회기간", "조회일시", "조회일", "조회시간", "계좌번호", "예금주",
    "거래내역", "출력일시", "출력일", "페이지", "잔액", "합계", "총 ", "총건",
    "이체결과", "인쇄일시", "발급", "은행장", "점", "영업점", "지점",
)


def _sanitize_amount(v):
    """금액 정화: 음수·과대값(계좌번호 오인)·공백을 0으로."""
    amt = _parse_amount(v)
    if amt < 0 or amt > _AMOUNT_MAX:
        return 0
    return amt


def _looks_meta_row(cells):
    """거래 행이 아니라 명세서 머리말/꼬리말인지 판정."""
    joined = " ".join(str(c).strip() for c in cells if str(c).strip())
    if not joined:
        return True
    # '조회기간 : ...', '계좌번호 : ...' 처럼 콜론이 있으면 메타
    if ":" in joined or "：" in joined:
        # 실제 거래 적요에도 콜론이 드물게 있으나, 앞머리 메타 키워드가 함께 있으면 확정
        if any(k in joined for k in _META_ROW_KWS):
            return True
    # 메타 키워드 단독 포함
    if any(k in joined for k in ("조회기간", "조회일시", "출력일시", "출력일", "인쇄일시")):
        return True
    if "계좌번호" in joined and "예금주" in joined:
        return True
    # '총 14건' / '합계 N건' 같은 요약행
    if re.search(r"(총|합계)\s*[\d,]+\s*건", joined):
        return True
    return False


def _parse_amount(v):
    if v is None:
        return 0
    if isinstance(v, (int, float)):
        return int(round(v))
    s = re.sub(r"[^0-9\-]", "", str(v))
    try:
        return int(s) if s not in ("", "-") else 0
    except Exception:
        return 0


def _read_excel_sheets(b, filename=""):
    """xlsx/xls/csv 바이트 → [(시트명, 2차원 문자열 리스트)] 모든 시트 순회."""
    import io
    low = (filename or "").lower()

    # CSV/TXT는 단일 시트
    if low.endswith(".csv") or low.endswith(".txt") or low.endswith(".tsv"):
        text = b.decode("utf-8", errors="replace")
        delim = "," if (low.endswith(".csv") or low.endswith(".tsv")) else "\t"
        rows = []
        for ln in text.splitlines():
            if ln.strip() == "":
                continue
            rows.append([c.strip().strip('"') for c in ln.split(delim)])
        return [("CSV", rows)]

    # 구형 .xls
    if low.endswith(".xls"):
        import xlrd
        wb = xlrd.open_workbook(file_contents=b)
        sheets = []
        for sh in wb.sheets():
            rows = []
            for r in range(sh.nrows):
                rows.append([str(sh.cell_value(r, c)).strip() for c in range(sh.ncols)])
            sheets.append((sh.name, rows))
        return sheets

    # 기본: xlsx — 모든 시트 순회
    import openpyxl
    wb = openpyxl.load_workbook(io.BytesIO(b), data_only=True, read_only=True)
    sheets = []
    for ws in wb.worksheets:
        rows = []
        for row in ws.iter_rows(values_only=True):
            rows.append(["" if c is None else str(c).strip() for c in row])
        sheets.append((ws.title, rows))
    wb.close()
    return sheets


def _read_excel_bytes(b, filename=""):
    """xlsx/xls/csv 바이트 → 2차원 문자열 리스트(첫 시트). 하위 호환."""
    sheets = _read_excel_sheets(b, filename)
    return sheets[0][1] if sheets else []


def _rows_to_objects(rows):
    """헤더 감지 후 dict 리스트로 변환(헤더 없으면 자동 매핑).

    은행 거래내역서의 머리말/꼬리말(조회기간/계좌번호/합계 등)은 건너뛴다.
    """
    if not rows:
        return []
    known = {
        "이름": "name", "성명": "name", "입금자": "payer", "입금자명": "payer",
        "보낸분": "payer", "보낸사람": "payer", "거래처": "payer",
        "입금의뢰인": "payer", "의뢰인": "payer", "보낸이": "payer",
        "기재내용": "payer", "받는분": "payer", "받는사람": "payer",
        "내용": "memo", "적요": "jeyo", "메모": "memo", "비고": "memo",
        "거래내용": "memo", "거래적요": "memo",
        "번호": "number", "인가번호": "number",
        "금액": "amount", "입금액": "in_amount", "출금액": "out_amount",
        "거래금액": "amount", "출금": "out_amount", "입금": "in_amount",
        "지급": "out_amount", "지급액": "out_amount",
        "맡기신금액": "in_amount", "찾으신금액": "out_amount",
        "일자": "date", "날짜": "date", "거래일": "date", "거래일자": "date",
        "거래일시": "date", "거래시간": "date",
        "구분": "type", "유형": "type", "거래구분": "type",
        "행사": "event", "행사명": "event", "단위": "unit", "단위대": "unit",
        "연맹": "league", "소속": "league", "연도": "year",
    }

    def _norm(c):
        """헤더 셀 정규화: 공백·(원)·단위 표기 제거."""
        s = str(c).strip().replace(" ", "")
        s = re.sub(r"\((원|KRW|₩)\)", "", s)
        s = s.replace("수표·어음·증권금액", "무시_증권금액")
        return s

    def _is_header(cells):
        keys = [known.get(_norm(c)) for c in cells]
        return sum(1 for k in keys if k is not None) >= 2

    # 헤더 행 탐색(앞쪽 15행 이내) — 은행 명세서는 머리말 뒤에 헤더가 온다
    header_idx = -1
    mapped = []
    for i, r in enumerate(rows[:15]):
        if _is_header(r):
            header_idx = i
            mapped = [known.get(_norm(c)) for c in r]
            break

    out = []
    if header_idx >= 0:
        body = rows[header_idx + 1:]
        for r in body:
            if not any(str(c).strip() for c in r):
                continue
            if _looks_meta_row(r):
                continue
            o = {}
            for i, c in enumerate(r):
                key = mapped[i] if i < len(mapped) else None
                if key:
                    o[key] = str(c).strip()
            # 입금액/출금액 분리 열 → amount/type 정규화
            in_amt = _sanitize_amount(o.get("in_amount"))
            out_amt = _sanitize_amount(o.get("out_amount"))
            if in_amt or out_amt:
                if in_amt:
                    o["amount"] = str(in_amt)
                    o.setdefault("type", "income")
                else:
                    o["amount"] = str(out_amt)
                    o.setdefault("type", "expense")
            if not in_amt and not out_amt and "amount" in o:
                amt = _sanitize_amount(o.get("amount"))
                o["amount"] = str(amt)
                if amt == 0:
                    # 금액이 0이거나 부적합 → 메타성 행으로 보고 제외
                    continue
            # 적요(거래유형)를 memo 앞에 붙여 분류 신호로 활용
            jeyo = str(o.get("jeyo") or "").strip()
            if jeyo:
                o["memo"] = (jeyo + " " + str(o.get("memo", ""))).strip()
            out.append(o)
    else:
        # 헤더 없음: [일자, 입금자, 금액, 적요] 추정
        for r in rows:
            if not any(str(c).strip() for c in r):
                continue
            if _looks_meta_row(r):
                continue
            vals = [str(c).strip() for c in r]
            o = {
                "date": vals[0] if len(vals) > 0 else "",
                "payer": vals[1] if len(vals) > 1 else "",
                "amount": vals[2] if len(vals) > 2 else "",
                "memo": vals[3] if len(vals) > 3 else "",
                "name": vals[1] if len(vals) > 1 else "",
            }
            if _sanitize_amount(o["amount"]) == 0:
                continue
            out.append(o)
    return out


def _cfg_value(key, default=None):
    return _load_json(CFG_FILE, _default_config()).get(key, default)


def _personal_pw_of(no):
    """설정된 개인비번 또는 기본 '{no}!@@'."""
    no = re.sub(r"[^0-9]", "", str(no))
    pws = _cfg_value("personalPasswords", {}) or {}
    return str(pws.get(no) or f"{no}!@@")


def _verify(tier, value):
    if tier == "master":
        return value == MASTER_PW, "master"
    app_pw = _cfg_value("appPassword", APP_PW) or APP_PW
    if tier == "app":
        return value == app_pw or value == MASTER_PW, "app"
    if tier == "personal":
        # 입력값에서 인가번호 추출 후, 설정된 개인비번과 비교
        no = re.sub(r"[^0-9]", "", value or "")
        if not no:
            return False, ""
        members = _load_json(DB_FILE, [])
        exists = any(
            re.sub(r"[^0-9]", "", str(m.get("number", ""))) == no for m in members
        )
        if not exists:
            return False, ""
        return (value == _personal_pw_of(no) or value == MASTER_PW), "personal"
    if tier == "guest":
        # 비인가자(일반회원): ID=전화번호(숫자), PW=뒤 4자리(또는 설정값)
        return _guest_verify("", value)
    return False, ""


def _guest_verify(ident, value):
    """일반회원(비인가자) 검증. ident(전화/번호)가 있으면 지정회원만, 없으면 전체 탐색."""
    d_ident = re.sub(r"[^0-9]", "", str(ident or ""))
    pws = _ev_load_regular_pw()
    for m in _ev_members():
        if not m.get("isRegular"):
            continue
        mid = re.sub(r"[^0-9]", "", str(m.get("accessPhone") or m.get("phone") or ""))
        no = re.sub(r"[^0-9]", "", str(m.get("number", "")))
        if d_ident and d_ident not in (mid, no):
            continue
        stored = pws.get(mid) or m.get("personalPassword") or _ev_phone_last4(
            m.get("phone") or mid)
        if value == str(stored) or value == _ev_phone_last4(m.get("phone") or mid):
            return True, "guest"
    return False, ""


def _set_password(tier, ident, value, reset):
    """마스터/관리자 전용 — 회원 비번 강제 변경/초기화.
    반환: (ok, error, newPw)"""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d:
        return False, "id", ""
    m = _ev_member_by_ident(d)
    if not m:
        return False, "not found", ""
    is_regular = bool(m.get("isRegular"))
    # 관리자(비마스터)는 일반회원만 변경 가능
    if tier == "app" and not is_regular:
        return False, "권한 없음: 일반회원만 변경 가능", ""
    if reset:
        if is_regular:
            new_pw = _ev_phone_last4(m.get("phone") or d)
        else:
            # 인가자 기본비번은 "{인가번호}!@@" — number 필드가 비어 있어도
            # 식별자(로그인 ID) 기준으로 일관되게 생성한다.
            base = re.sub(r"[^0-9]", "", str(m.get("number") or d))
            new_pw = f"{base}!@@" if base else ""
        if not new_pw:
            return False, "reset", ""
    else:
        new_pw = str(value or "").strip()
        if not new_pw:
            return False, "value", ""
    # 회원 DB 갱신
    members = _load_json(DB_FILE, [])
    for i, mm in enumerate(members):
        if str(mm.get("id", "")) == str(m.get("id", "")):
            mm["personalPassword"] = new_pw
            members[i] = mm
            break
    _save_json(DB_FILE, members)
    # 일반회원은 별도 파일에도 저장(게스트 검증용)
    if is_regular:
        pws = _ev_load_regular_pw()
        key = re.sub(r"[^0-9]", "", str(m.get("accessPhone") or m.get("phone") or d))
        pws[key] = new_pw
        _ev_save_regular_pw(pws)
    _touch_meta({"updatedBy": "admin-set-pw"})
    return True, "", new_pw


def _server_paused():
    return bool(_cfg_value("serverPaused", False))


# ============ 행사관리 — 미디어(사진/동영상) 유틸 ============
def _safe_name(name):
    """NAS 경로 안전 파일명 (경로 분리자/제어문자 제거)."""
    name = str(name or "").replace("\\", "/").split("/")[-1].strip()
    name = re.sub(r"[\x00-\x1f]", "", name)
    return name or "file"


def _ext_of(name):
    return os.path.splitext(str(name))[1].lower()


def _kind_of(name):
    ext = _ext_of(name)
    if ext in IMAGE_EXT:
        return "image"
    if ext in VIDEO_EXT:
        return "video"
    return "other"


def _looks_like_image(b):
    """확장자가 이미지라도 실제 바이트가 이미지 시그니처인지 검사.

    (과거 write_stream 버그로 multipart 경계 문자열이 파일로 저장된 경우를 걸러낸다.)
    """
    if not b or len(b) < 12:
        return False
    if b[:2] == b"\xff\xd8":            # JPEG
        return True
    if b[:8] == b"\x89PNG\r\n\x1a\n":   # PNG
        return True
    if b[:6] in (b"GIF87a", b"GIF89a"):
        return True
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        return True
    if b[:2] == b"BM":                  # BMP
        return True
    return False


def _broken_image_placeholder():
    """손상된 이미지 대신 내보낼 회색 '이미지 없음' JPEG (1회 생성 후 캐시)."""
    global _BROKEN_JPEG
    try:
        if _BROKEN_JPEG is not None:
            return _BROKEN_JPEG
    except NameError:
        pass
    try:
        import io
        from PIL import Image, ImageDraw
        im = Image.new("RGB", (480, 360), (225, 225, 228))
        d = ImageDraw.Draw(im)
        d.line((40, 40, 440, 320), fill=(180, 180, 185), width=6)
        d.line((440, 40, 40, 320), fill=(180, 180, 185), width=6)
        d.rectangle((0, 200, 480, 360), fill=(205, 205, 210))
        try:
            d.text((150, 260), "IMAGE", fill=(120, 120, 125))
        except Exception:
            pass
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=80)
        _BROKEN_JPEG = buf.getvalue()
    except Exception:
        _BROKEN_JPEG = b""
    return _BROKEN_JPEG


def _serve_served_image(self, data, fallback_name, ctype):
    """이미지 응답 직전 검증: 손상 파일이면 플레이스홀더로 대체한다."""
    if ctype.startswith("image/") and not _looks_like_image(data):
        ph = _broken_image_placeholder()
        if ph:
            return self._bytes_cache(ph, "image/jpeg", max_age=86400)
    return self._bytes_cache(data, ctype)


def _event_media_meta():
    return _load_json(EVENT_MEDIA_FILE, {"files": {}})


def _save_event_media_meta(meta):
    _save_json(EVENT_MEDIA_FILE, meta)


def _thumb_path(name):
    return f"{EVENT_THUMB_DIR}/{name}.jpg"


def _make_image_thumb(src_bytes, dest_name, max_side=480):
    """이미지 → JPEG 썸네일 생성 (PIL). 실패 시 None."""
    try:
        import io
        from PIL import Image, ImageOps
        im = Image.open(io.BytesIO(src_bytes))
        im = ImageOps.exif_transpose(im)
        im = im.convert("RGB")
        im.thumbnail((max_side, max_side))
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=78, optimize=True)
        NAS.write(_thumb_path(dest_name), buf.getvalue())
        return True
    except Exception as e:
        print("thumb fail", dest_name, e)
        return None


def _make_video_thumb(local_tmp_path, dest_name, max_side=480):
    """동영상 → 첫 프레임 JPEG 썸네일 (ffmpeg). 실패 시 None."""
    try:
        import subprocess, tempfile, io
        from PIL import Image
        out = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False).name
        cmd = [
            "ffmpeg", "-y", "-ss", "0.5", "-i", local_tmp_path,
            "-frames:v", "1", "-vf", f"scale='min({max_side},iw)':-2",
            "-q:v", "4", out,
        ]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        if not os.path.exists(out) or os.path.getsize(out) == 0:
            return None
        with open(out, "rb") as f:
            data = f.read()
        try:
            os.unlink(out)
        except Exception:
            pass
        NAS.write(_thumb_path(dest_name), data)
        return True
    except Exception as e:
        print("vthumb fail", dest_name, e)
        return None


def _probe_video(local_tmp_path):
    """ffprobe로 동영상 길이/해상도 추출."""
    try:
        import subprocess
        r = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json",
             "-show_format", "-show_streams", local_tmp_path],
            capture_output=True, text=True, timeout=40)
        j = json.loads(r.stdout or "{}")
        dur = float(j.get("format", {}).get("duration", 0) or 0)
        w = h = 0
        for s in j.get("streams", []):
            if s.get("codec_type") == "video":
                w, h = int(s.get("width", 0) or 0), int(s.get("height", 0) or 0)
                break
        return {"duration": round(dur, 1), "width": w, "height": h}
    except Exception:
        return {"duration": 0, "width": 0, "height": 0}


def _event_list():
    """행사관리 폴더의 미디어 목록 (메타와 병합, 최신순)."""
    if not NAS.exists(EVENT_DIR):
        return []
    r = NAS.list(EVENT_DIR)
    if not r.get("ok"):
        return []
    meta = _event_media_meta().get("files", {})
    out = []
    for f in r["files"]:
        nm = f["name"]
        if f.get("isdir") or nm.startswith("."):
            continue
        kind = _kind_of(nm)
        if kind == "other":
            continue
        m = meta.get(nm, {})
        out.append({
            "name": nm,
            "size": int(f.get("size", 0) or 0),
            "kind": kind,
            "ext": _ext_of(nm),
            "thumb": _thumb_path(nm) if (m.get("thumb") or m.get("vthumb")) else None,
            "thumbName": f"{nm}.jpg",
            "duration": m.get("duration", 0),
            "width": m.get("width", 0),
            "height": m.get("height", 0),
            "uploaded": m.get("uploaded", ""),
        })
    out.sort(key=lambda x: x["name"], reverse=True)
    return out


def _veto_static():
    """서버 일시정지 시 정적 웹앱 요청을 차단할지 여부(API/정지안내는 허용)."""
    return _server_paused()


# ============ 행사관리 — 폴더/데이터/샘플/미디어 유틸 ============
def _ev_safe(name):
    """행사명/파일명을 NAS 경로에 안전한 단일 세그먼트로 정규화."""
    s = str(name or "").strip().replace("\\", "/").split("/")[-1]
    s = re.sub(r"[\x00-\x1f]", "", s)
    s = s.replace("/", "／").strip()
    return s or "무제"


def _ev_doc():
    return _load_json(EVENTS_FILE, {"events": {}})


def _ev_save(doc):
    _save_json(EVENTS_FILE, doc)


def _ev_id(year, title):
    return f"{year}::{title}"


def _ev_dir(year, title):
    return f"{EVENT_DIR}/{_ev_safe(year)}/{_ev_safe(title)}"


def _ev_thumb_dir(year, title):
    return f"{EVENT_DIR}/.thumbnails/{_ev_safe(year)}/{_ev_safe(title)}"


def _ev_media_meta(year, title):
    return _load_json(EVENT_MEDIA_FILE, {"events": {}})


def _ev_sub_safe(sub):
    """media 폴더 기준 상대 하위경로 정규화 ('a/b' → 각 세그먼트 안전화)."""
    if not sub:
        return ""
    parts = [p for p in str(sub).replace("\\", "/").split("/")
             if p and p not in (".", "..")]
    return "/".join(_ev_safe(p) for p in parts)


def _ev_sub_dir(year, title, key, sub=""):
    """행사 항목 폴더(+하위경로)의 NAS 경로."""
    fn = EVENT_SUB_BY_KEY.get(key)
    if not fn:
        return None
    base = f"{_ev_dir(year, title)}/{fn}"
    sub = _ev_sub_safe(sub)
    return f"{base}/{sub}" if sub else base


def _ev_mkdir_deep(path):
    """EVENT_DIR 기준으로 경로의 각 세그먼트 폴더를 순차 생성."""
    if not path:
        return False
    parts = path.split("/")
    cur = ""
    for i, seg in enumerate(parts):
        cur = seg if not cur else f"{cur}/{seg}"
        if not cur.startswith(EVENT_DIR):
            continue
        if not NAS.exists(cur):
            parent, name = cur.rsplit("/", 1)
            if not NAS.exists(parent):
                _ev_mkdir_deep(parent)
            try:
                NAS.mkdir(parent, name)
            except Exception as e:
                print("mkdir fail", cur, e)
                return False
    return True


def _ev_thumb_key(name, sub=""):
    sub = _ev_sub_safe(sub)
    return (sub + "/" + str(name)) if sub else str(name)


def _ev_thumb_path(year, title, name, sub=""):
    key = _ev_thumb_key(name, sub).replace("/", "__")
    return f"{_ev_thumb_dir(year, title)}/{key}.jpg"


def _ev_view_dir(year, title):
    return f"{EVENT_DIR}/.views/{_ev_safe(year)}/{_ev_safe(title)}"


def _ev_view_path(year, title, name, sub=""):
    key = _ev_thumb_key(name, sub).replace("/", "__")
    return f"{_ev_view_dir(year, title)}/{key}.jpg"


def _ensure_event_dirs(year, title):
    """행사 폴더 + 항목 하위폴더 + 업로드 폴더 샘플 파일 생성."""
    base = _ev_dir(year, title)
    for parent in (EVENT_DIR, f"{EVENT_DIR}/{_ev_safe(year)}", base):
        if not NAS.exists(parent):
            p, n = parent.rsplit("/", 1)
            NAS.mkdir(p, n)
    for fname, key, upload in EVENT_SUBFOLDERS:
        fp = f"{base}/{fname}"
        if not NAS.exists(fp):
            NAS.mkdir(base, fname)
        if upload:
            _ev_ensure_sample(fname, key, fp)
    tdir = _ev_thumb_dir(year, title)
    if not NAS.exists(tdir):
        p, n = tdir.rsplit("/", 1)
        if not NAS.exists(p):
            p2, n2 = p.rsplit("/", 1)
            if not NAS.exists(p2):
                NAS.mkdir(p2, n2)
            NAS.mkdir(p, n)
        NAS.mkdir(p, n)


def _ev_sample_names(key):
    if key == "plan":
        return "샘플_행사계획서.docx", "샘플_행사계획서.xlsx"
    if key == "attendees":
        return "샘플_참석자명단.xlsx", None
    if key == "media":
        return "샘플_사진설명.txt", None
    return None, None


def _ev_ensure_sample(folder_name, key, folder_path):
    """업로드 가능 폴더에 샘플 파일이 없으면 생성 (테스트 후 교체 가능)."""
    try:
        n1, n2 = _ev_sample_names(key)
        if n1 and not NAS.exists(f"{folder_path}/{n1}"):
            data = _ev_sample_bytes(key)
            if data:
                NAS.write(f"{folder_path}/{n1}", data)
        if n2 and not NAS.exists(f"{folder_path}/{n2}"):
            data = _ev_sample_bytes(key, alt=True)
            if data:
                NAS.write(f"{folder_path}/{n2}", data)
    except Exception as e:
        print("sample fail", folder_name, e)


def _ev_sample_bytes(key, alt=False):
    """샘플 파일 바이트 (xlsx=openpyxl, docx=python-docx, txt=텍스트)."""
    import io
    title = "행사 계획서" if key == "plan" else "참석자 명단"
    header = {
        "plan": ["항목", "내용"],
        "attendees": ["순번", "이름", "소속", "성별", "연락처", "메일주소", "주소", "항목"],
        "media": [],
    }.get(key, [])
    rows = {
        "plan": [["행사명", ""], ["기간", ""], ["장소", ""], ["주요내용", ""], ["예산", ""]],
        "attendees": [
            ["1", "", "", "", "", "", "", ""],
            ["2", "", "", "", "", "", "", ""],
        ],
        "media": [],
    }.get(key, [])
    if key == "media":
        txt = (
            "샘플 파일입니다. 이 파일은 형식 확인용으로, 자유롭게 삭제하고 실제 파일로 교체하세요.\n"
            "사진과 동영상을 이 폴더에 업로드하면 앱에서도 보이고 다운로드할 수 있습니다.\n"
        )
        return txt.encode("utf-8")
    if alt:  # docx
        try:
            from docx import Document
            doc = Document()
            doc.add_heading(title, level=1)
            nd = doc.add_table(rows=1, cols=len(header))
            for i, h in enumerate(header):
                nd.rows[0].cells[i].text = h
            for r in rows:
                cells = nd.add_row().cells
                for i, v in enumerate(r):
                    if i < len(cells):
                        cells[i].text = str(v)
            buf = io.BytesIO()
            doc.save(buf)
            return buf.getvalue()
        except Exception as e:
            print("docx sample fail", e)
            return None
    # xlsx
    try:
        import openpyxl
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = title
        ws.append(header)
        for r in rows:
            ws.append(r)
        for col in ws.columns:
            width = max((len(str(c.value)) if c.value else 0) for c in col) + 4
            ws.column_dimensions[col[0].column_letter].width = min(width, 40)
        buf = io.BytesIO()
        wb.save(buf)
        return buf.getvalue()
    except Exception as e:
        print("xlsx sample fail", e)
        return None


def _ev_load_stats():
    """행사별 참석자 수 등 요약(목록 표시용)."""
    doc = _ev_doc()
    return {
        eid: {"attendeeCount": len(e.get("attendees", []))}
        for eid, e in doc.get("events", {}).items()
    }


def _ev_media_counts(year, title):
    """행사 '사진+동영상' 폴더의 이미지/동영상 개수(재귀)."""
    d = _ev_sub_dir(year, title, "media")
    if not d or not NAS.exists(d):
        return {"photo": 0, "video": 0}
    photo = video = 0
    for it in _ev_collect_under(d):
        k = _kind_of(str(it["rel"]).rsplit("/", 1)[-1])
        if k == "image":
            photo += 1
        elif k == "video":
            video += 1
    return {"photo": photo, "video": video}


def _ev_known_names():
    """행사관리(events.json)에 정의된 행사명 집합."""
    doc = _ev_doc()
    return {str(e.get("title", "")) for e in doc.get("events", {}).values()}


def _ev_all_member_event_names():
    """모든 회원 프로필(eventAttend)에 등록된 행사명 집합."""
    names = set()
    for m in _ev_members():
        ev = m.get("eventAttend")
        if isinstance(ev, dict):
            for k in ev.keys():
                if str(k).strip():
                    names.add(str(k))
    return names


def _ev_member_event_counts():
    """행사명별 (참가=true) 인원 수."""
    counts = {}
    for m in _ev_members():
        ev = m.get("eventAttend")
        if isinstance(ev, dict):
            for k, v in ev.items():
                if v:
                    counts[str(k)] = counts.get(str(k), 0) + 1
    return counts


def _ev_union_events():
    """행사관리 목록 + 개인 프로필(eventAttend) 행사명의 합집합.

    - events.json 에 정의된 행사: defined=True
    - 프로필에만 있는 행사(관리목록누락): defined=False (id=null, year='')
    각 항목에 참가인원/장소/사진·동영상 개수/생성자 포함.
    """
    doc = _ev_doc()
    defined = doc.get("events", {})
    mot = _ev_member_event_counts()
    by_title = {str(e.get("title", "")): eid for eid, e in defined.items()}
    out = []
    for eid, e in defined.items():
        info = dict(e)
        info["id"] = eid
        info.setdefault("attendees", [])
        info["createdBy"] = str(e.get("createdBy", "") or "")
        info["defined"] = True
        info["media"] = _ev_media_counts(e.get("year", ""), e.get("title", ""))
        info["memberCount"] = mot.get(str(e.get("title", "")), 0)
        out.append(info)
    for name in sorted(_ev_all_member_event_names()):
        if name in by_title:
            continue
        out.append({
            "id": None, "year": "", "title": name, "period": "", "place": "",
            "desc": "", "created": "", "createdBy": "", "attendees": [],
            "defined": False, "media": {"photo": 0, "video": 0},
            "memberCount": mot.get(name, 0),
        })
    out.sort(
        key=lambda x: (str(x.get("year", "") or "0000"), str(x.get("title", ""))),
        reverse=True,
    )
    return out


def _ev_remove_member_events(names):
    """여러 행사명을 모든 회원의 eventAttend 에서 제거 → 개인 프로필 반영."""
    names = {str(n) for n in names if str(n).strip()}
    if not names:
        return 0
    members = _ev_members()
    changed = 0
    for i, m in enumerate(members):
        ev = m.get("eventAttend")
        if not isinstance(ev, dict):
            continue
        hit = [k for k in list(ev.keys()) if k in names]
        if hit:
            for k in hit:
                ev.pop(k, None)
            m["eventAttend"] = ev
            members[i] = m
            changed += 1
    if changed:
        if NAS.exists(DB_FILE):
            stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            try:
                NAS.write(f"{BASE}/backups/members_{stamp}.json",
                          NAS.read(DB_FILE).encode("utf-8"))
            except Exception:
                pass
        _save_json(DB_FILE, members)
        _touch_meta({"count": len(members), "updatedBy": "event-delete"})
    return changed


def _ev_list(tree=False):
    """행사 목록. tree=True면 참석자/폴더 정보 요약 포함."""
    doc = _ev_doc()
    out = []
    for eid, e in doc.get("events", {}).items():
        info = dict(e)
        info["id"] = eid
        info.setdefault("attendees", [])
        if tree:
            try:
                r = NAS.list(_ev_dir(e.get("year", ""), e.get("title", "")))
                info["folders"] = [
                    {"name": f["name"], "isdir": f.get("isdir", False)}
                    for f in (r.get("files") or [])
                    if not f["name"].startswith(".")
                ] if r.get("ok") else []
            except Exception:
                info["folders"] = []
        out.append(info)
    out.sort(key=lambda x: (str(x.get("year", "0")), x.get("title", "")), reverse=True)
    return out


def _ev_files(year, title, key, sub=""):
    """행사 하위 항목 폴더의 파일+하위폴더 목록(+확장자/용량/업로더).

    sub: 항목 폴더 기준 상대 하위경로(예: '봄행사/1팀'). '' 이면 항목 폴더 루트.
    """
    fp = _ev_sub_dir(year, title, key, sub)
    if not fp or not NAS.exists(fp):
        return []
    r = NAS.list(fp)
    if not r.get("ok"):
        return []
    doc = _ev_doc()
    ev = doc.get("events", {}).get(_ev_id(year, title), {})
    upl = ev.get("uploaders", {}).get(key, {})
    sub_clean = _ev_sub_safe(sub)
    out = []
    for f in r["files"]:
        nm = f["name"]
        if nm.startswith("."):
            continue
        # 업로더/시각 키는 'sub/name' 형태(하위폴더 파일 구분)
        ukey = f"{sub_clean}/{nm}" if sub_clean else nm
        if f.get("isdir"):
            # 하위폴더 항목
            try:
                cnt = len([x for x in (NAS.list(f"{fp}/{nm}").get("files") or [])
                           if not x["name"].startswith(".")])
            except Exception:
                cnt = 0
            out.append({
                "name": nm,
                "isdir": True,
                "size": 0,
                "ext": "",
                "kind": "folder",
                "count": cnt,
                "uploader": upl.get(ukey, ""),
                "uploaded": ev.get("fileTimes", {}).get(key, {}).get(ukey, ""),
            })
        else:
            out.append({
                "name": nm,
                "isdir": False,
                "size": int(f.get("size", 0) or 0),
                "ext": _ext_of(nm),
                "kind": _kind_of(nm),
                "uploader": upl.get(ukey, ""),
                "uploaded": ev.get("fileTimes", {}).get(key, {}).get(ukey, ""),
            })
    # 폴더 먼저, 그 다음 파일 (그룹 내 이름 역순)
    out.sort(key=lambda x: x.get("name", ""), reverse=True)
    out.sort(key=lambda x: 0 if x.get("isdir") else 1)
    return out


def _make_image_thumb2(src_bytes, year, title, name, sub="", max_side=480):
    """행사 항목 이미지 → JPEG 썸네일."""
    try:
        import io
        from PIL import Image, ImageOps
        im = Image.open(io.BytesIO(src_bytes))
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((max_side, max_side))
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=78, optimize=True)
        NAS.write(_ev_thumb_path(year, title, name, sub), buf.getvalue())
        return True
    except Exception as e:
        print("ev thumb fail", name, e)
        return None


def _make_video_thumb2(local_tmp_path, year, title, name, sub="", max_side=480):
    """행사 항목 동영상 → 첫 프레임 썸네일."""
    try:
        import subprocess, tempfile
        out = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False).name
        subprocess.run(
            ["ffmpeg", "-y", "-ss", "0.5", "-i", local_tmp_path, "-frames:v", "1",
             "-vf", f"scale='min({max_side},iw)':-2", "-q:v", "4", out],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        if not os.path.exists(out) or os.path.getsize(out) == 0:
            return None
        with open(out, "rb") as f:
            data = f.read()
        try:
            os.unlink(out)
        except Exception:
            pass
        NAS.write(_ev_thumb_path(year, title, name, sub), data)
        return True
    except Exception as e:
        print("ev vthumb fail", name, e)
        return None


def _make_image_view2(src_bytes, year, title, name, sub="", max_side=1600):
    """사진 '최적 크기' 보기용 지연 생성본(1600px, 품질 85)."""
    try:
        import io
        from PIL import Image, ImageOps
        im = Image.open(io.BytesIO(src_bytes))
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((max_side, max_side))
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=85, optimize=True)
        vp = _ev_view_path(year, title, name, sub)
        d = vp.rsplit("/", 1)[0]
        _ev_mkdir_deep(d)
        NAS.write(vp, buf.getvalue())
        return True
    except Exception as e:
        print("view fail", name, e)
        return None


# ============ 행사 썸네일 일괄 백필(backfill) ============
# 기존 업로드분은 썸네일이 없어 첫 조회 시 서빙 경로에서 "지연 생성"된다.
# 그 비용(원격 NAS 원본 다운로드+PIL 리사이즈)이 목록 로딩을 매우 느리게
# 만들므로, 백그라운드 작업으로 미리 모든 썸네일을 만들어 둔다.
#  - 스레드 1개로 순차 처리(NAS 호출은 Lock 직렬화되므로 과도한 병렬은 무의미)
#  - 진행상황을 메모리에 기록하여 관리자가 진행률을 확인할 수 있다.
_THUMB_JOB = {
    "running": False,
    "total": 0,
    "done": 0,
    "images": 0,
    "videos": 0,
    "skipped": 0,
    "failed": 0,
    "started": "",
    "finished": "",
    "last": "",
}
_THUMB_JOB_LOCK = threading.Lock()
_THUMB_INDEX_FILE = BASE + "/db/thumb_index.json"


def _ev_thumb_job_reset(total):
    with _THUMB_JOB_LOCK:
        _THUMB_JOB.update({
            "running": True, "total": total, "done": 0,
            "images": 0, "videos": 0, "skipped": 0, "failed": 0,
            "started": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "finished": "", "last": "",
        })


def _ev_thumb_job_inc(field, last=None):
    with _THUMB_JOB_LOCK:
        _THUMB_JOB["done"] = int(_THUMB_JOB.get("done", 0)) + 1
        _THUMB_JOB[field] = int(_THUMB_JOB.get(field, 0)) + 1
        if last:
            _THUMB_JOB["last"] = last


def _ev_thumb_job_finish():
    with _THUMB_JOB_LOCK:
        _THUMB_JOB["running"] = False
        _THUMB_JOB["finished"] = datetime.datetime.now().strftime(
            "%Y-%m-%d %H:%M:%S")


def _ev_thumb_job_state():
    with _THUMB_JOB_LOCK:
        return dict(_THUMB_JOB)


def _ev_media_files_with_meta(year, title, key, sub=""):
    """(파일명, sub경로) 목록 — 하위폴더까지 재귀 수집."""
    out = []
    fp = _ev_sub_dir(year, title, key, sub)
    if not fp or not NAS.exists(fp):
        return out
    try:
        r = NAS.list(fp)
    except Exception:
        return out
    for f in (r.get("files") or []):
        nm = f.get("name", "")
        if nm.startswith("."):
            continue
        if f.get("isdir"):
            child = f"{sub}/{nm}" if sub else nm
            out.extend(_ev_media_files_with_meta(year, title, key, child))
        else:
            out.append((nm, sub))
    return out


def _ev_spot_thumb(year, title, name, sub, kind, k):
    """단일 파일 썸네일 생성. 반환: 'image' | 'video' | 'skip' | 'fail'."""
    try:
        if NAS.exists(_ev_thumb_path(year, title, name, sub)):
            # 이미 있음 → 로컬 디스크 캐시만 보강(예열)하고 skip.
            try:
                if _thumb_disk_get(year, title, name, sub) is None:
                    data = NAS.read_bytes(_ev_thumb_path(year, title, name, sub))
                    _thumb_disk_put(year, title, name, sub, data)
            except Exception:
                pass
            return "skip"
        orig = _ev_find_file(year, title, "media", name, sub)
        if not orig:
            return "skip"
        if kind == "image":
            ok = _make_image_thumb2(
                NAS.read_bytes(orig), year, title, name, sub, max_side=k)
            return "image" if ok else "fail"
        if kind == "video":
            # 동영상은 NAS 원본을 임시로 받아 첫 프레임 추출
            import tempfile
            tmp = tempfile.NamedTemporaryFile(
                suffix=_ext_of(name), delete=False).name
            try:
                with open(tmp, "wb") as w:
                    w.write(NAS.read_bytes(orig))
                ok = _make_video_thumb2(tmp, year, title, name, sub, max_side=k)
                del ok
                return "video"
            finally:
                try:
                    os.unlink(tmp)
                except Exception:
                    pass
        return "skip"
    except Exception as e:
        print("spot thumb fail", name, e)
        return "fail"


def _ev_ensure_thumb_dir(year, title):
    """썸네일 저장 폴더 보장(누락 시 생성)."""
    tdir = _ev_thumb_dir(year, title)
    if NAS.exists(tdir):
        return True
    try:
        _ev_mkdir_deep(tdir)
    except Exception as e:
        print("thumb dir fail", tdir, e)
    return NAS.exists(tdir)


def _ev_backfill_thumbs_worker(max_side=480, force=False):
    """전체 행사 사진/동영상 썸네일 백필(백그라운드)."""
    try:
        doc = _ev_doc()
        jobs = []          # (year, title, name, sub, kind)
        for eid, e in doc.get("events", {}).items():
            year = e.get("year", "")
            title = e.get("title", "")
            if not year or not title:
                continue
            files = _ev_media_files_with_meta(year, title, "media")
            if not files:
                continue
            _ev_ensure_thumb_dir(year, title)
            for nm, sub in files:
                kind = _kind_of(nm)
                if kind in ("image", "video"):
                    jobs.append((year, title, nm, sub, kind))
        _ev_thumb_job_reset(len(jobs))
        for (year, title, nm, sub, kind) in jobs:
            try:
                if force:
                    try:
                        NAS.delete(_ev_thumb_path(year, title, nm, sub))
                    except Exception:
                        pass
                res = _ev_spot_thumb(year, title, nm, sub, kind, max_side)
                if res == "image":
                    _ev_thumb_job_inc("images", f"{title}/{nm}")
                elif res == "video":
                    _ev_thumb_job_inc("videos", f"{title}/{nm}")
                elif res == "skip":
                    _ev_thumb_job_inc("skipped")
                else:
                    _ev_thumb_job_inc("failed", f"{title}/{nm}")
            except Exception as e:
                print("backfill item fail", nm, e)
                _ev_thumb_job_inc("failed")
        print("thumb backfill done", _ev_thumb_job_state())
    except Exception as e:
        print("thumb backfill worker fail", e)
    finally:
        _ev_thumb_job_finish()


def _ev_start_thumb_backfill(max_side=480, force=False):
    """이미 진행 중이면 시작하지 않는다."""
    with _THUMB_JOB_LOCK:
        if _THUMB_JOB.get("running"):
            return False
    t = threading.Thread(
        target=_ev_backfill_thumbs_worker,
        args=(max_side, force),
        daemon=True,
    )
    t.start()
    return True


def _ev_find_file(year, title, key, name, sub=""):
    fp_dir = _ev_sub_dir(year, title, key, sub)
    if not fp_dir:
        return None
    safe = _safe_name(name)
    fp = f"{fp_dir}/{safe}"
    return fp if NAS.exists(fp) else None


# ---- 썸네일 로컬 디스크 캐시 -----------------------------------------------
# NAS 는 원격(HTTPS)이라 썸네일을 매 요청마다 NAS 에서 읽으면 왕복 ~0.9s 가
# 걸린다. 백필 후 로컬 디스크에 캐시해 두면 브라우저가 이미 가진 캐시까지
# 고려해 첫 로딩이 ~0.02s 로 단축된다.
_THUMB_DISK_DIR = "/home/user/nas_proxy/.thumb_cache"
_THUMB_DISK_LOCK = threading.Lock()


def _thumb_disk_path(year, title, name, sub=""):
    key = _ev_thumb_key(name, sub)
    safe = re.sub(r"[^0-9A-Za-z_.\-가-힣]", "_", f"{_ev_safe(year)}__{_ev_safe(title)}__{key}")
    return f"{_THUMB_DISK_DIR}/{safe}.jpg"


def _thumb_disk_get(year, title, name, sub=""):
    """로컬 캐시에서 썸네일 바이트 반환. 없으면 None."""
    p = _thumb_disk_path(year, title, name, sub)
    try:
        if os.path.exists(p):
            with open(p, "rb") as f:
                return f.read()
    except Exception:
        pass
    return None


def _thumb_disk_put(year, title, name, sub, data):
    try:
        os.makedirs(_THUMB_DISK_DIR, exist_ok=True)
        p = _thumb_disk_path(year, title, name, sub)
        tmp = p + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, p)
    except Exception:
        pass


def _thumb_get(year, title, name, sub="", build_missing=True):
    """썸네일 바이트 반환 (로컬캐시 → NAS → 즉석생성 순). 없으면 None."""
    data = _thumb_disk_get(year, title, name, sub)
    if data is not None:
        return data
    if not NAS.exists(_ev_thumb_path(year, title, name, sub)):
        if build_missing:
            try:
                orig = _ev_find_file(year, title, "media", name, sub)
                if orig:
                    kind = _kind_of(name)
                    if kind == "image":
                        _ev_ensure_thumb_dir(year, title)
                        _make_image_thumb2(NAS.read_bytes(orig), year, title, name, sub)
                    elif kind == "video":
                        import tempfile
                        tmp = tempfile.NamedTemporaryFile(
                            suffix=_ext_of(name), delete=False).name
                        try:
                            with open(tmp, "wb") as w:
                                w.write(NAS.read_bytes(orig))
                            _ev_ensure_thumb_dir(year, title)
                            _make_video_thumb2(tmp, year, title, name, sub)
                        finally:
                            try:
                                os.unlink(tmp)
                            except Exception:
                                pass
            except Exception as e:
                print("thumb build(get) fail", name, e)
    if not NAS.exists(_ev_thumb_path(year, title, name, sub)):
        return None
    try:
        data = NAS.read_bytes(_ev_thumb_path(year, title, name, sub))
    except Exception:
        return None
    _thumb_disk_put(year, title, name, sub, data)
    return data


def _ev_collect_under(base, rel_prefix="", recursive=True):
    """base 폴더 아래 파일들을 rel 경로와 함께 수집 (rel_prefix 기준)."""
    if not base or not NAS.exists(base):
        return []
    paths = []

    def walk(p, rel):
        r = NAS.list(p)
        if not r.get("ok"):
            return
        for f in r["files"]:
            nm = f["name"]
            if nm.startswith("."):
                continue
            child = f"{p}/{nm}"
            if f.get("isdir"):
                if recursive:
                    walk(child, f"{rel}/{nm}")
            else:
                paths.append({"path": child, "rel": f"{rel}/{nm}"})
    walk(base, rel_prefix or base.rsplit("/", 1)[-1])
    return paths


def _ev_collect_paths(year, title, key, sub="", recursive=True):
    """항목 폴더(하위경로)의 파일 경로 목록(ZIP용). rel은 하위폴더명 유지."""
    return _ev_collect_under(_ev_sub_dir(year, title, key, sub), recursive=recursive)


def _ev_zip_paths(year, title):
    """행사 전체 폴더의 파일 경로 목록 (ZIP용)."""
    base = _ev_dir(year, title)
    if not NAS.exists(base):
        return []
    paths = []

    def walk(p, rel):
        r = NAS.list(p)
        if not r.get("ok"):
            return
        for f in r["files"]:
            nm = f["name"]
            if nm.startswith("."):
                continue
            child = f"{p}/{nm}"
            if f.get("isdir"):
                walk(child, f"{rel}/{nm}")
            else:
                paths.append({"path": child, "rel": f"{rel}/{nm}"})
    walk(base, _ev_safe(title))
    return paths


def _ev_ext_ok(name):
    return _ext_of(name)


def _ev_build_zip(paths, files=None):
    """NAS 파일들을 ZIP으로 묶어 bytes 반환. files 우선, 없으면 paths로 fetch."""
    import io, zipfile
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for it in (files if files is not None else []):
            z.writestr(it["rel"], it["data"])
        if files is None:
            for it in paths:
                try:
                    data = NAS.read_bytes(it["path"])
                except Exception:
                    continue
                z.writestr(it["rel"], data)
    return buf.getvalue()


def _ev_roster_html(year, title):
    """참가자 명단을 무인양품풍 + 컬러풀 디자인 HTML로 출력 (인쇄/저장용)."""
    doc = _ev_doc()
    e = doc.get("events", {}).get(_ev_id(year, title), {})
    attendees = e.get("attendees", [])
    place = e.get("place", "")
    period = e.get("period", "") or e.get("date", "")
    desc = e.get("desc", "")
    access = _ev_access_map(_ev_id(year, title))

    # 범스카우트 색채(프랑스 국기: 블루·화이트·레드) 중심 팔레트
    palette = ["#1B4F9C", "#D62828", "#2E7D32", "#B7791F", "#00838F",
               "#6D4C41", "#AD1457", "#283593", "#5B2C8D", "#37474F"]

    def esc(s):
        return (str(s or "")
                .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))

    rows = []
    for i, a in enumerate(attendees, 1):
        ident = re.sub(r"[^0-9]", "", str(a.get("number") or a.get("phone") or ""))
        visited = ident in access
        color = palette[(i - 1) % len(palette)]
        roles = a.get("roles") or ([a.get("role")] if a.get("role") else [])
        role_chips = "".join(
            f'<span style="display:inline-block;margin:1px 3px 1px 0;padding:2px 8px;'
            f'border-radius:10px;background:{color}22;color:{color};font-size:11px;'
            f'font-weight:700">{esc(r)}</span>' for r in roles
        )
        vbox = (
            '<span style="display:inline-block;width:16px;height:16px;line-height:16px;'
            'text-align:center;border-radius:4px;background:#2E7D32;color:#fff;'
            'font-size:11px;font-weight:800">V</span>'
            if visited else
            '<span style="display:inline-block;width:16px;height:16px;border:1px solid #ccc;'
            'border-radius:4px"></span>'
        )
        rows.append(f"""
      <tr style="border-bottom:1px solid #eee">
        <td style="padding:8px 6px;color:#888;font-size:12px">{i}</td>
        <td style="padding:8px 6px;text-align:center">{vbox}</td>
        <td style="padding:8px 6px;font-weight:700">{esc(a.get('name',''))}</td>
        <td style="padding:8px 6px;font-size:13px;color:#555">{esc(a.get('unit',''))}</td>
        <td style="padding:8px 6px;font-size:12px">{esc(a.get('gender',''))}</td>
        <td style="padding:8px 6px;font-size:12px">{esc(a.get('phone',''))}</td>
        <td style="padding:8px 6px;font-size:12px">{esc(a.get('email',''))}</td>
        <td style="padding:8px 6px">{role_chips}</td>
      </tr>""")

    return f"""<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)} 참가자 명단</title>
<style>
  * {{ box-sizing:border-box; }}
  :root {{ --blue:#1B4F9C; --red:#D62828; --white:#fff; --ink:#171E33; --bg:#F5F4F0; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
    font-family:-apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Noto Sans KR','Malgun Gothic',sans-serif;
    -webkit-print-color-adjust:exact; print-color-adjust:exact; }}
  .wrap {{ max-width:960px; margin:0 auto; padding:34px 22px 60px; }}
  /* 프랑스 국기 트리컬러 바 */
  .fr {{ display:flex; height:7px; border-radius:99px; overflow:hidden; margin-bottom:24px;
    box-shadow:0 2px 8px rgba(27,79,156,.18); }}
  .fr i {{ flex:1; }} .fr i:nth-child(1){{background:var(--blue);}}
  .fr i:nth-child(2){{background:#fff;border-top:1px solid #e6e6ee;border-bottom:1px solid #e6e6ee;}}
  .fr i:nth-child(3){{background:var(--red);}}
  .head {{ background:#fff; border:1px solid #e8e8e2; border-radius:22px;
    padding:30px 30px 26px; position:relative; box-shadow:0 2px 14px rgba(23,30,51,.05); }}
  .kicker {{ font-size:12px; letter-spacing:2.5px; font-weight:800; color:var(--blue);
    text-transform:uppercase; }}
  .kicker .r {{ color:var(--red); }}
  .head h1 {{ margin:9px 0 0; font-size:30px; letter-spacing:-.6px; font-weight:900; }}
  .emblem {{ position:absolute; right:26px; top:26px; width:64px; height:64px; object-fit:contain; }}
  .meta {{ display:flex; flex-wrap:wrap; gap:9px 24px; margin-top:16px; font-size:13.5px; }}
  .meta b {{ font-weight:800; color:var(--blue); }}
  .rule {{ height:1px; background:#edede8; margin:18px 0 4px; }}
  .lead {{ margin-top:14px; font-size:13.5px; color:#4a5570; line-height:1.7; }}
  .counts {{ display:flex; gap:12px; margin-top:20px; flex-wrap:wrap; }}
  .stat {{ flex:1; min-width:110px; background:#fbfbf8; border:1px solid #ececE6;
    border-radius:14px; padding:13px 16px; }}
  .stat .n {{ font-size:22px; font-weight:900; color:var(--blue); }}
  .stat .l {{ font-size:11.5px; color:#7a8194; margin-top:2px; }}
  table {{ width:100%; border-collapse:separate; border-spacing:0; margin-top:22px; background:#fff;
    border:1px solid #e8e8e2; border-radius:16px; overflow:hidden;
    box-shadow:0 2px 14px rgba(23,30,51,.05); }}
  th {{ background:#f2f5fb; color:var(--blue); text-align:left; padding:12px 10px;
    font-size:11.5px; letter-spacing:.3px; font-weight:800; border-bottom:1px solid #e8e8e2; }}
  th:nth-child(3) {{ color:var(--red); }}
  td {{ border-bottom:1px solid #f1f1ec; }}
  tbody tr:nth-child(even) td {{ background:#fcfcfa; }}
  tbody tr:last-child td {{ border-bottom:0; }}
  .foot {{ margin-top:26px; font-size:12px; color:#98a0b2; text-align:center; line-height:1.7; }}
  @media print {{
    body {{ background:#fff; }} .wrap {{ padding:0; }}
    table, .head {{ box-shadow:none; }}
    .no-print {{ display:none !important; }}
  }}
  .printbtn {{ position:fixed; right:20px; bottom:20px; background:var(--blue); color:#fff;
    border:0; border-radius:14px; padding:14px 20px; font-size:14px; font-weight:800;
    font-family:inherit; cursor:pointer; box-shadow:0 10px 26px rgba(27,79,156,.32); }}
</style></head>
<body><div class="wrap">
  <div class="fr"><i></i><i></i><i></i></div>
  <div class="head">
    <img class="emblem" src="/assets/assets/images/tsak_emblem.png" alt="TSAK"
         onerror="this.style.display='none'">
    <div class="kicker">Tiger <span class="r">Scout</span> Association of Korea</div>
    <h1>{esc(title)}</h1>
    <div class="meta">
      {'<span><b>연도</b> ' + esc(year) + '</span>' if year else ''}
      {'<span><b>기간</b> ' + esc(period) + '</span>' if period else ''}
      {'<span><b>장소</b> ' + esc(place) + '</span>' if place else ''}
    </div>
    <div class="counts">
      <div class="stat"><div class="n">{len(attendees)}</div><div class="l">총 참가자(명)</div></div>
      <div class="stat"><div class="n">{len(access)}</div><div class="l">사진폴더 접속(명)</div></div>
    </div>
    {'<div class="rule"></div><div class="lead">' + esc(desc) + '</div>' if desc else ''}
  </div>
  <table>
    <thead><tr>
      <th>#</th><th>접속</th><th>이름</th><th>소속</th><th>성별</th>
      <th>연락처</th><th>메일</th><th>항목</th>
    </tr></thead>
    <tbody>{''.join(rows) or '<tr><td colspan="8" style="padding:26px;text-align:center;color:#98a0b2">참가자가 없습니다</td></tr>'}</tbody>
  </table>
  <div class="foot">한국범스카우트 중앙회 (TSAK) · 접속 V = 사진폴더 접근 이력<br>
    출력일시 {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}</div>
</div>
<button class="printbtn no-print" onclick="window.print()">🖨 인쇄 / PDF 저장</button>
</body></html>"""



# ============ 재무 연동 (행사 참가비/후원금/지출) ============
def _ev_fin_add(tx):
    """finance.json 에 거래 1건 append (참가비/후원금/지출 연동)."""
    fin = _load_json(FIN_FILE, _default_finance())
    txs = fin.setdefault("transactions", [])
    txs.insert(0, tx)
    fin["version"] = int(fin.get("version", 0)) + 1
    fin["updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    _save_json(FIN_FILE, fin)
    try:
        _rebuild_history(fin)
    except Exception:
        pass
    return tx


def _ev_fin_remove(tx):
    fin = _load_json(FIN_FILE, _default_finance())
    txs = fin.get("transactions", [])
    before = len(txs)
    fin["transactions"] = [
        t for t in txs
        if not (t.get("event") == tx.get("event")
                and t.get("payer") == tx.get("payer")
                and int(t.get("amount", 0) or 0) == int(tx.get("amount", 0) or 0)
                and t.get("category") == tx.get("category")
                and t.get("date") == tx.get("date"))
    ]
    if len(fin["transactions"]) != before:
        fin["version"] = int(fin.get("version", 0)) + 1
        fin["updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        _save_json(FIN_FILE, fin)
    return True


def _ev_fin_event(event_name):
    """특정 행사에 연동된 거래 목록 (참가비/후원금/지출)."""
    fin = _load_json(FIN_FILE, _default_finance())
    out = []
    for t in fin.get("transactions", []):
        if t.get("event") == event_name:
            out.append(t)
    return out


def _ev_phone_last4(phone):
    d = re.sub(r"[^0-9]", "", str(phone or ""))
    return d[-4:] if len(d) >= 4 else d


def _ev_load_regular_pw():
    return _load_json(REGULAR_FILE, {})


def _ev_save_regular_pw(d):
    _save_json(REGULAR_FILE, d)



# ============ 행사 참석자 ↔ 회원 연동 · 접근 로그 ============
def _ev_members():
    return _load_json(DB_FILE, [])


def _ev_member_by_ident(ident):
    """인가번호 또는 전화번호로 회원 1명 찾기."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d:
        return None
    for m in _ev_members():
        if re.sub(r"[^0-9]", "", str(m.get("number", ""))) == d:
            return m
        if re.sub(r"[^0-9]", "", str(m.get("phone", ""))) == d:
            return m
    return None


def _ev_member_set_event(ident, event_name, value=True):
    """회원의 eventAttend 맵에 행사명 기록/해제 → 개인 프로필 자동 반영."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d:
        return False
    members = _ev_members()
    hit = False
    for i, m in enumerate(members):
        if (re.sub(r"[^0-9]", "", str(m.get("number", ""))) == d
                or re.sub(r"[^0-9]", "", str(m.get("phone", ""))) == d):
            ev = m.get("eventAttend")
            if not isinstance(ev, dict):
                ev = {}
            ev[event_name] = bool(value)
            m["eventAttend"] = ev
            members[i] = m
            hit = True
            break
    if hit:
        if NAS.exists(DB_FILE):
            stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            try:
                NAS.write(f"{BASE}/backups/members_{stamp}.json",
                          NAS.read(DB_FILE).encode("utf-8"))
            except Exception:
                pass
        _save_json(DB_FILE, members)
        _touch_meta({"count": len(members), "updatedBy": "event"})
    return hit


def _ev_member_set_event_batch(idents, event_name, value=True, members=None,
                               backup=True, meta=True):
    """여러 회원의 eventAttend 를 한 번의 로드/저장으로 갱신 (성능).

    members 를 넘기면 재조회 없이 그 리스트를 갱신한다(호출측이 저장 책임).
    반환: 갱신된 회원 수.
    """
    ds = {re.sub(r"[^0-9]", "", str(i or "")) for i in idents}
    ds.discard("")
    if not ds:
        return 0
    own = members is None
    if own:
        members = _ev_members()
    hit = 0
    for i, m in enumerate(members):
        mid = re.sub(r"[^0-9]", "", str(m.get("number", "")))
        mp = re.sub(r"[^0-9]", "", str(m.get("phone", "")))
        mlid = re.sub(r"[^0-9]", "", str(m.get("loginId", "")))
        if mid in ds or mp in ds or mlid in ds:
            ev = m.get("eventAttend")
            if not isinstance(ev, dict):
                ev = {}
            ev[event_name] = bool(value)
            m["eventAttend"] = ev
            members[i] = m
            hit += 1
    if hit and own:
        if backup:
            _ev_backup_members()
        _save_json(DB_FILE, members)
        if meta:
            _touch_meta({"count": len(members), "updatedBy": "event"})
    return hit


def _ev_backup_members():
    """members.json 백업 1회(쓰기 전 원본 보존)."""
    try:
        if NAS.exists(DB_FILE):
            stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            NAS.write(f"{BASE}/backups/members_{stamp}.json",
                      NAS.read(DB_FILE).encode("utf-8"))
    except Exception:
        pass


# 회원파일 백그라운드 쓰기 직렬화(동시 스캔 시 서로 덮어쓰기 방지)
_MEMBER_WRITE_LOCK = threading.Lock()


def _ev_guest_ensure_account_async(phone, name, event_name):
    """비인가자 계정 보장 + eventAttend 를 백그라운드에서 처리.

    · 전화번호 일치 계정이 있으면 재사용(프로필 보완), 없으면 신규 생성.
    · 생성/갱신 후 members.json 1회 저장.
    응답을 지연시키지 않기 위해 별도 스레드에서 실행.
    """
    d = re.sub(r"[^0-9]", "", str(phone or ""))
    nm = str(name or "").strip()
    if not d:
        return

    def _job():
        try:
            with _MEMBER_WRITE_LOCK:
                members = _ev_members()
                found = None
                for m in members:
                    if re.sub(r"[^0-9]", "", str(
                            m.get("accessPhone") or m.get("phone") or "")) == d:
                        found = m
                        break
                if not found:
                    existing = {re.sub(r"[^0-9]", "", str(x.get("number", "")))
                                for x in members}
                    newno = ""
                    for cand in range(900001, 900001 + max(1, len(members) + 10)):
                        if str(cand) not in existing:
                            newno = str(cand)
                            break
                    if not newno:
                        newno = str(900001 + len(members))
                    found = {
                        "id": "guest_" + newno,
                        "number": newno,
                        "name": nm,
                        "unit": "", "league": "",
                        "phone": d, "accessPhone": d, "loginId": d,
                        "isRegular": True,
                        "personalPassword": _ev_phone_last4(d),
                        # 신규 일반회원은 관리자·마스터 승인 대기(pending) 상태로 생성.
                        "approvalStatus": "pending",
                    }
                    members.append(found)
                else:
                    if not found.get("isRegular"):
                        found["isRegular"] = True
                    if not found.get("loginId"):
                        found["loginId"] = d
                    if not found.get("accessPhone"):
                        found["accessPhone"] = d
                if event_name:
                    ev = found.get("eventAttend")
                    if not isinstance(ev, dict):
                        ev = {}
                    ev[event_name] = True
                    found["eventAttend"] = ev
                _save_json(DB_FILE, members)
                _touch_meta({"count": len(members), "updatedBy": "qr_join"})
        except Exception:
            pass

    threading.Thread(target=_job, daemon=True).start()


def _ev_member_event_async(ident, event_name, value=True):
    """응답을 지연시키지 않도록 회원 eventAttend 갱신을 백그라운드로 처리.

    직렬화 락 하에 members.json 을 다시 읽어 안전하게 반영한다(가산적).
    """
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d:
        return

    def _job():
        try:
            with _MEMBER_WRITE_LOCK:
                members = _ev_members()
                for i, m in enumerate(members):
                    if (re.sub(r"[^0-9]", "", str(m.get("number", ""))) == d
                            or re.sub(r"[^0-9]", "", str(m.get("phone", ""))) == d
                            or re.sub(r"[^0-9]", "", str(m.get("loginId", ""))) == d):
                        ev = m.get("eventAttend")
                        if not isinstance(ev, dict):
                            ev = {}
                        ev[event_name] = bool(value)
                        m["eventAttend"] = ev
                        members[i] = m
                        _save_json(DB_FILE, members)
                        _touch_meta({"updatedBy": "event"})
                        break
        except Exception:
            pass

    threading.Thread(target=_job, daemon=True).start()


def _ev_log_access(eid, entry):
    """행사 접근 이력 1건 기록."""
    doc = _ev_doc()
    e = doc.get("events", {}).get(eid)
    if not e:
        return False
    log = e.setdefault("accessLog", [])
    log.insert(0, entry)
    e["accessLog"] = log[:500]
    _ev_save(doc)
    return True


def _ev_access_map(eid):
    """행사 접근 이력 → {식별자: 마지막접속} 맵."""
    doc = _ev_doc()
    e = doc.get("events", {}).get(eid, {})
    out = {}
    for it in e.get("accessLog", []):
        key = re.sub(r"[^0-9]", "", str(it.get("id", "") or it.get("number", "")))
        if key:
            out[key] = it
    return out


# ============ QR 행사 참여 (스캔 → 참가 등록) ============
def _ev_public_event(year, title):
    """QR 착지용 공개 행사 요약(민감정보 제외). 없으면 None."""
    doc = _ev_doc()
    e = doc.get("events", {}).get(_ev_id(year, title))
    if not e:
        return None
    return {
        "year": e.get("year", year),
        "title": e.get("title", title),
        "period": e.get("period", "") or e.get("date", ""),
        "place": e.get("place", ""),
        "count": len(e.get("attendees", [])),
    }


def _ev_attendee_ident(a):
    """참가자 항목의 식별자(인가번호 우선, 없으면 전화/로그인ID)."""
    return re.sub(r"[^0-9]", "", str(
        a.get("number") or a.get("loginId") or a.get("phone") or ""))


def _ev_is_attendee(e, ident):
    """해당 식별자가 이미 참가자 명단에 있는지."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d:
        return False
    return any(_ev_attendee_ident(a) == d for a in e.get("attendees", []))


def _ev_add_attendee_entry(e, entry):
    """행사 참가자 명단에 1명 추가(중복 식별자면 스킵). 추가 여부 반환."""
    e.setdefault("attendees", [])
    if _ev_is_attendee(e, _ev_attendee_ident(entry)):
        return False
    e["attendees"].append(entry)
    return True


def _ev_qr_join_credentialed(year, title, number):
    """[QR] 범스카우트 인가자: 인가번호로 행사 참여 등록.

    로그인 과정 없이 인가번호만으로 등록한다(QR 자체가 접근 매개).
    """
    d = re.sub(r"[^0-9]", "", str(number or ""))
    if not d:
        return {"ok": False, "error": "number", "message": "인가번호를 입력해 주세요."}, 400
    # 회원 목록 1회 로드 후 재사용(조회/저장 중복 제거)
    _members = _ev_members()
    m = None
    for _x in _members:
        if (re.sub(r"[^0-9]", "", str(_x.get("number", ""))) == d
                or re.sub(r"[^0-9]", "", str(_x.get("phone", ""))) == d
                or re.sub(r"[^0-9]", "", str(_x.get("loginId", ""))) == d):
            m = _x
            break
    if not m:
        return {"ok": False, "error": "not_member",
                "message": "등록되지 않은 인가번호입니다. 번호를 확인해 주세요."}, 404
    entry = {
        "number": str(m.get("number", d)),
        "name": str(m.get("name", "")),
        "unit": str(m.get("unit", "")),
        "league": str(m.get("league", "")),
        "phone": str(m.get("phone", "")),
        "roles": [],
    }
    eid = _ev_id(year, title)
    # 이벤트 문서 1회 저장
    with LOCK:
        doc = _ev_doc()
        e = doc.get("events", {}).get(eid)
        if not e:
            return {"ok": False, "error": "no_event",
                    "message": "행사를 찾을 수 없습니다."}, 404
        if _ev_is_attendee(e, d):
            already = True
        else:
            already = False
            _ev_add_attendee_entry(e, entry)
            e.setdefault("accessLog", []).insert(0, {
                "id": d, "name": entry["name"], "via": "qr",
                "at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")})
            e["accessLog"] = e["accessLog"][:500]
            _ev_save(doc)
    # 회원 eventAttend 연동 — 응답 지연을 피하기 위해 백그라운드 처리
    if not already:
        _ev_member_event_async(d, title, True)
    if already:
        return {"ok": True, "already": True, "name": m.get("name", ""),
                "kind": "credentialed",
                "message": "이미 참가자로 등록되어 있습니다."}, 200
    return {"ok": True, "name": entry["name"], "kind": "credentialed",
            "message": "행사 참가자로 등록되었습니다."}, 200


def _ev_qr_join_guest(year, title, name, phone):
    """[QR] 비인가자: 전화번호+이름으로 아이디 자동 생성 후 참여 등록.

    · 신규: members.json 에 isRegular=true 회원 생성(loginId=전화번호)
      → 추후 전화번호로 로그인 가능(비번: 전화 뒤 4자리)
    · 기존(전화번호 일치): 기존 회원 사용
    """
    name = str(name or "").strip()
    d = re.sub(r"[^0-9]", "", str(phone or ""))
    if not name:
        return {"ok": False, "error": "name", "message": "이름을 입력해 주세요."}, 400
    if len(d) < 9:
        return {"ok": False, "error": "phone",
                "message": "전화번호를 정확히 입력해 주세요."}, 400
    eid = _ev_id(year, title)
    # 이벤트 문서만 동기 처리(회원 파일 읽기/쓰기는 백그라운드 → 응답 즉시)
    with LOCK:
        doc = _ev_doc()
        e = doc.get("events", {}).get(eid)
        if not e:
            return {"ok": False, "error": "no_event",
                    "message": "행사를 찾을 수 없습니다."}, 404
        already = _ev_is_attendee(e, d)
        if not already:
            entry = {
                "loginId": d,
                "name": name,
                "unit": "",
                "phone": d,
                "roles": [],
            }
            _ev_add_attendee_entry(e, entry)
            e.setdefault("accessLog", []).insert(0, {
                "id": d, "name": name, "via": "qr",
                "at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")})
            e["accessLog"] = e["accessLog"][:500]
            _ev_save(doc)
    # 회원 계정 보장(신규 생성/재사용) + eventAttend 를 백그라운드에서 처리
    if not already:
        _ev_guest_ensure_account_async(d, name, title)
    if already:
        return {"ok": True, "already": True, "name": name,
                "loginId": d, "kind": "guest",
                "message": "이미 참가자로 등록되어 있습니다."}, 200
    return {"ok": True, "name": name, "loginId": d, "kind": "guest",
            "created": True, "pw_hint": _ev_phone_last4(d),
            "message": "참가자로 등록되었습니다. 아이디는 전화번호, "
                       "비밀번호는 전화번호 뒤 4자리입니다."}, 200


def _ev_member_add_attendee(year, title, entry):
    """관리자가 참가자 명단에 직접 1명 추가(수동/검색 공용)."""
    eid = _ev_id(year, title)
    with LOCK:
        doc = _ev_doc()
        e = doc.get("events", {}).get(eid)
        if not e:
            return False
        added = _ev_add_attendee_entry(e, entry)
        if added:
            _ev_save(doc)
        return added
    return False



# ============ 입금자 자동분류 · 통계 · 엑셀 ============
_EXPENSE_KWS = [
    "출금", "지출", "지급", "이체출", "송금", "인출", "결제", "구매대금",
    "임차", "수수료", "공과금", "전기", "수도", "통신", "급여", "운영비",
    "행사비", "물품", "반환", "환불",
    "withdraw", "withdrawal", "debit", "payment", "transfer out",
]
_INCOME_KWS = [
    "입금", "입금자", "후원", "찬조", "기부", "수품", "구매", "참가", "참가비",
    "행사비", "연회비", "회비", "평생", "CMS", "자동이체",
    "deposit", "credit", "received", "incoming",
]


def _looks_expense(memo, amount):
    """적요/메모에 지출 신호어가 있고, 음수이거나 지출 신호가 명확할 때 True."""
    text = (memo or "")
    if amount < 0:
        return True
    exp = any(k in text for k in _EXPENSE_KWS)
    inc = any(k in text for k in _INCOME_KWS)
    # 지출 신호만 있고 수입 신호가 없으면 지출로 판정
    if exp and not inc:
        return True
    return False


def _guess_category(memo, amount, rules):
    """적요/메모로 카테고리 추정 (수입·지출·평생회비 포함)."""
    text = (memo or "")
    # 1) 사용자 정의 행사명→분류 규칙 최우선
    for kw, cat in (rules.get("events") or {}).items():
        if kw and kw in text:
            return cat
    # 2) 지출 신호가 명확하면 지출 카테고리로
    if _looks_expense(memo, amount):
        if "행사" in text or "참가" in text:
            return "행사비"
        if "수품" in text or "물품" in text or "구매" in text:
            return "수품구매"
        if "후원" in text or "찬조" in text or "기부" in text:
            return "후원금집행"
        return "운영비"
    # 3) 수입 카테고리 (평생회비 우선 인식)
    for kw, cat in (
        ("평생", "평생회비"), ("평생회비", "평생회비"),
        ("후원", "후원"), ("찬조", "후원"), ("기부", "후원"),
        ("수품", "수품구매"), ("구매", "수품구매"), ("물품", "수품구매"),
        ("참가비", "참가비"), ("참가", "참가비"), ("행사비", "참가비"),
        ("연회비", "연회비"), ("회비", "연회비"),
    ):
        if kw in text:
            return cat
    # 4) 미상: 금액 부호로 판정
    return "후원" if amount >= 0 else "운영비"


def _account_kind(filename):
    """파일명의 계좌번호 → 계좌 성격(수입 기본 카테고리·지출 기본 카테고리).

    대표(202-281140)=후원, 수품(102-281143)=수품구매, 행사(003-886274)=참가비/행사비.
    """
    s = re.sub(r"[^0-9]", "", filename or "")
    if "102281143" in s:
        return {"income": "수품구매", "expense": "수품구매"}
    if "003886274" in s:
        return {"income": "참가비", "expense": "행사비"}
    if "202281140" in s:
        return {"income": "후원", "expense": "후원금집행"}
    if "281140" in s:
        return {"income": "후원", "expense": "후원금집행"}
    if "281143" in s:
        return {"income": "수품구매", "expense": "수품구매"}
    if "886274" in s:
        return {"income": "참가비", "expense": "행사비"}
    return None


def _classify(obj, members, rules, account_kind=None):
    """행사명/이름 인식 → 동일인 인지 → 인가번호·상세 기록."""
    payer_raw = (obj.get("payer") or obj.get("name") or "").strip()
    memo = (obj.get("memo") or "").strip()
    date = (obj.get("date") or "").strip()
    amount = _sanitize_amount(obj.get("amount"))
    number = re.sub(r"[^0-9]", "", str(obj.get("number") or ""))
    context_parts = []
    name = (obj.get("name") or "").strip()
    matched_no, matched_name, matched_id = "", "", ""

    # 1) 별칭 규칙 우선
    for alias, no in (rules.get("aliases") or {}).items():
        if alias and alias in payer_raw:
            matched_no = re.sub(r"[^0-9]", "", str(no))
            if alias != name:
                context_parts.append(f"별칭:{alias}")
            break

    # 2) 번호가 명시되면 이름으로 인가자 특정
    if not matched_no and number:
        for m in members:
            if re.sub(r"[^0-9]", "", str(m.get("number", ""))) == number:
                matched_no = number
                matched_name = m.get("name", "")
                matched_id = m.get("id", "")
                break
        if not matched_no:
            context_parts.append(f"번호:{number}(미등록)")

    # 3) 입금자 텍스트에서 이름 검색(앞/뒤에 다른 내용이 있어도 포함되면 인식)
    if not matched_no and payer_raw:
        best = None
        for m in members:
            mn = str(m.get("name", "")).strip()
            if len(mn) >= 2 and mn in payer_raw:
                # 더 긴(구체적) 이름 우선
                if best is None or len(mn) > len(str(best.get("name", ""))):
                    best = m
        if best is not None:
            matched_no = re.sub(r"[^0-9]", "", str(best.get("number", "")))
            matched_name = best.get("name", "")
            matched_id = best.get("id", "")
            # 앞뒤 잔여 텍스트를 맥락으로 기록
            residue = payer_raw.replace(matched_name, "").strip(" -·,_/()[]")
            if residue:
                context_parts.append(residue)

    # 행사명/이벤트 명시
    event_name = (obj.get("event") or "").strip()
    if event_name:
        context_parts.append(event_name)

    text_all = memo + " " + payer_raw + " " + event_name
    category = _guess_category(text_all, amount, rules)
    # 지정 유형(엑셀에 입금/출금 열이 있으면 우선), 없으면 지출 신호로 판정
    explicit = str(obj.get("type") or "").strip().lower()
    if explicit in ("expense", "지출", "출금", "출"):
        ttype = "expense"
    elif explicit in ("income", "입금", "수입", "입"):
        ttype = "income"
    else:
        ttype = "expense" if _looks_expense(text_all, amount) else "income"

    # 지출로 판정됐는데 수입 카테고리로 잡혔으면 지출 카테고리로 보정
    if ttype == "expense":
        if category in ("후원", "참가비", "연회비", "평생회비"):
            if "후원" in text_all or "찬조" in text_all or "기부" in text_all:
                category = "후원금집행"
            elif "수품" in text_all or "물품" in text_all or "구매" in text_all:
                category = "수품구매"
            else:
                category = "행사비"
        elif category in ("수품구매",):
            category = "수품구매"
        elif category not in ("행사비", "운영비", "후원금집행", "수품구매", "기타"):
            category = "운영비"
    # 계좌 힌트: 신호가 '기본 후원'으로 떨어진 경우 계좌 성격으로 교정
    if account_kind:
        if ttype == "income" and category in ("후원", "기타"):
            category = account_kind["income"]
        elif ttype == "expense" and category in ("행사비", "운영비", "후원금집행", "수품구매", "기타"):
            # 명확한 신호(운영비/수품구매)는 유지, 후원금집행은 유지
            if category in ("행사비", "기타"):
                category = account_kind["expense"]
    status = "matched" if matched_no else "unmatched"

    return {
        "date": date,
        "type": ttype,
        "payer": payer_raw,
        "name": name or matched_name or payer_raw,
        "number": matched_no,
        "memberId": matched_id,
        "matchedName": matched_name,
        "amount": amount,
        "category": category,
        "memo": memo,
        "event": event_name,
        "context": " / ".join([c for c in context_parts if c]),
        "status": status,
        "year": (re.findall(r"(20\d{2})", date) or [str(datetime.datetime.now().year)])[0],
    }


def _recompute_member_sums(fin):
    """인가번호별 입금 합계(카테고리별)."""
    by_no = {}
    for t in fin.get("transactions", []):
        no = re.sub(r"[^0-9]", "", str(t.get("number", "")))
        if not no:
            continue
        rec = by_no.setdefault(no, {"total": 0, "byCategory": {}})
        amt = int(t.get("amount", 0) or 0)
        rec["total"] += amt
        cat = t.get("category", "기타")
        rec["byCategory"][cat] = rec["byCategory"].get(cat, 0) + amt
    return by_no


def _rebuild_history(fin):
    """연도·월별 집계 스냅샷 저장."""
    years = {}
    for t in fin.get("transactions", []):
        y = str(t.get("year") or (re.findall(r"(20\d{2})", str(t.get("date", ""))) or ["미지정"])[0])
        m = (re.findall(r"20\d{2}[.\-/]?(\d{1,2})", str(t.get("date", ""))) or ["00"])[0]
        yy = years.setdefault(y, {"income": 0, "expense": 0, "byCategory": {}, "months": {}})
        amt = int(t.get("amount", 0) or 0)
        cat = t.get("category", "기타")
        typ = t.get("type", "income")
        if typ == "expense":
            yy["expense"] += amt
        else:
            yy["income"] += amt
        yy["byCategory"][cat] = yy["byCategory"].get(cat, 0) + amt
        mm = yy["months"].setdefault(m.zfill(2), {"income": 0, "expense": 0})
        mm["income" if typ != "expense" else "expense"] += amt
    hist = {"years": years, "updated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
    _save_json(HIST_FILE, hist)
    return hist


def _analyze_file(folder, name, content):
    """첨부 파일 자동분석: 은행거래/명단/후원현황 → 전 시트 요약 및 인원 통계."""
    low = name.lower()
    summary = f"{folder}/{name} 업로드"
    detail = {"folder": folder, "name": name}
    try:
        if folder in ("은행거래내역", "후원현황") or low.endswith((".xlsx", ".xls", ".csv")):
            sheets = _read_excel_sheets(content, name)
            acct = _account_kind(name)
            members = _load_json(DB_FILE, [])
            rules = _load_json(MAT_FILE, _default_mat())
            total_rows = total_matched = 0
            grand_total = 0
            per_sheet = []
            for sname, srows in sheets:
                if not srows:
                    continue
                objs = _rows_to_objects(srows)
                if not objs:
                    continue
                cls = [_classify(o, members, rules, account_kind=acct) for o in objs]
                matched = [c for c in cls if c["status"] == "matched"]
                stot = sum(c["amount"] for c in cls)
                total_rows += len(cls)
                total_matched += len(matched)
                grand_total += stot
                per_sheet.append({"sheet": sname, "rows": len(cls),
                                  "matched": len(matched), "total": stot})
            detail["sheets"] = per_sheet
            detail["rows"] = total_rows
            detail["matched"] = total_matched
            detail["total"] = grand_total
            note = f"{len(per_sheet)}개 시트 · " if len(per_sheet) > 1 else ""
            summary = (f"{note}{total_rows}건 분석 · {total_matched}건 인가자 매칭 "
                       f"· 합계 {grand_total:,}원")
        elif folder in ("인가자명단", "명단"):
            sheets = _read_excel_sheets(content, name)
            total = 0
            for sname, srows in sheets:
                total += max(0, len([r for r in srows if any(str(c).strip() for c in r)]) - 1)
            detail["rows"] = total
            summary = f"명단 {total}명 인식 ({len(sheets)}개 시트)"
    except Exception as e:
        summary = f"{folder}/{name} (분석 실패: {e})"
    detail["summary"] = summary
    return detail


def _build_excel(kind="finance"):
    """통합 재무 엑셀 생성 (거래·연도별집계·인가자별 요약)."""
    import io
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment
    fin = _load_json(FIN_FILE, _default_finance())
    wb = openpyxl.Workbook()
    head_fill = PatternFill("solid", fgColor="1F6E43")
    head_font = Font(color="FFFFFF", bold=True)

    def style_head(ws):
        for c in ws[1]:
            c.fill = head_fill
            c.font = head_font
            c.alignment = Alignment(horizontal="center")

    # 1) 거래내역
    ws = wb.active
    ws.title = "거래내역"
    ws.append(["일자", "구분", "입금자", "이름", "인가번호", "금액", "분류", "행사", "맥락", "메모", "상태"])
    style_head(ws)
    for t in fin.get("transactions", []):
        ws.append([t.get("date", ""), "지출" if t.get("type") == "expense" else "입금",
                   t.get("payer", ""), t.get("name", ""), t.get("number", ""),
                   int(t.get("amount", 0) or 0), t.get("category", ""), t.get("event", ""),
                   t.get("context", ""), t.get("memo", ""),
                   "매칭" if t.get("status") == "matched" else "미매칭"])
    for col, w in zip("ABCDEFGHIJK", (12, 6, 14, 10, 10, 12, 10, 14, 20, 20, 8)):
        ws.column_dimensions[col].width = w

    # 2) 연도별 집계
    ws2 = wb.create_sheet("연도별집계")
    ws2.append(["연도", "수입합계", "지출합계", "순액", "인원수"])
    style_head(ws2)
    sums = _recompute_member_sums(fin)
    for y, v in sorted(_rebuild_history(fin).get("years", {}).items(), reverse=True):
        ws2.append([y, v.get("income", 0), v.get("expense", 0),
                    v.get("income", 0) - v.get("expense", 0), len(sums)])

    # 3) 인가자별 입금요약
    ws3 = wb.create_sheet("인가자별요약")
    ws3.append(["인가번호", "총입금", "후원", "수품구매", "참가비", "연회비", "기타"])
    style_head(ws3)
    for no, rec in sorted(sums.items(), key=lambda x: int(x[0]) if x[0].isdigit() else 0):
        bc = rec["byCategory"]
        ws3.append([no, rec["total"], bc.get("후원", 0), bc.get("수품구매", 0),
                    bc.get("참가비", 0), bc.get("연회비", 0), bc.get("기타", 0)])

    # 4) 분류규칙(별칭/행사)
    rules = _load_json(MAT_FILE, _default_mat())
    ws4 = wb.create_sheet("분류규칙")
    ws4.append(["종류", "키워드", "값"])
    style_head(ws4)
    for k, v in (rules.get("aliases") or {}).items():
        ws4.append(["별칭→인가번호", k, v])
    for k, v in (rules.get("events") or {}).items():
        ws4.append(["행사명→분류", k, v])

    bio = io.BytesIO()
    wb.save(bio)
    return bio.getvalue()


# ============ OCR (이미지/PDF 거래내역 자동분석) ============
def _ocr_image_bytes(content):
    """이미지 바이트 → 텍스트 (한국어+영어)."""
    import io
    from PIL import Image
    import pytesseract
    img = Image.open(io.BytesIO(content))
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    # 저해상도 보정: 폭이 작으면 확대
    if img.width < 1000:
        scale = 1000 / max(1, img.width)
        img = img.resize((int(img.width * scale), int(img.height * scale)))
    try:
        txt = pytesseract.image_to_string(img, lang="kor+eng")
    except Exception:
        txt = pytesseract.image_to_string(img, lang="eng")
    return txt


def _ocr_pdf_bytes(content):
    """PDF 바이트 → 텍스트 (페이지 렌더 후 OCR, 텍스트 추출 우선)."""
    import io
    import fitz  # PyMuPDF
    out = []
    doc = fitz.open(stream=content, filetype="pdf")
    for page in doc:
        # 1) 내장 텍스트가 충분하면 그대로 사용
        t = page.get_text("text") or ""
        if len(t.strip()) > 40:
            out.append(t)
            continue
        # 2) 스캔본 → 이미지 렌더 후 OCR
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
        img_bytes = pix.tobytes("png")
        out.append(_ocr_image_bytes(img_bytes))
    doc.close()
    return "\n".join(out)


_DATE_RE = re.compile(r"(20\d{2})[.\-/]?\s?(\d{1,2})[.\-/]\s?(\d{1,2})")
_SHORT_DATE_RE = re.compile(r"(?<!\d)(\d{1,2})[.\-/](\d{1,2})(?!\d)")
_AMOUNT_RE = re.compile(r"[-+]?\d{1,3}(?:,\d{3})+|[-+]?\d{4,}")


def _parse_ocr_text(text):
    """OCR 텍스트 → 거래 객체 리스트(휴리스틱 파서).

    각 줄에서 날짜·금액·출금/입금 여부를 추정하고 나머지를 입금자/적요로 사용.
    """
    objs = []
    for raw_line in text.splitlines():
        line = re.sub(r"\s+", " ", raw_line).strip()
        if len(line) < 4:
            continue
        # 머리말/꼬리말(조회기간·계좌번호·합계 등) 제외
        if _looks_meta_row([line]):
            continue
        # 금액 표기가 전혀 없는 라인 제외
        if not re.search(r"\d{3,}", line):
            continue
        # 날짜
        date = ""
        m = _DATE_RE.search(line)
        if m:
            date = f"{m.group(1)}-{m.group(2).zfill(2)}-{m.group(3).zfill(2)}"
        else:
            ms = _SHORT_DATE_RE.search(line)
            if ms:
                date = f"{datetime.datetime.now().year}-{ms.group(1).zfill(2)}-{ms.group(2).zfill(2)}"
        # 금액: 최대값 추출 후 상한 초과(계좌번호 등)는 배제
        amounts = [a for a in _AMOUNT_RE.findall(line)]
        amount = 0
        if amounts:
            nums = [_parse_amount(a) for a in amounts]
            nums = [n for n in nums if 0 < n <= _AMOUNT_MAX]
            if nums:
                amount = max(nums, key=lambda v: abs(v))
        if amount == 0 and not date:
            continue
        if amount == 0:
            continue
        # 유형
        lowline = line.lower()
        neg = ("-" in line and amount > 0 and re.search(r"-\s?\d", line) is not None)
        is_out = ("출금" in line) or neg or re.match(r"^\s*-", line) \
            or any(k in lowline for k in ("withdraw", "debit"))
        is_in = ("입금" in line) or ("후원" in line) or ("찬조" in line) \
            or ("기부" in line) or any(k in lowline for k in ("deposit", "credit"))
        ttype = "expense" if (is_out and not is_in) else "income"
        # 입금자/적요: 날짜·숫자 토큰 제거
        residue = line
        if date:
            residue = _DATE_RE.sub(" ", residue)
            residue = _SHORT_DATE_RE.sub(" ", residue)
        residue = _AMOUNT_RE.sub(" ", residue)
        residue = re.sub(r"\d{3,}", " ", residue)
        residue = re.sub(r"\b(입금|출금|잔액|합계|계좌|은행|원|No|번호|deposit|withdraw|withdrawal|credit|debit|transfer|account)\b", " ", residue, flags=re.IGNORECASE)
        residue = re.sub(r"\s+", " ", residue).strip(" -·,_/()[]:|")
        objs.append({
            "date": date,
            "payer": residue,
            "name": residue,
            "amount": str(abs(amount)),
            "memo": line,
            "type": ttype,
        })
    return objs


def _ocr_bank(content, filename, members, rules):
    """이미지/PDF 거래내역 → 자동분류 행 리스트."""
    low = (filename or "").lower()
    if low.endswith(".pdf"):
        text = _ocr_pdf_bytes(content)
    else:
        text = _ocr_image_bytes(content)
    objs = _parse_ocr_text(text)
    acct = _account_kind(filename)
    return [_classify(o, members, rules, account_kind=acct) for o in objs], text


def _compute_stats(fin, members):
    """DB 거래 전체 종합 통계 — 연도별/월별/행사별/분류별/기간별."""
    tx = fin.get("transactions", [])
    name_by_no = {re.sub(r"[^0-9]", "", str(m.get("number", ""))): m.get("name", "")
                  for m in members}

    def ym(t):
        y = str(t.get("year") or (re.findall(r"(20\d{2})", str(t.get("date", ""))) or ["미지정"])[0])
        mo = (re.findall(r"20\d{2}[.\-/]?(\d{1,2})", str(t.get("date", ""))) or [""])[0]
        return y, mo.zfill(2) if mo else ""

    by_year, by_month, by_cat, by_event, by_expcat = {}, {}, {}, {}, {}
    by_member = {}
    income_total = expense_total = 0
    for t in tx:
        amt = int(t.get("amount", 0) or 0)
        typ = t.get("type", "income")
        cat = t.get("category", "기타")
        y, mo = ym(t)
        rec = by_year.setdefault(y, {"income": 0, "expense": 0, "count": 0,
                                     "byCategory": {}, "months": {}})
        rec["count"] += 1
        if typ == "expense":
            rec["expense"] += amt
            expense_total += amt
            by_expcat[cat] = by_expcat.get(cat, 0) + amt
        else:
            rec["income"] += amt
            income_total += amt
            by_cat[cat] = by_cat.get(cat, 0) + amt
            no = re.sub(r"[^0-9]", "", str(t.get("number", "")))
            if no:
                mr = by_member.setdefault(no, {"name": name_by_no.get(no, t.get("name", "")),
                                               "total": 0, "byCategory": {}})
                mr["total"] += amt
                mr["byCategory"][cat] = mr["byCategory"].get(cat, 0) + amt
        rec["byCategory"][cat] = rec["byCategory"].get(cat, 0) + amt
        if y != "미지정" and mo:
            mk = f"{y}-{mo}"
            mm = by_month.setdefault(mk, {"income": 0, "expense": 0})
            mm["income" if typ != "expense" else "expense"] += amt
        mm2 = rec["months"].setdefault(mo or "00", {"income": 0, "expense": 0})
        mm2["income" if typ != "expense" else "expense"] += amt
        ev = str(t.get("event", "")).strip() or "(미지정)"
        er = by_event.setdefault(ev, {"income": 0, "expense": 0})
        er["income" if typ != "expense" else "expense"] += amt

    return {
        "total": {"income": income_total, "expense": expense_total,
                  "net": income_total - expense_total, "count": len(tx)},
        "byYear": by_year,
        "byMonth": dict(sorted(by_month.items())),
        "byCategory": by_cat,
        "byExpenseCategory": by_expcat,
        "byEvent": by_event,
        "byMember": by_member,
        "updated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }


def _bank_scheme(name):
    """은행명/핀테크명 → 앱 실행 URL 스킴. 없으면 None."""
    m = {
        "토스": "supertoss://send",
        "카카오뱅크": "kakaobank://",
        "케이뱅크": "kbank://",
        "국민은행": "kbbank://", "KB국민은행": "kbbank://",
        "신한은행": "shinhan-sbank://",
        "우리은행": "wooribank://",
        "하나은행": "hanabank://",
        "농협은행": "nhbapp://", "NH농협은행": "nhbapp://",
        "기업은행": "ibkonebank://", "IBK기업은행": "ibkonebank://",
        "SC제일은행": "scbank://",
        "한국씨티은행": "citibank://", "씨티은행": "citibank://",
        "부산은행": "busanbank://",
        "경남은행": "knbank://",
        "대구은행": "dgbbank://",
        "광주은행": "kjbank://",
        "전북은행": "jbbank://",
        "제주은행": "jejubank://",
        "수협은행": "suhyupbank://",
        "우체국": "epostbank://",
        "새마을금고": "mgbank://",
        "신협": "cuapp://",
    }
    t = re.sub(r"\s+", "", name or "")
    for k, v in m.items():
        if t and (k in t or t in k):
            return v
    return None


# 바로 송금 가능한 금융사(앱 스킴·표준코드·브랜드색) — Flutter 아이콘 목록과 동일
_PAY_APPS = [
    ("토스", "092", "0064FF", "supertoss://send"),
    ("카카오뱅크", "090", "FFCD00", "kakaobank://"),
    ("케이뱅크", "089", "00B4B0", "kbank://"),
    ("KB국민은행", "004", "FFB800", "kbbank://"),
    ("신한은행", "088", "0046FF", "shinhan-sbank://"),
    ("우리은행", "020", "0067AC", "wooribank://"),
    ("하나은행", "081", "009A93", "hanabank://"),
    ("NH농협은행", "011", "1B7C3D", "nhbapp://"),
    ("IBK기업은행", "003", "005EB8", "ibkonebank://"),
    ("SC제일은행", "023", "00694E", "scbank://"),
    ("한국씨티은행", "027", "0F4FA8", "citibank://"),
    ("부산은행", "032", "0059A5", "busanbank://"),
    ("경남은행", "039", "C8102E", "knbank://"),
    ("대구은행", "031", "0B4DA2", "dgbbank://"),
    ("광주은행", "034", "F0A500", "kjbank://"),
    ("전북은행", "037", "005BAC", "jbbank://"),
    ("제주은행", "035", "E87722", "jejubank://"),
    ("수협은행", "007", "0067A3", "suhyupbank://"),
    ("우체국", "071", "E8442E", "epostbank://"),
    ("새마을금고", "045", "00703C", "mgbank://"),
    ("신협", "048", "0083C6", "cuapp://"),
]


def _pay_landing_page(q):
    """송금 QR 착지 페이지.

    폰으로 QR을 스캔하면 이 https 페이지가 열리고, 페이지가 토스/은행 앱
    딥링크를 자동 실행한다. 자동 실행이 막히면 버튼으로 한 번 더 시도.
    """
    def g(k):
        return (q.get(k, [""])[0] or "").strip()

    bank = g("bank")
    account = g("account")
    try:
        amount = int(re.sub(r"[^0-9]", "", g("amount")) or "0")
    except Exception:
        amount = 0
    holder = g("holder")
    memo = g("memo")
    label = g("label")
    digits = re.sub(r"[^0-9]", "", account)
    amount_s = f"{amount:,}" if amount > 0 else ""

    # 금액 상한(비정상 입력 방지) — 1e21 이상이면 무시
    if amount < 0 or amount >= 10 ** 21:
        amount = 0

    def _deep(base, bank_name=""):
        """스킴에 (받는은행명)·계좌·금액 파라미터를 붙인 딥링크.

        토스 규격은 `bank=<은행명>`(예: bank=우리은행) 이다.
        (앱 자체 은행코드를 넣으면 받는 계좌와 불일치해 송금이 안 된다.)
        """
        params = []
        if bank_name:
            params.append("bank=" + urllib.parse.quote(bank_name))
        if digits:
            params.append(f"accountNo={digits}")
        if amount > 0:
            params.append(f"amount={amount}")
        return base + ("?" + "&".join(params) if params else "")

    bank_scheme = _bank_scheme(bank)
    esc = lambda s: (
        s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )
    bank_e, account_e, holder_e = esc(bank), esc(account), esc(holder)
    memo_row = (
        f'<div class="row"><span>메모</span><b>{esc(memo)}</b></div>' if memo else ""
    )
    amount_row = (
        f'<div class="amt">{amount_s}원</div>' if amount > 0 else ""
    )
    bank_btn = (
        f'<button class="btn open" id="bankbtn" '
        f'data-scheme="{esc(_deep(bank_scheme, bank) if bank_scheme else "")}">'
        f'{bank_e} 앱 열기</button>'
        if bank_scheme else ""
    )
    # 금융사 그리드 (전체 앱) — 금액·계좌 자동 입력
    app_cells = []
    for nm, code, color, scheme in _PAY_APPS:
        short = nm.replace("은행", "").replace("IBK", "IBK").strip() or nm
        lum_light = color in ("FFCD00", "FFB800", "F0A500")
        fg = "#1F1A2E" if lum_light else "#fff"
        # bank 파라미터는 **받는 계좌의 은행명**(query.bank)을 쓴다.
        # (앱마다 자기 코드를 넣던 기존 방식은 받는 은행과 불일치해 오류 유발)
        link = _deep(scheme, bank)
        app_cells.append(
            f'<a class="app" href="{esc(link)}" data-scheme="{esc(link)}" '
            f'data-code="{code}" data-name="{esc(nm)}">'
            f'<span class="ico" style="background:#{color};color:{fg}">'
            f'{esc(short[:3])}</span>'
            f'<span class="nm">{esc(nm)}</span></a>'
        )
    apps_html = "".join(app_cells)
    return f"""<!doctype html>
<html lang="ko"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TSAK 송금</title>
<style>
  *{{box-sizing:border-box}}
  body{{font-family:-apple-system,BlinkMacSystemFont,'Malgun Gothic','Apple SD Gothic Neo',sans-serif;
       margin:0;background:#f4f2f8;color:#1F1A2E;display:flex;min-height:100vh;
       align-items:center;justify-content:center;padding:20px}}
  .card{{background:#fff;max-width:420px;width:100%;border-radius:20px;
        padding:26px 22px;box-shadow:0 10px 30px rgba(91,44,141,.12);text-align:center}}
  .badge{{display:inline-block;background:rgba(242,183,5,.18);color:#1F1A2E;
         font-size:12px;font-weight:800;padding:4px 10px;border-radius:7px}}
  .bank{{margin-top:14px;font-size:13px;color:#6E6A7C;font-weight:700}}
  .no{{font-size:22px;font-weight:800;letter-spacing:.5px;margin:4px 0 10px}}
  .amt{{font-size:30px;font-weight:900;color:#5B2C8D;margin:8px 0}}
  .row{{display:flex;justify-content:space-between;font-size:13px;
       color:#6E6A7C;padding:6px 2px;border-top:1px solid #eee}}
  .row b{{color:#1F1A2E}}
  .btn{{display:block;width:100%;margin-top:14px;padding:15px;border:none;
       border-radius:12px;font-size:16px;font-weight:800;text-decoration:none;
       cursor:pointer}}
  .copy{{background:#5B2C8D;color:#fff}}
  .open{{background:#fff;color:#5B2C8D;border:1.5px solid #5B2C8D}}
  .grid{{display:grid;grid-template-columns:repeat(5,1fr);gap:10px 6px;
        margin-top:16px;padding-top:14px;border-top:1px dashed #e2dcef}}
  .app{{text-decoration:none;display:flex;flex-direction:column;align-items:center;
       gap:4px}}
  .ico{{width:40px;height:40px;border-radius:13px;display:flex;align-items:center;
       justify-content:center;font-size:10px;font-weight:800;letter-spacing:-.3px}}
  .nm{{font-size:9.5px;color:#1F1A2E;line-height:1.1}}
  .secttl{{font-size:12px;font-weight:800;color:#6E6A7C;margin-top:16px}}
  .hint{{font-size:12px;color:#6E6A7C;margin-top:14px;line-height:1.5}}
  .ok{{color:#2E7D32;font-size:12.5px;margin-top:10px;font-weight:700;display:none}}
</style></head>
<body>
  <div class="card">
    <span class="badge">{esc(label or '송금 정보')}</span>
    <div class="bank">{bank_e}</div>
    <div class="no">{account_e}</div>
    {amount_row}
    {f'<div class="row"><span>예금주</span><b>{esc(holder)}</b></div>' if holder else ''}
    {memo_row}
    {bank_btn}
    <button class="btn copy" id="copybtn">계좌번호 복사</button>
    <div class="ok" id="ok">복사됐어요! 은행 앱에 붙여넣으세요</div>
    <div class="secttl">바로 송금 (앱이 열려요)</div>
    <div class="grid">{apps_html}</div>
    <div class="hint">쓰시는 금융사 아이콘을 누르면 앱이 열려요.<br>
      앱이 안 열리면 「계좌번호 복사」 후 은행 앱에서 붙여넣어 송금하세요.</div>
  </div>
<script>
  var ACC = {json.dumps(account)};
  function copyAcc(){{
    function done(){{var ok=document.getElementById('ok');ok.style.display='block';
      setTimeout(function(){{ok.style.display='none';}},2500);}}
    if(navigator.clipboard){{navigator.clipboard.writeText(ACC).then(done).catch(fallbackCopy);}}
    else fallbackCopy();
  }}
  function fallbackCopy(){{
    var t=document.createElement('textarea'); t.value=ACC; document.body.appendChild(t);
    t.select(); try{{document.execCommand('copy');}}catch(e){{}}
    document.body.removeChild(t);
    var ok=document.getElementById('ok'); ok.style.display='block';
    setTimeout(function(){{ok.style.display='none';}},2500);
  }}
  document.getElementById('copybtn').addEventListener('click', copyAcc);
  // 금융사 앱 실행: 클릭 시 스킴으로 이동 (실패해도 페이지 유지)
  function openScheme(scheme){{
    try{{
      var ifr=document.createElement('iframe'); ifr.style.display='none';
      ifr.src=scheme;
      document.body.appendChild(ifr);
      setTimeout(function(){{document.body.removeChild(ifr);}},1500);
    }}catch(e){{}}
    try{{ window.location.href = scheme; }}catch(e){{}}
  }}
  document.querySelectorAll('.app, #bankbtn').forEach(function(el){{
    el.addEventListener('click', function(ev){{
      var s=el.getAttribute('data-scheme'); if(!s) return;
      ev.preventDefault(); openScheme(s);
    }});
  }});
</script>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    # TCP_NODELAY: 소켓 버퍼링(Nagle)으로 인한 ~0.5초 응답 지연 제거.
    #  (작은 응답이 ACK 를 기다리며 멈추는 지연-ACK/Nagle 상호작용 방지)
    disable_nagle_algorithm = True

    def setup(self):
        super().setup()
        try:
            import socket as _sock
            self.connection.setsockopt(_sock.IPPROTO_TCP, _sock.TCP_NODELAY, 1)
        except Exception:
            pass

    def log_message(self, *a):
        pass

    def _cors(self):
        # 보안 감사 F02 대응 — 임의 출처 읽기 차단.
        #  허용목록에 있는 Origin 에만 ACAO 를 반환한다(전역 '*' 제거).
        #  · 동일 출처(Origin == Host) 는 허용.
        #  · 그 외는 CORS_ALLOW_ORIGINS 에 명시된 것만 허용.
        origin = self.headers.get("Origin")
        self.send_header("Vary", "Origin")
        if origin:
            host = self.headers.get("Host", "")
            ok = False
            try:
                o = urllib.parse.urlparse(origin)
                if o.netloc and host and o.netloc == host:
                    ok = True
            except Exception:
                pass
            if not ok:
                for a in CORS_ALLOW_ORIGINS:
                    if a == "*":
                        ok = True
                        break
                    if origin == a or origin.endswith(a):
                        ok = True
                        break
            if ok:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, X-TSAK-Session, Authorization")
        # 방어 헤더 (F05/F06)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self' 'unsafe-inline' "
            "'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' "
            "data: blob:; font-src 'self' data:; connect-src 'self' "
            "https:; object-src 'none'; base-uri 'self'")
        self.send_header("Cache-Control", "no-store")

    def _cors_static(self):
        # 보안 감사 F02 — 정적 자산 서빙용 경량 CORS.
        #  캐시 정책(no-store)을 건드리지 않고 ACAO 만 허용목록 기준으로 붙인다.
        origin = self.headers.get("Origin")
        self.send_header("Vary", "Origin")
        if not origin:
            return
        ok = False
        try:
            o = urllib.parse.urlparse(origin)
            host = self.headers.get("Host", "")
            if o.netloc and host and o.netloc == host:
                ok = True
        except Exception:
            pass
        if not ok:
            for a in CORS_ALLOW_ORIGINS:
                if a == "*" or origin == a or origin.endswith(a):
                    ok = True
                    break
        if ok:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, X-TSAK-Session, Authorization")

    # ---- 세션 인증 (F01/F02) ----
    def _sid(self):
        """요청에서 세션토큰 추출: 쿠키 tsak_sid → 헤더 → 쿼리."""
        ck = self.headers.get("Cookie") or ""
        m = re.search(r"(?:^|;\s*)tsak_sid=([^;]+)", ck)
        if m:
            return urllib.parse.unquote(m.group(1)).strip()
        sid = (self.headers.get("X-TSAK-Session") or "").strip()
        if sid:
            return sid
        try:
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            return (q.get("sid", [""])[0] or "").strip()
        except Exception:
            return ""

    def _sess(self):
        return _sess_get(self._sid())

    def _auth_ok(self, need=None):
        """세션 또는 마스터 비번으로 인증 통과 여부."""
        s = self._sess()
        if not s:
            return False
        if need == "master":
            return s.get("tier") == "master"
        if need == "admin":
            return s.get("tier") in ("app", "master")
        return True

    def _require(self, need=None):
        """인증 실패 시 401 JSON 을 보내고 False 반환."""
        if not self._auth_ok(need):
            self._json({"ok": False, "error": "unauthorized"}, 401)
            return False
        return True

    def _set_sid_cookie(self, sid):
        self._pending_sid = sid

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if getattr(self, "_pending_sid", None):
            self.send_header(
                "Set-Cookie",
                "tsak_sid=%s; Path=/; Max-Age=%d; SameSite=Strict"
                % (urllib.parse.quote(self._pending_sid), _SESS_TTL))
            self._pending_sid = None
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _bytes(self, b, ctype="application/octet-stream"):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self._cors()
        self.end_headers()
        self.wfile.write(b)

    def _bytes_cache(self, b, ctype="application/octet-stream",
                     max_age=604800, immutable=True):
        """브라우저 캐시를 허용하는 바이트 응답 (썸네일 등 불변 리소스).

        파일명 기준이 아니라 API 응답이므로 현재는 last-modified 없이
        max-age 로만 캐시한다. 썸네일은 내용이 바뀌면 NAS 파일이 교체되므로
        캐시 무효화를 위해 앱에서 URL 에 타임스탬프를 붙이는 것을 권장.
        """
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        cc = f"public, max-age={max_age}"
        if immutable:
            cc += ", immutable"
        self.send_header("Cache-Control", cc)
        self._cors()
        self.end_headers()
        self.wfile.write(b)

    def _html(self, html_str, code=200):
        body = html_str.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _serve_nas_file(self, path, ctype, *, download_name=None, allow_range=True):
        """NAS 파일을 (동영상 탐색 가능한) Range 서빙."""
        try:
            data = NAS.read_bytes(path)
        except Exception as e:
            return self._json({"ok": False, "error": str(e)}, 404)
        total = len(data)
        start, end = 0, max(0, total - 1)
        status = 200
        rng = self.headers.get("Range") if allow_range else None
        if rng and rng.startswith("bytes="):
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                if m.group(1):
                    start = int(m.group(1))
                if m.group(2):
                    end = int(m.group(2))
                if end >= total:
                    end = total - 1
                if start > end or start >= total:
                    start = 0
                status = 206
        chunk = data[start:end + 1] if total else b""
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(len(chunk)))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
        if download_name:
            self.send_header(
                "Content-Disposition",
                "attachment; filename*=UTF-8''" + urllib.parse.quote(download_name))
        self._cors()
        self.end_headers()
        if chunk:
            self.wfile.write(chunk)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n) if n else b""

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        try:
            if p == "/api/health":
                return self._json({
                    "ok": True,
                    "paused": _server_paused(),
                    "ts": datetime.datetime.now().isoformat(),
                })
            # ---- 버전 감지(업데이트 반영) ----
            # 빌드 산출물(main.dart.js)의 수정시각을 버전으로 노출한다.
            # 재빌드(재배포) 시 값이 바뀌므로 클라이언트가 자동 감지/새로고침한다.
            if p == "/version.json":
                stamp = "0"
                try:
                    bf = os.path.join(STATIC_DIR, "main.dart.js")
                    mt = os.path.getmtime(bf)
                    # 한국시간(KST) 기준 YYYYMMDDHHMMSS — 앱(kBuildStampInt)과 동일 기준
                    try:
                        from zoneinfo import ZoneInfo
                        dt = datetime.datetime.fromtimestamp(
                            mt, ZoneInfo("Asia/Seoul"))
                    except Exception:
                        dt = datetime.datetime.fromtimestamp(mt)
                    stamp = dt.strftime("%Y%m%d%H%M%S")
                except Exception:
                    stamp = "0"
                vj = _load_json(os.path.join(STATIC_DIR, "version.json"), {})
                vj["build_id"] = stamp
                vj["version"] = stamp
                resp = self._json(vj)
                return resp
            # ---- 송금 QR 착지 페이지: 폰으로 스캔 → 은행/토스 앱 자동 실행 ----
            if p == "/pay":
                return self._html(_pay_landing_page(
                    urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)))
            if p == "/api/admin/state":
                if not self._require("admin"):
                    return
                cfg = _load_json(CFG_FILE, _default_config())
                s = self._sess() or {}
                # 앱 접근 비번은 마스터에게만 노출(관리자에게는 관리 UI 무의미).
                out = {
                    "ok": True,
                    "personalPasswords": cfg.get("personalPasswords", {}),
                    "serverPaused": bool(cfg.get("serverPaused", False)),
                }
                if s.get("tier") == "master":
                    out["appPassword"] = cfg.get("appPassword", APP_PW)
                return self._json(out)
            if p == "/api/members":
                # F01: 무인증 차단 + 역할별 최소 항목
                if not self._require():
                    return
                s = self._sess() or {}
                members = _load_json(DB_FILE, [])
                members = _scope_members(s.get("tier"), s.get("who"), members)
                return self._json({"ok": True, "members": members})
            # ---- 접속 비밀번호 "현재값" 조회 (요구: 마스터 로그인 시에만 노출) ----
            if p == "/api/member/password":
                if not self._require("master"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                no = re.sub(r"[^0-9]", "", str(q.get("number", [""])[0]))
                if not no:
                    return self._json({"ok": False, "error": "number"}, 400)
                m = _ev_member_by_ident(no)
                if not m:
                    return self._json({"ok": False, "error": "not found"}, 404)
                is_regular = bool(m.get("isRegular"))
                if is_regular:
                    key = re.sub(r"[^0-9]", "",
                                 str(m.get("accessPhone") or m.get("phone") or no))
                    pws = _ev_load_regular_pw()
                    pw = str(pws.get(key) or m.get("personalPassword")
                             or _ev_phone_last4(m.get("phone") or key))
                    default_pw = _ev_phone_last4(m.get("phone") or key)
                else:
                    pw = _personal_pw_of(re.sub(r"[^0-9]", "",
                                                str(m.get("number", ""))))
                    default_pw = f"{re.sub(r'[^0-9]', '', str(m.get('number', '')))}!@@"
                return self._json({
                    "ok": True,
                    "password": pw,
                    "defaultPassword": default_pw,
                    "isDefault": pw == default_pw,
                    "isRegular": is_regular,
                })
            # ---- 회원 접속 로그 조회 (마스터 전용) ----
            if p == "/api/member/access-log":
                if not self._require("master"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                no = re.sub(r"[^0-9]", "", str(q.get("number", [""])[0]))
                if not no:
                    return self._json({"ok": False, "error": "number"}, 400)
                return self._json({"ok": True, "logs": _access_log_for(no)})
            # ---- 전체 회원 접속 로그 (마스터 전용, 대시보드용) ----
            if p == "/api/access/logs":
                if not self._require("master"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                try:
                    limit = int(q.get("limit", ["200"])[0])
                except Exception:
                    limit = 200
                limit = max(1, min(_ACCESS_LOG_MAX, limit))
                logs = _access_log_all().get("logs", [])[:limit]
                return self._json({"ok": True, "logs": logs})
            # ---- 일반회원 승인 대기 목록 (관리자·마스터) ----
            if p == "/api/approval/pending":
                if not self._require("admin"):
                    return
                pending = _pending_members()
                return self._json({"ok": True, "pending": pending,
                                   "count": len(pending)})
            if p == "/api/meta":
                if not self._require():
                    return
                return self._json({"ok": True, "meta": _load_json(META_FILE, {})})
            if p == "/api/config":
                if not self._require():
                    return
                cfg = _load_json(CFG_FILE, _default_config())
                cfg.pop("personalPasswords", None)   # 개인비번은 공개 config에서 제외
                return self._json({"ok": True, "config": cfg})
            # ---- 재무 (F02: 관리자·마스터 전용) ----
            if p == "/api/finance":
                if not self._require("admin"):
                    return
                return self._json({"ok": True, "finance": _load_json(FIN_FILE, _default_finance())})
            if p == "/api/finance/rules":
                if not self._require("admin"):
                    return
                return self._json({"ok": True, "rules": _load_json(MAT_FILE, _default_mat())})
            if p == "/api/finance/history":
                if not self._require("admin"):
                    return
                return self._json({"ok": True, "history": _load_json(HIST_FILE, {"years": {}})})
            if p == "/api/finance/stats":
                if not self._require("admin"):
                    return
                members = _load_json(DB_FILE, [])
                fin = _load_json(FIN_FILE, _default_finance())
                return self._json({"ok": True, "stats": _compute_stats(fin, members)})
            # ---- 기본자료 파일 목록 (관리자·마스터 전용) ----
            if p == "/api/files":
                if not self._require("admin"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                folder = (q.get("folder", [""])[0] or "").strip()
                sub = SUB_FOLDERS.get(folder, folder)
                target = f"{DATA_DIR}/{sub}" if sub else DATA_DIR
                if not NAS.exists(target):
                    return self._json({"ok": True, "folder": sub, "files": []})
                r = NAS.list(target)
                files = []
                if r.get("ok"):
                    for f in r["files"]:
                        if not f["isdir"]:
                            files.append({"name": f["name"], "size": f["size"]})
                files.sort(key=lambda x: x["name"], reverse=True)
                return self._json({"ok": True, "folder": sub, "files": files})
            if p == "/api/files/download":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                folder = SUB_FOLDERS.get(q.get("folder", [""])[0], q.get("folder", [""])[0])
                name = q.get("name", [""])[0]
                fp = f"{DATA_DIR}/{folder}/{name}"
                if not NAS.exists(fp):
                    return self._json({"ok": False, "error": "not found"}, 404)
                ext = os.path.splitext(name)[1].lower()
                ct = MIME.get(ext, "application/octet-stream")
                return self._bytes(NAS.read_bytes(fp), ct)
            # ---- 엑셀 다운로드: 통합 재무 엑셀 ----
            if p == "/api/finance/excel":
                if not self._require("admin"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                kind = q.get("kind", ["finance"])[0]
                b = _build_excel(kind)
                fn = "통합재무관리.xlsx" if kind == "finance" else f"{kind}.xlsx"
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
                self.send_header("Content-Disposition", f"attachment; filename*=UTF-8''{urllib.parse.quote(fn)}")
                self.send_header("Content-Length", str(len(b)))
                self._cors()
                self.end_headers()
                self.wfile.write(b)
                return
            if p == "/api/backups":
                # F04: 백업 목록은 관리자·마스터 전용
                if not self._require("admin"):
                    return
                r = NAS.list(BASE + "/backups")
                files = []
                if r.get("ok"):
                    for f in r["files"]:
                        if not f["isdir"] and f["name"].endswith(".json"):
                            files.append({"name": f["name"], "size": f["size"]})
                files.sort(key=lambda x: x["name"], reverse=True)
                return self._json({"ok": True, "backups": files})
            if p.startswith("/api/photo/"):
                no = re.sub(r"[^0-9]", "", p.split("/")[-1])
                for ext in (".jpg", ".png", ".jpeg"):
                    fp = f"{BASE}/photos/{no}{ext}"
                    if NAS.exists(fp):
                        ct = "image/png" if ext == ".png" else "image/jpeg"
                        return self._bytes(NAS.read_bytes(fp), ct)
                return self._json({"ok": False, "error": "not found"}, 404)
            # ---- 행사관리: 미디어 목록 ----
            if p == "/api/event/list":
                if not self._require():
                    return
                return self._json({"ok": True, "files": _event_list()})
            # ---- 행사 썸네일 백필 진행상황 (관리자·마스터) ----
            if p == "/api/event/thumbs/status":
                if not self._require("admin"):
                    return
                return self._json({"ok": True, "job": _ev_thumb_job_state()})
            # ---- 행사관리: 썸네일 ----
            if p == "/api/event/thumb":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                name = _safe_name(q.get("name", [""])[0])
                fp = _thumb_path(name)
                if not NAS.exists(fp):
                    return self._json({"ok": False, "error": "no thumb"}, 404)
                return self._bytes(NAS.read_bytes(fp), "image/jpeg")
            # ---- 행사관리: 원본(보기/다운로드, Range) ----
            if p == "/api/event/file":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                name = _safe_name(q.get("name", [""])[0])
                dl = q.get("dl", ["0"])[0] == "1"
                fp = f"{EVENT_DIR}/{name}"
                if not NAS.exists(fp):
                    return self._json({"ok": False, "error": "not found"}, 404)
                ct = MIME.get(_ext_of(name), "application/octet-stream")
                return self._serve_nas_file(
                    fp, ct, download_name=name if dl else None)
            # ============ 행사관리 v2 (연도/행사/항목 폴더) ============
            if p == "/api/event/list2":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                want_media = q.get("media", ["1"])[0] == "1"
                try:
                    events = _ev_union_events() if want_media else _ev_list()
                except Exception as e:
                    print("list2 fail", e)
                    events = _ev_list()
                return self._json({"ok": True, "events": events})
            # ---- QR 착지용 공개 행사 정보 (인증 불필요) ----
            if p == "/api/event/qr/info":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                ev = _ev_public_event(year, title)
                if not ev:
                    return self._json({"ok": False, "error": "not found"}, 404)
                return self._json({"ok": True, "event": ev})
            if p == "/api/event/get":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                doc = _ev_doc()
                eid = _ev_id(year, title)
                e = doc.get("events", {}).get(eid)
                if not e:
                    return self._json({"ok": False, "error": "not found"}, 404)
                e = dict(e)
                e["id"] = eid
                return self._json({"ok": True, "event": e})
            if p == "/api/event/files":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                key = q.get("key", [""])[0]
                sub = q.get("sub", [""])[0]
                return self._json({"ok": True, "files": _ev_files(year, title, key, sub)})
            if p == "/api/event/thumb2":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                name = _safe_name(q.get("name", [""])[0])
                sub = q.get("sub", [""])[0]
                size = q.get("size", ["normal"])[0]  # normal | view | orig
                if size == "orig":
                    orig = _ev_find_file(year, title, "media", name, sub)
                    if orig:
                        ct = MIME.get(_ext_of(name), "image/jpeg")
                        if ct.startswith("image/"):
                            return _serve_served_image(self, NAS.read_bytes(orig), name, ct)
                        return self._serve_nas_file(orig, ct)
                if size == "view":
                    # 지연 생성 1600px 최적본 (없으면 생성, 실패 시 썸네일/원본 폴백)
                    vp = _ev_view_path(year, title, name, sub)
                    if not NAS.exists(vp):
                        try:
                            orig = _ev_find_file(year, title, "media", name, sub)
                            if orig and _kind_of(name) == "image":
                                _make_image_view2(NAS.read_bytes(orig), year, title, name, sub)
                        except Exception:
                            pass
                    if NAS.exists(vp):
                        return _serve_served_image(self, NAS.read_bytes(vp), name, "image/jpeg")
                fp = _ev_thumb_path(year, title, name, sub)
                # 로컬 디스크 캐시 우선 → NAS 왕복 없이 즉시 응답 (~0.02s).
                data = _thumb_get(year, title, name, sub)
                if data is not None:
                    return _serve_served_image(self, data, name, "image/jpeg")
                # 그래도 없으면 이미지 원본/동영상 원본으로 최종 폴백
                try:
                    orig = _ev_find_file(year, title, "media", name, sub)
                    if orig:
                        ct = MIME.get(_ext_of(name), "image/jpeg")
                        if ct.startswith("image/"):
                            return _serve_served_image(self, NAS.read_bytes(orig), name, ct)
                        return self._serve_nas_file(orig, ct)
                except Exception:
                    pass
                return self._json({"ok": False, "error": "no thumb"}, 404)
            if p == "/api/event/f2":
                # 항목 폴더 내 파일 서빙 (Range 지원, 원본/다운로드)
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                key = q.get("key", [""])[0]
                name = q.get("name", [""])[0]
                sub = q.get("sub", [""])[0]
                dl = q.get("dl", ["0"])[0] == "1"
                fp = _ev_find_file(year, title, key, name, sub)
                if not fp:
                    return self._json({"ok": False, "error": "not found"}, 404)
                safe = _safe_name(name)
                ct = MIME.get(_ext_of(safe), "application/octet-stream")
                # 이미지 '미리보기'(dl 없음)는 손상 파일이면 플레이스홀더로 대체.
                # 실제 다운로드(dl=1)는 원본 그대로 내보낸다.
                if not dl and ct.startswith("image/"):
                    try:
                        return _serve_served_image(self, NAS.read_bytes(fp), safe, ct)
                    except Exception:
                        pass
                return self._serve_nas_file(fp, ct, download_name=safe if dl else None)
            if p == "/api/event/zip":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                key = q.get("key", [""])[0]
                sub = q.get("sub", [""])[0]
                FilesParam = q.get("files", [""])[0]  # 선택 다운로드: 'a.jpg|b.mp4'
                if FilesParam:
                    # 명시된 파일/폴더만 (선택 다운로드).
                    # 토큰 형식: 'name'(현재 폴더) 또는 'sub/seg:name'(하위폴더 파일)
                    paths = []
                    seen = set()
                    for tok in FilesParam.split("|"):
                        tok = tok.strip()
                        if not tok:
                            continue
                        seg_sub, sep, fname = tok.rpartition(":")
                        if not sep:
                            fname = tok
                            seg_sub = ""
                        fname = _safe_name(fname)
                        tgt_sub = f"{sub}/{seg_sub}" if seg_sub else sub
                        tgt_dir = _ev_sub_dir(year, title, key, tgt_sub)
                        if not tgt_dir:
                            continue
                        sp = f"{tgt_dir}/{fname}"
                        if not NAS.exists(sp):
                            continue
                        info = NAS.get_info(sp)
                        if info.get("isdir"):
                            for it in _ev_collect_under(sp, rel_prefix=fname):
                                if it["path"] not in seen:
                                    seen.add(it["path"])
                                    paths.append(it)
                        else:
                            if sp not in seen:
                                seen.add(sp)
                                rel = f"{seg_sub}/{fname}" if seg_sub else fname
                                paths.append({"path": sp, "rel": rel})
                else:
                    paths = _ev_collect_paths(year, title, key, sub)
                b = _ev_build_zip(paths)
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Disposition",
                                 "attachment; filename*=UTF-8''" + urllib.parse.quote(f"{title}_{key or 'all'}.zip"))
                self.send_header("Content-Length", str(len(b)))
                self._cors()
                self.end_headers()
                self.wfile.write(b)
                return
            if p == "/api/event/roster":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                html = _ev_roster_html(year, title)
                body = html.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self._cors()
                self.end_headers()
                self.wfile.write(body)
                return
            if p == "/api/event/access":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                return self._json({"ok": True, "access": _ev_access_map(_ev_id(year, title))})
            if p == "/api/event/finance":
                if not self._require("admin"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                docs = _ev_doc()
                e = docs.get("events", {}).get(_ev_id(year, title), {})
                return self._json({
                    "ok": True,
                    "fees": e.get("fees", []),
                    "expenses": e.get("expenses", []),
                })
            # --- 정적 파일 서빙 (Flutter 웹앱) ---
            if p == "/":
                p = "/index.html"
            import os as _os
            fp = _os.path.join(STATIC_DIR, p.lstrip("/"))
            # F03: 정적 배포물의 회원 초기자료(seed)는 무인증 제공 금지.
            #  운영 회원자료가 정적 JSON 으로 남아 있으면 즉시 차단(404) 한다.
            _base_l = _os.path.basename(fp).lower()
            if _base_l in ("members_seed.json", "members.json",
                           "members_backup.json") or \
                    _base_l.endswith("_seed.json"):
                self._json({"ok": False, "error": "not found"}, 404)
                return
            if _os.path.isfile(fp):
                # 서버 일시정지: index.html 은 정지 안내 페이지로 대체
                if _server_paused() and p == "/index.html":
                    notice = (
                        "<!doctype html><html lang='ko'><meta charset='utf-8'>"
                        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                        "<title>TSAK 인가자 관리 · 서버 일시정지</title>"
                        "<body style='margin:0;font-family:sans-serif;background:#5B2C8D;"
                        "color:#fff;display:flex;align-items:center;justify-content:center;"
                        "min-height:100vh;text-align:center'>"
                        "<div><div style='font-size:52px'>🛑</div>"
                        "<h2>앱 서버가 일시 정지되었습니다</h2>"
                        "<p style='opacity:.85'>마스터가 서버를 일시 정지했습니다.<br>"
                        "잠시 후 다시 접속해 주세요.</p></div></body></html>"
                    ).encode("utf-8")
                    self.send_response(503)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Content-Length", str(len(notice)))
                    self.send_header("Cache-Control", "no-store")
                    self._cors()
                    self.end_headers()
                    self.wfile.write(notice)
                    return
                with open(fp, "rb") as f:
                    data = f.read()
                ext = _os.path.splitext(fp)[1].lower()
                ct = MIME.get(ext, "application/octet-stream")
                name = _os.path.basename(fp)
                # ---- ETag (내용 해시) → 304 재검증 지원 ----
                etag = '"%s"' % hashlib.md5(data).hexdigest()
                if self.headers.get("If-None-Match") == etag:
                    self.send_response(304)
                    self.send_header("ETag", etag)
                    _reval = name in ("index.html", "flutter_bootstrap.js",
                                      "main.dart.js", "flutter_service_worker.js",
                                      "manifest.json")
                    self.send_header("Cache-Control",
                                     "no-cache" if _reval else "public, max-age=604800")
                    self._cors_static()
                    self.end_headers()
                    return
                # ---- 압축 전송: 캐시된 압축(brotli>gzip) → 없으면 원본 ----
                acc = self.headers.get("Accept-Encoding", "")
                compressed, enc = _get_compressed(fp, data, ext, acc)
                if compressed is None:
                    enc = "identity"
                body = compressed if compressed is not None else data
                # ---- 캐시 정책: 진입점/앱코드는 매번 재검증(즉시 반영), 정적 자산은 장기 ----
                if name in ("index.html", "flutter_bootstrap.js", "main.dart.js",
                            "flutter_service_worker.js", "manifest.json"):
                    cache = "no-cache"                 # 항상 재검증(304) → 업데이트 즉시 반영
                elif "/canvaskit/" in fp or \
                        ext in (".wasm", ".ttf", ".woff", ".woff2", ".otf") or \
                        name.startswith("main.dart.js."):
                    cache = "public, max-age=31536000, immutable"
                elif "/assets/" in fp:
                    cache = "public, max-age=604800"
                else:
                    cache = "public, max-age=86400"
                self.send_response(200)
                self.send_header("Content-Type", ct)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("ETag", etag)
                if enc != "identity":
                    self.send_header("Content-Encoding", enc)
                    self.send_header("Vary", "Accept-Encoding")
                self.send_header("Cache-Control", cache)
                self._cors_static()
                self.end_headers()
                self.wfile.write(body)
                return
            return self._json({"ok": False, "error": "unknown"}, 404)
        except Exception as e:
            return self._json({"ok": False, "error": str(e)}, 500)

    def do_POST(self):
        p = urllib.parse.urlparse(self.path).path
        try:
            if p == "/api/login":
                d = json.loads(self._body() or b"{}")
                tier = d.get("tier", "")
                value = d.get("value", "")
                ident = d.get("id", "")
                _ua = self.headers.get("User-Agent", "")
                _ip = self.client_address[0] if self.client_address else ""
                if tier == "guest":
                    ok, role = _guest_verify(ident, value)
                    no = ""
                    if ok:
                        m = _ev_member_by_ident(ident) or _ev_member_by_ident(ident)
                        no = re.sub(r"[^0-9]", "", str(m.get("number", ""))) if m else ""
                        _log_access_login("guest", "일반회원",
                                          ident or no, ident or no, _ua, _ip)
                    sid = _sess_new("guest", no) if ok else ""
                    if sid:
                        self._set_sid_cookie(sid)
                    return self._json(
                        {"ok": ok, "role": role, "number": no, "sid": sid})
                ok, role = _verify(tier, value)
                # 세션에 기록할 신원: 개인은 인가번호, 그 외는 role
                who = ""
                if ok and tier == "personal":
                    who = re.sub(r"[^0-9]", "", str(ident))
                if ok:
                    _log_access_login(tier, role,
                                      who or re.sub(r"[^0-9]", "", str(ident)),
                                      who, _ua, _ip)
                sid = _sess_new(tier, who) if ok else ""
                if sid:
                    self._set_sid_cookie(sid)
                return self._json(
                    {"ok": ok, "role": role, "silent": (tier == "master"),
                     "sid": sid})
            # ---- 세션 종료 ----
            if p == "/api/logout":
                _sess_del(self._sid())
                self._pending_sid = ""
                return self._json({"ok": True})
            # ---- QR/세션복원용 세션 발급 ----
            #  개인 QR(?access=personal&no=..)로 열린 경우처럼 비번 입력 없이
            #  세션을 발급해야 하는 경로. 안전을 위해 다음을 강제한다:
            #   · master 등급은 마스터 비번 확인값 없이는 발급 불가(권한 상승 차단)
            #   · 개인(personal): 인가번호 유효성 확인
            #   · 비인가자(guest): 전화번호 형식만 확인(본인 1건만 조회됨)
            if p == "/api/session/grant":
                d = json.loads(self._body() or b"{}")
                tier = str(d.get("tier", "")).strip()
                ident = re.sub(r"[^0-9]", "", str(d.get("id", "")))
                if tier == "master":
                    if not _is_master_val(d.get("master")):
                        return self._json(
                            {"ok": False, "error": "master required"}, 401)
                    sid = _sess_new("master", ident)
                elif tier == "app":
                    if not _is_master_val(d.get("master")) and \
                            str(d.get("app")) != APP_PW:
                        return self._json(
                            {"ok": False, "error": "app required"}, 401)
                    sid = _sess_new("app", ident)
                elif tier == "personal":
                    if not ident:
                        return self._json({"ok": False, "error": "id"}, 400)
                    try:
                        _mems = _load_json(DB_FILE, [])
                    except Exception:
                        _mems = []
                    _ok = any(
                        re.sub(r"[^0-9]", "", str(m.get("number", ""))) == ident
                        for m in _mems
                    )
                    if not _ok:
                        m = _ev_member_by_ident(ident)
                        _ok = bool(m)
                    if not _ok:
                        return self._json({"ok": False, "error": "unknown"}, 404)
                    sid = _sess_new("personal", ident)
                elif tier == "guest":
                    if len(ident) < 4:
                        return self._json({"ok": False, "error": "id"}, 400)
                    sid = _sess_new("guest", ident)
                else:
                    return self._json({"ok": False, "error": "tier"}, 400)
                self._set_sid_cookie(sid)
                return self._json({"ok": True, "sid": sid, "tier": tier})
            # ============ 전역 인증 게이트 (F01/F02) ============
            #  로그인/로그아웃을 제외한 모든 변경(쓰기) 요청은 유효한 세션 필요.
            #  관리자 전용 경로는 추가로 tier 검사.
            if p.startswith("/api/"):
                # QR 행사참여(스캔) 경로는 공개 — QR 자체가 접근 매개.
                if p.startswith("/api/event/qr/"):
                    pass
                else:
                    need = None
                    if (p.startswith("/api/admin/") or p.startswith("/api/backup")
                            or p.startswith("/api/restore")
                            or p.startswith("/api/finance")
                            or p.startswith("/api/files")):
                        need = "admin"
                    if not self._require(need):
                        return
            # ---- 마스터 앱관리 ----
            if p == "/api/admin/app-password":
                d = json.loads(self._body() or b"{}")
                if not _is_master_val(d.get("master")):
                    return self._json({"ok": False, "error": "master"}, 401)
                newp = str(d.get("new", "")).strip()
                if len(newp) < 4:
                    return self._json({"ok": False, "error": "too short"}, 400)
                with LOCK:
                    cfg = _load_json(CFG_FILE, _default_config())
                    cfg["appPassword"] = newp
                    _save_json(CFG_FILE, cfg)
                return self._json({"ok": True})
            if p == "/api/admin/personal":
                d = json.loads(self._body() or b"{}")
                if not _is_master_val(d.get("master")):
                    return self._json({"ok": False, "error": "master"}, 401)
                no = re.sub(r"[^0-9]", "", str(d.get("number", "")))
                if not no:
                    return self._json({"ok": False, "error": "number"}, 400)
                with LOCK:
                    cfg = _load_json(CFG_FILE, _default_config())
                    pws = cfg.setdefault("personalPasswords", {})
                    if d.get("reset"):          # 초기화 → 기본 {no}!@@
                        pws.pop(no, None)
                    else:                       # 지정 변경
                        val = str(d.get("value", "")).strip()
                        if not val:
                            return self._json({"ok": False, "error": "value"}, 400)
                        pws[no] = val
                    _save_json(CFG_FILE, cfg)
                return self._json({"ok": True, "personalPassword": _personal_pw_of(no)})
            # ---- 접속 로그 삭제 (마스터 전용) ----
            #  mode: 'one'(ts 1건) | 'member'(해당 회원 전체) | 'all'(전체)
            if p == "/api/member/access-log/delete":
                d = json.loads(self._body() or b"{}")
                mode = str(d.get("mode", "one"))
                with _ACCESS_LOG_LOCK:
                    doc = _load_json(ACCESS_LOG_FILE, {"logs": []})
                    logs = doc.get("logs", [])
                    if mode == "all":
                        logs = []
                    elif mode == "member":
                        no = re.sub(r"[^0-9]", "", str(d.get("number", "")))
                        logs = [x for x in logs if str(x.get("ident", "")) != no]
                    else:
                        ts = str(d.get("ts", ""))
                        ident = re.sub(r"[^0-9]", "", str(d.get("number", "")))
                        logs = [
                            x for x in logs
                            if not (str(x.get("ts", "")) == ts
                                    and (not ident
                                         or str(x.get("ident", "")) == ident))
                        ]
                    doc["logs"] = logs
                    doc["updated"] = datetime.datetime.now().strftime(
                        "%Y-%m-%d %H:%M:%S")
                    _save_json(ACCESS_LOG_FILE, doc)
                return self._json({"ok": True, "count": len(logs)})
            # ---- 일반회원 승인 처리 (관리자·마스터) ----
            #  action: 'approve' | 'hold' | 'pending' | 'delete' | 'bulk'
            if p == "/api/approval/set":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                action = str(d.get("action", "approve"))
                idents = d.get("idents")
                if not isinstance(idents, list):
                    idents = [d.get("ident", "")]
                idents = [str(x) for x in idents if str(x).strip()]
                if not idents:
                    return self._json({"ok": False, "error": "ident"}, 400)
                done = 0
                if action == "delete":
                    with _MEMBER_WRITE_LOCK:
                        members = _ev_members()
                        keys = {re.sub(r"[^0-9]", "", x) for x in idents}
                        keep = []
                        for m in members:
                            mk = re.sub(r"[^0-9]", "", str(m.get("number", "")))
                            lk = re.sub(r"[^0-9]", "", str(
                                m.get("accessPhone") or m.get("phone") or ""))
                            if mk in keys or lk in keys or str(m.get("id", "")) in idents:
                                done += 1
                                continue
                            keep.append(m)
                        _save_json(DB_FILE, keep)
                        _touch_meta({"count": len(keep), "updatedBy": "approval-del"})
                else:
                    status = {
                        "approve": "approved", "hold": "held",
                        "pending": "pending", "bulk": "approved",
                    }.get(action, "approved")
                    for x in idents:
                        ok, _ = _set_member_approval(x, status)
                        if ok:
                            done += 1
                return self._json({"ok": True, "done": done})
            # ---- 개인 셀프 비밀번호 변경 (본인) ----
            if p == "/api/personal/password":
                d = json.loads(self._body() or b"{}")
                no = re.sub(r"[^0-9]", "", str(d.get("number", "")))
                cur = str(d.get("current", ""))
                new = str(d.get("new", "")).strip()
                if not no or not new:
                    return self._json({"ok": False, "error": "입력 오류"}, 400)
                if len(new) < 4:
                    return self._json({"ok": False, "error": "새 비밀번호가 너무 짧습니다(4자 이상)"}, 400)
                # 현재 비번 검증 (설정된 값 또는 기본 {no}!@@ 또는 마스터)
                if not (cur == _personal_pw_of(no) or cur == MASTER_PW):
                    return self._json({"ok": False, "error": "현재 비밀번호가 올바르지 않습니다"}, 401)
                with LOCK:
                    cfg = _load_json(CFG_FILE, _default_config())
                    pws = cfg.setdefault("personalPasswords", {})
                    pws[no] = new
                    _save_json(CFG_FILE, cfg)
                return self._json({"ok": True})
            if p == "/api/admin/server-pause":
                d = json.loads(self._body() or b"{}")
                if not _is_master_val(d.get("master")):
                    return self._json({"ok": False, "error": "master"}, 401)
                with LOCK:
                    cfg = _load_json(CFG_FILE, _default_config())
                    cfg["serverPaused"] = bool(d.get("paused", False))
                    _save_json(CFG_FILE, cfg)
                return self._json({"ok": True, "serverPaused": bool(d.get("paused", False))})
            if p == "/api/member":
                # 단일 인가자 부분 갱신 (개인 접근의 안전한 저장 — 전체 DB 덮어쓰기 방지)
                d = json.loads(self._body() or b"{}")
                mem = d.get("member")
                if not isinstance(mem, dict):
                    return self._json({"ok": False, "error": "member"}, 400)
                mid = str(mem.get("id", ""))
                with LOCK:
                    members = _load_json(DB_FILE, [])
                    found = False
                    for i, m in enumerate(members):
                        if str(m.get("id", "")) == mid:
                            members[i] = mem
                            found = True
                            break
                    if not found:
                        members.append(mem)
                    if NAS.exists(DB_FILE):
                        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                        NAS.write(f"{BASE}/backups/members_{stamp}.json",
                                  NAS.read(DB_FILE).encode("utf-8"))
                    _save_json(DB_FILE, members)
                    meta = _touch_meta({"count": len(members), "updatedBy": d.get("by", "app")})
                return self._json({"ok": True, "meta": meta})
            if p == "/api/members":
                d = json.loads(self._body() or b"{}")
                members = d.get("members", [])
                with LOCK:
                    # backup before overwrite
                    if NAS.exists(DB_FILE):
                        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                        old = NAS.read(DB_FILE)
                        NAS.write(f"{BASE}/backups/members_{stamp}.json", old.encode("utf-8"))
                    _save_json(DB_FILE, members)
                    meta = _touch_meta({"count": len(members), "updatedBy": d.get("by", "app")})
                return self._json({"ok": True, "meta": meta})
            if p == "/api/backup":
                d = json.loads(self._body() or b"{}")
                name = d.get("name") or datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                if not name.endswith(".json"):
                    name += ".json"
                cur = NAS.read(DB_FILE)
                NAS.write(f"{BASE}/backups/{name}", cur.encode("utf-8"))
                return self._json({"ok": True, "name": name})
            if p == "/api/restore":
                d = json.loads(self._body() or b"{}")
                name = d.get("name", "")
                src = f"{BASE}/backups/{name}"
                if not NAS.exists(src):
                    return self._json({"ok": False, "error": "no backup"}, 404)
                cur = NAS.read(src)
                with LOCK:
                    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                    if NAS.exists(DB_FILE):
                        NAS.write(f"{BASE}/backups/BEFORE_RESTORE_{stamp}.json",
                                  NAS.read(DB_FILE).encode("utf-8"))
                    NAS.write(DB_FILE, cur.encode("utf-8"))
                    meta = _touch_meta({"restored": name})
                return self._json({"ok": True, "members": json.loads(cur), "meta": meta})
            if p == "/api/config":
                d = json.loads(self._body() or b"{}")
                need = d.pop("_pw", None)
                if d.get("requirePw") and need != APP_PW:
                    return self._json({"ok": False, "error": "auth"}, 401)
                cfg = _load_json(CFG_FILE, _default_config())
                cfg.update({k: v for k, v in d.items() if not k.startswith("_")})
                _save_json(CFG_FILE, cfg)
                return self._json({"ok": True, "config": cfg})
            if p.startswith("/api/photo/"):
                no = re.sub(r"[^0-9]", "", p.split("/")[-1])
                raw = self._body()
                ext = ".jpg"
                ctyp = self.headers.get("Content-Type", "")
                if "png" in ctyp:
                    ext = ".png"
                NAS.write(f"{BASE}/photos/{no}{ext}", raw)
                return self._json({"ok": True})
            # ---- 재무 저장(전체 교체, 서버 자동 스냅샷) ----
            if p == "/api/finance":
                d = json.loads(self._body() or b"{}")
                fin = _load_json(FIN_FILE, _default_finance())
                with LOCK:
                    if "transactions" in d:
                        fin["transactions"] = d["transactions"]
                    for k in ("income_categories", "expense_categories"):
                        if k in d:
                            fin[k] = d[k]
                    fin["version"] = int(fin.get("version", 0)) + 1
                    fin["updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    _save_json(FIN_FILE, fin)
                    _rebuild_history(fin)
                return self._json({"ok": True, "finance": fin})
            if p == "/api/finance/rules":
                d = json.loads(self._body() or b"{}")
                rules = _load_json(MAT_FILE, _default_mat())
                rules.update({k: v for k, v in d.items() if k in ("aliases", "events")})
                rules["updated"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                _save_json(MAT_FILE, rules)
                return self._json({"ok": True, "rules": rules})
            # ---- 행사관리: 미디어 삭제 (구 갤러리 전용 경로 분리) ----
            if p == "/api/event/media/delete":
                d = json.loads(self._body() or b"{}")
                name = _safe_name(d.get("name", ""))
                if not name:
                    return self._json({"ok": False, "error": "name"}, 400)
                try:
                    NAS.delete(f"{EVENT_DIR}/{name}")
                    try:
                        NAS.delete(_thumb_path(name))
                    except Exception:
                        pass
                    meta = _event_media_meta()
                    meta.get("files", {}).pop(name, None)
                    _save_event_media_meta(meta)
                    return self._json({"ok": True})
                except Exception as e:
                    return self._json({"ok": False, "error": str(e)}, 500)
            # ---- 은행거래파일 자동분류(파싱만, 저장 안 함) ----
            if p == "/api/finance/parse-bank":
                d = json.loads(self._body() or b"{}")
                import base64 as _b64
                raw = _b64.b64decode(d.get("data", ""))
                fname = d.get("filename", "")
                members = _load_json(DB_FILE, [])
                rules = _load_json(MAT_FILE, _default_mat())
                low = fname.lower()
                # 이미지/PDF는 OCR 경로로
                if low.endswith((".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".pdf")):
                    try:
                        out, text = _ocr_bank(raw, fname, members, rules)
                        return self._json({"ok": True, "rows": out,
                                           "count": len(out), "engine": "ocr"})
                    except Exception as e:
                        return self._json({"ok": False, "error": f"OCR 실패: {e}"}, 500)
                sheets = _read_excel_sheets(raw, fname)
                acct = _account_kind(fname)
                out = []
                sheet_names = []
                for sname, srows in sheets:
                    if not srows:
                        continue
                    objs = _rows_to_objects(srows)
                    if not objs:
                        continue
                    sheet_names.append(sname)
                    for o in objs:
                        c = _classify(o, members, rules, account_kind=acct)
                        c["sheet"] = sname
                        c["account"] = acct["income"] if acct else ""
                        out.append(c)
                return self._json({"ok": True, "rows": out, "count": len(out),
                                   "engine": "excel", "sheets": sheet_names})
            # ---- 종합 통계(연도/월/행사/분류/지출/기간) ----
            if p == "/api/finance/stats":
                members = _load_json(DB_FILE, [])
                fin = _load_json(FIN_FILE, _default_finance())
                return self._json({"ok": True, "stats": _compute_stats(fin, members)})
            # ---- 기본자료 파일 업로드(base64) + 자동분석 ----
            if p == "/api/files":
                d = json.loads(self._body() or b"{}")
                folder = SUB_FOLDERS.get(d.get("folder", ""), d.get("folder", "")) or "기타"
                name = d.get("name", "file")
                content = base64.b64decode(d.get("data", ""))
                target_dir = f"{DATA_DIR}/{folder}"
                if not NAS.exists(target_dir):
                    NAS.mkdir(DATA_DIR, folder)
                NAS.write(f"{target_dir}/{name}", content)
                analysis = _analyze_file(folder, name, content)
                _log_import(folder, name, analysis.get("summary", ""))
                return self._json({"ok": True, "folder": folder, "analysis": analysis})
            # ---- 행사관리: 미디어 업로드 (스트리밍, 무제한) ----
            if p == "/api/event/upload":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                name = _safe_name(q.get("name", [""])[0])
                if not name:
                    return self._json({"ok": False, "error": "name"}, 400)
                total = int(self.headers.get("Content-Length", 0) or 0)
                if not NAS.exists(EVENT_DIR):
                    NAS.mkdir(BASE, "행사관리")
                if not NAS.exists(EVENT_THUMB_DIR):
                    NAS.mkdir(EVENT_DIR, ".thumbnails")

                def _chunks():
                    remaining = total
                    while remaining > 0:
                        buf = self.rfile.read(min(262144, remaining))
                        if not buf:
                            break
                        remaining -= len(buf)
                        yield buf

                ctyp = self.headers.get("Content-Type", "application/octet-stream")
                # 썸네일 생성을 위해 원본을 로컬 임시 파일로도 저장
                import tempfile
                tmp = tempfile.NamedTemporaryFile(
                    suffix=_ext_of(name) or ".bin", delete=False)
                tmp_path = tmp.name
                written = 0
                # 로컬 임시 저장(원본) 후 NAS 스트리밍 업로드
                for c in _chunks():
                    tmp.write(c)
                    written += len(c)
                tmp.close()
                size = written
                kind = _kind_of(name)
                with open(tmp_path, "rb") as f:
                    def _file_chunks():
                        while True:
                            b = f.read(262144)
                            if not b:
                                break
                            yield b
                    NAS.write_stream(f"{EVENT_DIR}/{name}", _file_chunks(),
                                     size=size, content_type=ctyp)

                # 썸네일 생성
                meta = _event_media_meta()
                files = meta.setdefault("files", {})
                rec = files.get(name, {})
                rec["uploaded"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                if kind == "image":
                    with open(tmp_path, "rb") as f:
                        src = f.read()
                    if _make_image_thumb(src, name):
                        rec["thumb"] = True
                elif kind == "video":
                    if _make_video_thumb(tmp_path, name):
                        rec["vthumb"] = True
                    rec.update(_probe_video(tmp_path))
                files[name] = rec
                _save_event_media_meta(meta)
                try:
                    os.unlink(tmp_path)
                except Exception:
                    pass
                return self._json({
                    "ok": True, "name": name, "size": size, "kind": kind,
                    "thumb": bool(rec.get("thumb") or rec.get("vthumb")),
                })
            # ============ 행사관리 v2 (POST) ============
            if p == "/api/admin/set-password":
                d = json.loads(self._body() or b"{}")
                tier = str(d.get("tier", "app"))
                if tier == "master" and str(d.get("master", "")) != MASTER_PW and d.get("master") is not None:
                    pass
                ok, err, new_pw = _set_password(
                    tier, d.get("id", ""), d.get("value", ""), bool(d.get("reset")))
                if ok:
                    return self._json({"ok": True, "newPassword": new_pw})
                return self._json({"ok": False, "error": err}, 400)
            # ---- 행사 썸네일 일괄 백필 시작 (관리자·마스터) ----
            if p == "/api/event/thumbs/backfill":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                force = bool(d.get("force"))
                try:
                    k = int(d.get("maxSide", 480) or 480)
                except Exception:
                    k = 480
                k = max(64, min(1600, k))
                started = _ev_start_thumb_backfill(max_side=k, force=force)
                return self._json({
                    "ok": True,
                    "started": started,
                    "job": _ev_thumb_job_state(),
                })
            if p == "/api/event/create":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                if not title:
                    return self._json({"ok": False, "error": "title"}, 400)
                # 연도는 필수 — 미지정/비정상 값은 거부 (요청: 모든 행사는 연도 필수)
                if not year or not re.match(r"^\d{4}$", year):
                    return self._json(
                        {"ok": False, "error": "year required",
                         "message": "행사 생성 시 연도(4자리)는 필수입니다."}, 400)
                with LOCK:
                    doc = _ev_doc()
                    eid = _ev_id(year, title)
                    e = doc.setdefault("events", {}).setdefault(eid, {})
                    e.update({
                        "year": year,
                        "title": title,
                        "period": str(d.get("period", "")),
                        "place": str(d.get("place", "")),
                        "desc": str(d.get("desc", "")),
                        "created": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                        "createdBy": str(d.get("by", "")),
                    })
                    e.setdefault("attendees", [])
                    e.setdefault("fees", [])
                    e.setdefault("expenses", [])
                    e.setdefault("requested", [])   # 사진 업로드 요청 대상
                    e.setdefault("accessLog", [])
                    e.setdefault("uploaders", {})
                    e.setdefault("fileTimes", {})
                    _ev_save(doc)
                _ensure_event_dirs(year, title)
                return self._json({"ok": True, "id": eid, "event": e})
            if p == "/api/event/rename":
                d = json.loads(self._body() or b"{}")
                old_year = _ev_safe(d.get("year", ""))
                old_title = _ev_safe(d.get("title", ""))
                new_title = _ev_safe(d.get("newTitle", "")) or old_title
                new_year = _ev_safe(d.get("newYear", "")) or old_year
                if not old_title:
                    return self._json({"ok": False, "error": "title"}, 400)
                with LOCK:
                    doc = _ev_doc()
                    events = doc.get("events", {})
                    old_id = _ev_id(old_year, old_title)
                    e = events.get(old_id)
                    if not e:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    # 폴더 이동 (연도 변경/이름 변경)
                    old_dir = _ev_dir(old_year, old_title)
                    new_dir = _ev_dir(new_year, new_title)
                    try:
                        if NAS.exists(old_dir) and old_dir != new_dir:
                            if not NAS.exists(f"{EVENT_DIR}/{new_year}"):
                                NAS.mkdir(EVENT_DIR, new_year)
                            NAS.move(old_dir, f"{EVENT_DIR}/{new_year}")
                            # move 는 dest_folder_path 하위로 들어가므로, 이름만 바뀐 경우 rename 보정
                            moved = f"{EVENT_DIR}/{new_year}/{old_title}"
                            if NAS.exists(moved) and new_title != old_title:
                                NAS.rename(moved, new_title)
                    except Exception as ex:
                        print("rename move fail", ex)
                    # 썸네일 폴더도 이동
                    try:
                        ot = _ev_thumb_dir(old_year, old_title)
                        nt = _ev_thumb_dir(new_year, new_title)
                        if NAS.exists(ot) and ot != nt:
                            if not NAS.exists(f"{EVENT_DIR}/.thumbnails/{new_year}"):
                                NAS.mkdir(f"{EVENT_DIR}/.thumbnails", new_year)
                            NAS.move(ot, f"{EVENT_DIR}/.thumbnails/{new_year}")
                            moved = f"{EVENT_DIR}/.thumbnails/{new_year}/{old_title}"
                            if NAS.exists(moved) and new_title != old_title:
                                NAS.rename(moved, new_title)
                    except Exception as ex:
                        print("rename thumb move fail", ex)
                    e["year"] = new_year
                    e["title"] = new_title
                    new_id = _ev_id(new_year, new_title)
                    events.pop(old_id, None)
                    events[new_id] = e
                    _ev_save(doc)
                return self._json({"ok": True, "id": new_id})
            if p == "/api/event/delete":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                with LOCK:
                    doc = _ev_doc()
                    doc.get("events", {}).pop(_ev_id(year, title), None)
                    _ev_save(doc)
                    try:
                        NAS.delete(_ev_dir(year, title))
                    except Exception:
                        pass
                    try:
                        NAS.delete(_ev_thumb_dir(year, title))
                    except Exception:
                        pass
                # 개인 프로필(eventAttend)에서도 행사명 제거
                try:
                    _ev_remove_member_events([title])
                except Exception as e:
                    print("member event remove fail", e)
                return self._json({"ok": True})
            if p == "/api/event/name/delete":
                # 행사명만 제거 — events.json(있으면) + 모든 개인 프로필(eventAttend)
                d = json.loads(self._body() or b"{}")
                names = d.get("names")
                if names is None:
                    names = [d.get("title", "")]
                names = [_ev_safe(n) for n in names if str(n).strip()]
                removed = 0
                with LOCK:
                    doc = _ev_doc()
                    events = doc.get("events", {})
                    for name in names:
                        for eid in [k for k, e in events.items()
                                    if str(e.get("title", "")) == name]:
                            events.pop(eid, None)
                            removed += 1
                    _ev_save(doc)
                try:
                    _ev_remove_member_events(names)
                except Exception as e:
                    print("member event name remove fail", e)
                return self._json({"ok": True, "removed": removed, "names": names})
            if p == "/api/event/attendee/set":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                eid = _ev_id(year, title)
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(eid)
                    if not e:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    e["attendees"] = d.get("attendees", [])
                    _ev_save(doc)
                # 회원 프로필(eventAttend) 연동 — 1회 로드/저장으로 일괄 처리
                idents = []
                for a in d.get("attendees", []):
                    ident = a.get("number") or a.get("loginId") or a.get("phone")
                    if ident:
                        idents.append(re.sub(r"[^0-9]", "", str(ident)))
                if idents:
                    try:
                        _ev_member_set_event_batch(idents, title, True)
                    except Exception:
                        pass
                return self._json({"ok": True})
            if p == "/api/event/search-member":
                d = json.loads(self._body() or b"{}")
                q = re.sub(r"[^0-9가-힣A-Za-z]", "", str(d.get("q", ""))).lower()
                try:
                    limit = int(d.get("limit", 30))
                except Exception:
                    limit = 30
                limit = max(1, min(200, limit))
                results = []
                for m in _ev_members():
                    hay = f"{m.get('number','')} {m.get('name','')} {m.get('unit','')}".lower()
                    if (not q) or (q in hay):   # 빈 검색어 = 최근/전체 목록
                        results.append({
                            "number": m.get("number", ""),
                            "name": m.get("name", ""),
                            "unit": m.get("unit", ""),
                            "league": m.get("league", ""),
                            "phone": m.get("phone", ""),
                            "isRegular": bool(m.get("isRegular")),
                        })
                    if len(results) >= limit:
                        break
                return self._json({"ok": True, "results": results,
                                   "count": len(results)})
            # ---- 참가자 일괄 추가 (다중 선택) ----
            if p == "/api/event/attendees/add":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                entries = d.get("attendees", []) or []
                eid = _ev_id(year, title)
                added_ok = 0
                added_skip = 0
                added_idents = []
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(eid)
                    if not e:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    for a in entries:
                        ident = _ev_attendee_ident(a)
                        if not ident or _ev_is_attendee(e, ident):
                            added_skip += 1
                            continue
                        e.setdefault("attendees", []).append({
                            "number": str(a.get("number", "")),
                            "loginId": str(a.get("loginId", "")),
                            "name": str(a.get("name", "")),
                            "unit": str(a.get("unit", "")),
                            "league": str(a.get("league", "")),
                            "phone": str(a.get("phone", "")),
                            "roles": a.get("roles", []),
                        })
                        added_ok += 1
                        added_idents.append(ident)
                    if added_ok:
                        _ev_save(doc)
                # 회원 프로필(eventAttend) 연동 — 1회 로드/저장으로 일괄 처리
                if added_idents:
                    try:
                        _ev_member_set_event_batch(added_idents, title, True)
                    except Exception:
                        pass
                return self._json({"ok": True, "added": added_ok,
                                   "skipped": added_skip})
            # ---- QR 행사 참여 (스캔 → 자동 등록), 인증 불필요 ----
            if p == "/api/event/qr/join":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                if not year or not title:
                    return self._json({"ok": False, "error": "event",
                                       "message": "행사 정보가 없습니다."}, 400)
                kind = str(d.get("kind", "")).strip()
                if kind == "credentialed":
                    res, code = _ev_qr_join_credentialed(
                        year, title, d.get("number", ""))
                elif kind == "guest":
                    res, code = _ev_qr_join_guest(
                        year, title, d.get("name", ""), d.get("phone", ""))
                else:
                    res, code = ({"ok": False, "error": "kind",
                                  "message": "참여 유형이 올바르지 않습니다."}, 400)
                return self._json(res, code)
            # ---- QR 착지 페이지 (스캔 시 표시) ----
            if p == "/api/event/upload2":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = _ev_safe(q.get("year", [""])[0])
                title = _ev_safe(q.get("title", [""])[0])
                key = q.get("key", [""])[0]
                up_name = _safe_name(q.get("name", [""])[0])
                uploader = str(q.get("uploader", [""])[0])
                sub = _ev_sub_safe(q.get("sub", [""])[0])
                if not EVENT_SUB_BY_KEY.get(key) or not up_name:
                    return self._json({"ok": False, "error": "bad request"}, 400)
                total = int(self.headers.get("Content-Length", 0) or 0)
                base = _ev_dir(year, title)
                if not NAS.exists(base):
                    _ensure_event_dirs(year, title)
                fp_dir = _ev_sub_dir(year, title, key, sub)
                if not NAS.exists(fp_dir):
                    _ev_mkdir_deep(fp_dir)
                import tempfile
                tmp = tempfile.NamedTemporaryFile(suffix=_ext_of(up_name) or ".bin", delete=False)
                tmp_path = tmp.name
                written = 0
                remaining = total
                while remaining > 0:
                    buf = self.rfile.read(min(262144, remaining))
                    if not buf:
                        break
                    tmp.write(buf)
                    written += len(buf)
                    remaining -= len(buf)
                tmp.close()
                ctyp = self.headers.get("Content-Type", "application/octet-stream")
                with open(tmp_path, "rb") as f:
                    def _file_chunks():
                        while True:
                            b = f.read(262144)
                            if not b:
                                break
                            yield b
                    NAS.write_stream(f"{fp_dir}/{up_name}", _file_chunks(),
                                     size=written, content_type=ctyp)
                kind = _kind_of(up_name)
                if key == "media":
                    if kind == "image":
                        with open(tmp_path, "rb") as f:
                            _make_image_thumb2(f.read(), year, title, up_name, sub)
                    elif kind == "video":
                        _make_video_thumb2(tmp_path, year, title, up_name, sub)
                # 메타: 업로더 이름 + 시각 (키: 'sub/name')
                ukey = f"{sub}/{up_name}" if sub else up_name
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(_ev_id(year, title))
                    if e is not None:
                        e.setdefault("uploaders", {}).setdefault(key, {})[ukey] = uploader
                        e.setdefault("fileTimes", {}).setdefault(key, {})[ukey] = \
                            datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
                        if key == "media" and uploader:
                            e.setdefault("participantsUploaded", {})[ukey] = uploader
                        _ev_save(doc)
                try:
                    os.unlink(tmp_path)
                except Exception:
                    pass
                return self._json({"ok": True, "name": up_name, "size": written, "kind": kind})
            if p == "/api/event/mkdir":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                key = d.get("key", "")
                sub = d.get("sub", "")
                nm = _ev_safe(d.get("name", ""))
                parent = _ev_sub_dir(year, title, key, sub)
                if not parent or not nm:
                    return self._json({"ok": False, "error": "bad request"}, 400)
                if not NAS.exists(parent):
                    _ev_mkdir_deep(parent)
                try:
                    NAS.mkdir(parent, nm)
                except Exception as e:
                    return self._json({"ok": False, "error": str(e)}, 500)
                return self._json({"ok": True, "name": nm})
            if p == "/api/event/file/delete":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                key = d.get("key", "")
                name = _safe_name(d.get("name", ""))
                sub = d.get("sub", "")
                is_dir = bool(d.get("isdir", False))
                if is_dir:
                    fp = _ev_sub_dir(year, title, key, f"{sub}/{name}" if sub else name)
                else:
                    fp = _ev_find_file(year, title, key, name, sub)
                if not fp or not NAS.exists(fp):
                    return self._json({"ok": False, "error": "not found"}, 404)
                try:
                    NAS.delete(fp)
                except Exception as e:
                    return self._json({"ok": False, "error": str(e)}, 500)
                if key == "media" and not is_dir:
                    try:
                        NAS.delete(_ev_thumb_path(year, title, name, sub))
                    except Exception:
                        pass
                ukey = f"{_ev_sub_safe(sub)}/{name}" if _ev_sub_safe(sub) else name
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(_ev_id(year, title))
                    if e is not None:
                        e.get("uploaders", {}).get(key, {}).pop(ukey, None)
                        e.get("fileTimes", {}).get(key, {}).pop(ukey, None)
                        e.get("participantsUploaded", {}).pop(ukey, None)
                        _ev_save(doc)
                return self._json({"ok": True})
            if p == "/api/event/file/rename":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                key = d.get("key", "")
                name = _safe_name(d.get("name", ""))
                new_name = _safe_name(d.get("newName", ""))
                sub = d.get("sub", "")
                if not EVENT_SUB_BY_KEY.get(key) or not new_name:
                    return self._json({"ok": False, "error": "bad"}, 400)
                src_dir = _ev_sub_dir(year, title, key, sub)
                src = f"{src_dir}/{name}"
                if not NAS.exists(src):
                    return self._json({"ok": False, "error": "not found"}, 404)
                # 이름변경 (동일 위치, FileStation.Rename)
                try:
                    NAS.rename(src, new_name)
                except Exception as ex:
                    return self._json({"ok": False, "error": str(ex)}, 500)
                sub_clean = _ev_sub_safe(sub)
                old_key = f"{sub_clean}/{name}" if sub_clean else name
                new_key = f"{sub_clean}/{new_name}" if sub_clean else new_name
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(_ev_id(year, title))
                    if e is not None:
                        up = e.get("uploaders", {}).get(key, {})
                        if old_key in up:
                            up[new_key] = up.pop(old_key)
                        ft = e.get("fileTimes", {}).get(key, {})
                        if old_key in ft:
                            ft[new_key] = ft.pop(old_key)
                        _ev_save(doc)
                return self._json({"ok": True, "newName": new_name})
            if p == "/api/event/finance/add":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                kind = d.get("kind", "fee")  # fee | expense
                row = d.get("row", {})
                eid = _ev_id(year, title)
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(eid)
                    if not e:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    tgt = e.setdefault("fees" if kind == "fee" else "expenses", [])
                    row["id"] = row.get("id") or f"t{int(time.time()*1000)}"
                    row["created"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
                    tgt.append(row)
                    _ev_save(doc)
                tx = {
                    "id": f"ev_{row['id']}",
                    "date": str(row.get("date", "")),
                    "type": "expense" if kind == "expense" else "income",
                    "payer": str(row.get("name", "")),
                    "name": str(row.get("name", "")),
                    "number": str(row.get("number", "")),
                    "memberId": "",
                    "amount": int(row.get("amount", 0) or 0),
                    "category": "행사비" if kind == "expense" else ("참가비" if row.get("category", "참가비") == "참가비" else str(row.get("category", "후원"))),
                    "event": title,
                    "context": f"{year} {title}",
                    "memo": str(row.get("memo", "")),
                    "status": "matched" if row.get("number") else "unmatched",
                    "year": year,
                    "source": "event",
                }
                try:
                    _ev_fin_add(tx)
                except Exception as ex:
                    print("fin add fail", ex)
                return self._json({"ok": True, "row": row})
            if p == "/api/event/finance/delete":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                kind = d.get("kind", "fee")
                rid = str(d.get("id", ""))
                eid = _ev_id(year, title)
                target = None
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(eid)
                    if e:
                        arr = e.get("fees" if kind == "fee" else "expenses", [])
                        for i, r in enumerate(arr):
                            if str(r.get("id", "")) == rid:
                                target = r
                                arr.pop(i)
                                break
                        _ev_save(doc)
                if target:
                    try:
                        _ev_fin_remove({
                            "date": str(target.get("date", "")),
                            "payer": str(target.get("name", "")),
                            "amount": int(target.get("amount", 0) or 0),
                            "category": "행사비" if kind == "expense" else ("참가비" if target.get("category", "참가비") == "참가비" else str(target.get("category", "후원"))),
                            "event": title,
                        })
                    except Exception:
                        pass
                return self._json({"ok": True})
            if p == "/api/event/finance/update":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                kind = d.get("kind", "fee")
                rid = str(d.get("id", ""))
                row = d.get("row", {})
                row["id"] = rid
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(_ev_id(year, title))
                    if not e:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    arr = e.get("fees" if kind == "fee" else "expenses", [])
                    for i, r in enumerate(arr):
                        if str(r.get("id", "")) == rid:
                            arr[i] = row
                            break
                    _ev_save(doc)
                return self._json({"ok": True})
            if p == "/api/event/access/log":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                entry = {
                    "id": str(d.get("id", "")),
                    "name": str(d.get("name", "")),
                    "role": str(d.get("role", "")),
                    "at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                }
                _ev_log_access(_ev_id(year, title), entry)
                return self._json({"ok": True})
            if p == "/api/event/request-photo":
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                with LOCK:
                    doc = _ev_doc()
                    e = doc.get("events", {}).get(_ev_id(year, title))
                    if e is None:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    e["photoRequest"] = {
                        "at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
                        "by": str(d.get("by", "")),
                        "message": str(d.get("message", "")),
                    }
                    _ev_save(doc)
                return self._json({"ok": True})
            # ---- 문의 접수 (이메일 발송 + 첨부 저장, 개인정보 동의 필수) ----
            if p == "/api/inquiry/submit":
                d = json.loads(self._body() or b"{}")
                name = str(d.get("name", "")).strip()
                email = str(d.get("email", "")).strip()
                phone = str(d.get("phone", "")).strip()
                number = str(d.get("number", "")).strip()
                subject = str(d.get("subject", "")).strip()
                message = str(d.get("message", "")).strip()
                agreed = bool(d.get("agreed", False))
                files = d.get("files", [])
                # 1) 필수 검증 — 보낸사람 메일 없으면 발송 금지
                if "@" not in email or "." not in email.split("@")[-1]:
                    return self._json(
                        {"ok": False, "error": "보낸사람 이메일이 필요합니다."}, 400)
                # 2) 개인정보 동의 없으면 발송 금지
                if not agreed:
                    return self._json(
                        {"ok": False, "error": "개인정보 활용 동의가 필요합니다."}, 400)
                if not name:
                    return self._json(
                        {"ok": False, "error": "이름(실명)을 입력하세요."}, 400)
                if not message:
                    return self._json(
                        {"ok": False, "error": "문의 내용을 입력하세요."}, 400)

                # 3) 첨부파일 저장 (base64 → 문의첨부 폴더)
                saved_files = []
                stamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
                if isinstance(files, list) and files:
                    try:
                        if not NAS.exists(INQUIRY_DIR):
                            NAS.mkdir(BASE, "문의첨부")
                    except Exception:
                        pass
                    for i, f in enumerate(files):
                        try:
                            fname = _ev_safe(str(f.get("name", f"file{i}")))
                            raw = base64.b64decode(str(f.get("data", "")))
                            if not raw:
                                continue
                            dst = f"{INQUIRY_DIR}/{stamp}_{name}_{fname}"
                            NAS.write(dst, raw)
                            saved_files.append(dst)
                        except Exception:
                            continue

                # 4) 문의 로그 저장
                rec = {
                    "at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "name": name,
                    "email": email,
                    "phone": phone,
                    "number": number,
                    "subject": subject,
                    "message": message,
                    "agreed": True,
                    "files": [
                        os.path.basename(x) for x in saved_files
                    ],
                }
                try:
                    with LOCK:
                        log = _load_json(INQUIRY_FILE, {"items": []})
                        log.setdefault("items", []).append(rec)
                        _save_json(INQUIRY_FILE, log)
                except Exception:
                    pass

                # 5) 이메일 발송 시도 (SMTP 설정이 config 에 있으면 실제 발송)
                mailed = _send_inquiry_mail(rec)
                return self._json({
                    "ok": True,
                    "mailed": mailed,
                    "attachments": len(saved_files),
                    "note": "" if mailed else
                    "메일 서버 미설정: 문의가 서버에 접수되었습니다.",
                })
            return self._json({"ok": False, "error": "unknown"}, 404)
        except Exception as e:
            return self._json({"ok": False, "error": str(e)}, 500)


if __name__ == "__main__":
    _boot()
    port = CONF.get("port", 5071)
    # 성능: NAS 연결/TLS/로그인을 백그라운드로 미리 데운다.
    #  첫 사용자 요청의 콜드 스타트 지연을 제거(실패해도 무해).
    def _warm_bg():
        try:
            NAS.warm()
            print("NAS connection warmed")
        except Exception as e:
            print("NAS warm skipped:", e)
        # 정적 자산 사전 압축(첫 사용자 지연 제거)
        _precompress_static()
    threading.Thread(target=_warm_bg, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"TSAK NAS proxy on 0.0.0.0:{port}")
    srv.serve_forever()
