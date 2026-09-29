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
import urllib.request

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
FINANCE_ANALYSIS_FILE = BASE + "/db/finance_analysis.json"  # Phase4 은행거래 종합분석 캐시
REVIEW_FILE = BASE + "/db/event_reviews.json"   # 행사 후기 게시판(댓글/첨부/좋아요/임시저장)
BOARD_FILE = BASE + "/db/board.json"            # 행사+수품판매 게시판(글/댓글/좋아요/첨부/비밀번호/비노출)
NOTIFY_FILE = BASE + "/db/notify.json"          # 게시판/주문 등 관리자 이상 알림 큐
MERCH_FILE = BASE + "/db/merch.json"            # 수품구매: 상품/주문/연회비 설정
MERCH_MAKER_DIR = BASE + "/수품제작자"           # 수품 제작자 첨부파일 저장 폴더
MERCH_IMG_UPLOAD_DIR = HERE + "/merch_img_upload"  # 관리자 업로드 상품 이미지 폴더
LOCK = threading.Lock()

# 행사별 하위 폴더(항목) — 번호+한글명, 업로드 가능 폴더엔 "_(업로드가능)" 꼬리말
EVENT_SUBFOLDERS = [
    ("01_계획서_(업로드가능)", "plan", True),
    ("02_참석자_(업로드가능)", "attendees", True),
    ("03_사진+동영상_(업로드가능)", "media", True),
    ("04_참가비·후원금", "fee", False),
    ("05_행사비지출내역", "expense", False),
    ("06_후기첨부_(업로드가능)", "review", True),
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
    "board": "게시판첨부",
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


def _sess_new(tier, who="", regular=False):
    sid = _secrets.token_urlsafe(32)
    with _SESS_LOCK:
        # 오래된 세션 정리
        now = time.time()
        for k in [k for k, v in _SESS.items() if v.get("exp", 0) < now]:
            _SESS.pop(k, None)
        _SESS[sid] = {"tier": tier, "who": who, "regular": bool(regular),
                      "exp": now + _SESS_TTL}
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
_BOARD_WRITE_LOCK = threading.Lock()   # 게시판 쓰기 직렬화(후기 연동 포함)
_REVIEW_WRITE_LOCK = threading.Lock()  # 행사 후기 쓰기 직렬화(게시판 연동 포함)


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
    # 본인 로그인 여부 — 개인/비인가자가 자기 인가번호(전화)로 접속한 경우.
    is_self = str(tier) in ("personal", "guest")
    entry = {
        "ts": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "event": "login",
        "self": is_self,
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


def _log_access_view(viewer_tier, viewer_who, target_ident, ua, ip):
    """타 사용자(마스터/관리자/다른 회원)가 개인 프로필을 열람한 이력 1건 기록."""
    target = re.sub(r"[^0-9]", "", str(target_ident or ""))
    if not target:
        return None
    vwho = re.sub(r"[^0-9]", "", str(viewer_who or ""))
    name = ""
    try:
        m = _ev_member_by_ident(target)
        if m:
            name = str(m.get("name", ""))
    except Exception:
        pass
    tier = str(viewer_tier or "")
    # 열람자 표시 라벨 — 마스터/관리자/인가자(번호)/비인가자.
    if tier == "master":
        label = "마스터"
    elif tier == "app":
        label = "관리자"
    elif tier == "personal":
        label = "인가자"
    elif tier == "guest":
        label = "비인가자"
    else:
        label = "열람자"
    is_self = bool(vwho) and vwho == target and tier in ("personal", "guest")
    entry = {
        "ts": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "event": "view",
        "self": is_self,
        "tier": tier,
        "role": label,
        "ident": target,
        "who": vwho,
        "name": name,
        "viewer": label + ((" " + vwho) if vwho else ""),
        "viewerTier": tier,
        "viewerWho": vwho,
        "device": _ua_device_name(ua),
        "ua": str(ua or "")[:300],
        "ip": str(ip or ""),
    }
    _access_log_append(entry)
    return entry


def _scope_members(tier, who, members, regular=False):
    """역할별 최소 항목 제공(대량 명단 열람 최소화).

    - 관리자(app)·마스터: 전체
    - 범스카우트(personal): 역할권한에 따라
        · memberDetail 허용 시 → 전원 상세(민감필드 제거)
        · memberSearch 만 허용 시 → 전원 축약형(이름·번호 중심)
        · 둘 다 불가 시 → 본인 1건만
    - 서포터즈(regular personal)/비인가자(guest): 본인 1건만 + 민감 필드 제거
    - '샘플' 회원(sample=true)은 모든 회원이 볼 수 있다(안내·예시용).
    """
    who = re.sub(r"[^0-9]", "", str(who or ""))
    if tier in ("app", "master"):
        return members
    # 실효 역할 키 도출
    if tier == "personal":
        role = "supporter" if regular else "personal"
    else:
        role = "guest"
    detail = _perm_for(role, "memberDetail")
    search = _perm_for(role, "memberSearch")
    out = []
    for m in members:
        num = re.sub(r"[^0-9]", "", str(m.get("number", "")))
        lid = re.sub(r"[^0-9]", "", str(m.get("loginId", "")))
        ph = re.sub(r"[^0-9]", "", str(m.get("phone", "")))
        is_self = bool(who) and (who in (num, lid, ph))
        is_sample = m.get("sample") is True
        if is_self or is_sample or detail:
            out.append(_redact_member(m))        # 상세(민감필드만 제거)
        elif search:
            out.append(_summary_member(m))       # 이름·번호 중심 축약
        # 그 외(supporter/guest 타인)는 제외 → 개인정보 보호
    return out


def _summary_member(m):
    """축약형 회원 정보 — 이름·번호 등 최소 항목만 노출(타인 조회용)."""
    name = m.get("name", "")
    if m.get("nameVisible") is False:
        name = "(이름 비공개)"
    return {
        "id": m.get("id", ""),
        "number": m.get("number", ""),
        "name": name,
        "nameVisible": m.get("nameVisible", True),
        "league": m.get("league", ""),
        "unit": m.get("unit", ""),
        "isRegular": bool(m.get("isRegular")),
        "lifetimeMember": bool(m.get("lifetimeMember")),
        "approvalStatus": m.get("approvalStatus", ""),
        "summaryOnly": True,
    }


def _redact_member(m):
    """일반 열람 응답에서 제외해야 하는 민감 필드 제거(F01)."""
    m = dict(m)
    for k in ("personalPassword", "password", "pw", "memo", "photoPath", "address"):
        m.pop(k, None)
    # 이름 노출 제어 — 관리자가 '이름 비공개'로 설정한 경우 이름을 가린다.
    if m.get("nameVisible") is False:
        m["name"] = "(이름 비공개)"
        m["nameHidden"] = True
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


# ---- 멘토·페런츠 연결 승인 ----
#  회원이 멘토/페런츠(보호자)를 지정하면 관리자·마스터 승인을 받도록 한다.
#  linkApprovalStatus: ''(미요청) | 'pending'(요청) | 'approved'(승인) | 'held'(보류)
def _link_of(m):
    s = str(m.get("linkApprovalStatus") or "").strip()
    if s in ("pending", "approved", "held"):
        return s
    return ""


def _link_pending_members():
    """멘토/페런츠를 지정했고 승인 대기(pending)인 회원 목록."""
    out = []
    for m in _ev_members():
        mentors = m.get("mentors") or []
        parents = m.get("parents") or []
        if not isinstance(mentors, list):
            mentors = []
        if not isinstance(parents, list):
            parents = []
        if not (mentors or parents):
            continue
        if _link_of(m) != "pending":
            continue
        out.append({
            "id": str(m.get("id", "")),
            "number": str(m.get("number", "")),
            "name": str(m.get("name", "")),
            "phone": str(m.get("phone", "")),
            "unit": str(m.get("unit", "")),
            "league": str(m.get("league", "")),
            "mentors": [str(x) for x in mentors],
            "parents": [str(x) for x in parents],
            "note": str(m.get("linkApprovalNote", "")),
            "linkApprovalStatus": "pending",
        })
    return out


def _set_member_link(ident, status, note=""):
    """멘토·페런츠 연결 승인 상태 변경(단일). 반환: (ok, name)"""
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
                m["linkApprovalStatus"] = status
                if note:
                    m["linkApprovalNote"] = str(note)[:300]
                if status == "approved":
                    m["linkApprovedAt"] = _now_stamp()
                members[i] = m
                _save_json(DB_FILE, members)
                _touch_meta({"updatedBy": "link-approval"})
                return True, str(m.get("name", ""))
    return False, ""



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
    ".woff2": "font/woff2", ".otf": "font/otf", ".map": "application/json", ".txt": "text/plain",
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


def _crop_merch_image(body, src_path=None):
    """수품 이미지의 상·하단 텍스트(설명/'내답변' 입력란)와 테두리선을 자동 제거.

    구글폼/설문 캡처처럼 이미지 안에 (a) 상단 설명 텍스트, (b) 하단 '내 답변'
    입력란, (c) 사각 테두리 박스가 섞여 있어도, 순수 수품 사진 영역만 잘라
    반환한다. 실패 시 원본을 그대로 반환.

    구현: 축소 이미지에서 순수 numpy 연결요소 라벨링 → 테두리 루프/얇은
    텍스트줄/세로선/점잡음 제거 → 남은(수품) 요소들의 합집합 bbox 로 크롭.
    """
    try:
        import io
        import numpy as np
        from PIL import Image
        im = Image.open(io.BytesIO(body)).convert("RGB")
        W, H = im.size
        if W < 40 or H < 40:
            return body
        # 분석용 축소(속도/노이즈) — 최대 200px
        scale = min(1.0, 200.0 / max(W, H))
        sw, sh = max(8, int(W * scale)), max(8, int(H * scale))
        small = im.resize((sw, sh))
        arr = np.asarray(small).astype("int16")
        bg = arr[2, 2]
        ink = (np.abs(arr - bg).sum(axis=2) > 60)
        if ink.mean() < 0.004:
            return body
        lbl = _numpy_cc_label(ink)
        if lbl is None:
            return body
        keep = np.zeros((sh, sw), dtype=bool)
        uniq = np.unique(lbl)
        # 수품은 이미지 중앙에 있고, 설명 텍스트는 최상단, '내답변'은 최하단에
        # 위치한다는 전제로 상·하단 12% 영역에만 존재하는 요소는 제거한다.
        top_zone = 0.12 * sh
        bot_zone = 0.88 * sh
        for lid in uniq:
            if lid == 0:
                continue
            ys, xs = np.where(lbl == lid)
            x0, x1 = int(xs.min()), int(xs.max()) + 1
            y0, y1 = int(ys.min()), int(ys.max()) + 1
            cw, ch = x1 - x0, y1 - y0
            area = len(xs)
            fill = area / float(cw * ch)
            # (a) 테두리 루프 제거
            if cw > 0.85 * sw and ch > 0.85 * sh and fill < 0.22:
                continue
            # (b) 가로 텍스트줄/구분선 제거
            if ch < 0.07 * sh and cw > 0.30 * sw:
                continue
            # (c) 세로 구분선 제거
            if cw < 0.07 * sw and ch > 0.30 * sh:
                continue
            # (d) 상·하단 텍스트 영역에만 있는 요소 제거(설명/'내답변')
            if y1 <= top_zone or y0 >= bot_zone:
                continue
            # (e) 작은 점/글자 잡음 제거
            if area < 0.0008 * sw * sh:
                continue
            keep[y0:y1, x0:x1] |= (lbl[y0:y1, x0:x1] == lid)
        ys, xs = np.where(keep)
        if len(xs) < 20:
            ys, xs = np.where(ink)
        if len(xs) == 0:
            return body
        # 축소 좌표 → 원본 좌표
        def to_full(v):
            return int(round(v / scale))
        pad = max(2, int(min(W, H) * 0.012))
        box = (max(0, to_full(xs.min()) - pad),
               max(0, to_full(ys.min()) - pad),
               min(W, to_full(xs.max() + 1) + pad),
               min(H, to_full(ys.max() + 1) + pad))
        if (box[2] - box[0]) < W * 0.12 or (box[3] - box[1]) < H * 0.12:
            return body
        return _crop_and_encode(im, box, W, H, src_path) or body
    except Exception as e:
        print("crop fail", e)
        return body


def _numpy_cc_label(mask):
    """순수 numpy 연결요소 라벨링(8-연결, 벡터화 min 전파).

    scipy/cv2/skimage 의존 없이 동작하도록 축소 이미지에서 수행한다.
    반환: 라벨 int32 배열(배경=0). 과도하게 크면 None.
    """
    try:
        import numpy as np
        h, w = mask.shape
        BIG = np.int32(1 << 29)
        idx = np.arange(1, h * w + 1, dtype="int32").reshape(h, w)
        # 배경은 전파를 막기 위해 큰 값으로 두고, 마지막에만 0으로 되돌린다.
        lbl = np.where(mask, idx, BIG).astype("int32")
        if int(lbl.min()) == int(BIG):
            return None
        # 가장자리에서 배경으로 전파되지 않도록 BIG으로 패딩한다.
        pad = np.full((h + 2, w + 2), BIG, dtype="int32")
        shifts = [(-1, 0), (1, 0), (0, -1), (0, 1),
                  (-1, -1), (-1, 1), (1, -1), (1, 1)]
        for it in range(400):
            pad[1:h + 1, 1:w + 1] = lbl
            mn = lbl.copy()
            for dy, dx in shifts:
                nb = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
                np.minimum(mn, nb, out=mn)
            if np.array_equal(mn, lbl):
                break
            lbl = mn
        lbl[~mask] = 0
        return lbl
    except Exception as e:
        print("ccl fail", e)
        return None


def _crop_and_encode(im, box, w, h, src_path=None):
    """박스로 크롭 후 JPEG 바이트 반환."""
    import io
    im2 = im.crop(box)
    out = io.BytesIO()
    im2.save(out, format="JPEG", quality=88)
    print(f"merch crop {src_path}: {w}x{h} -> {box} = {im2.size[0]}x{im2.size[1]}")
    return out.getvalue()


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


def _default_role_perms():
    """역할별 메뉴 접근권한 기본값 (마스터가 마스터창에서 변경 가능).
    메뉴 키:
      bulk(단체문자) finance(재무) merchMgmt(수품관리/등록/판매) stats(통계)
      board(게시판) events(행사관리) merchBuy(수품구매)
      memberSearch(명단검색) memberAdd(인가자 생성) memberDetail(타인 상세열람)
    """
    def p(**kw):
        base = {k: False for k in (
            "bulk", "finance", "merchMgmt", "stats", "board", "events",
            "merchBuy", "memberSearch", "memberAdd", "memberDetail")}
        base.update(kw)
        return base
    return {
        # 마스터: 전부 허용
        "master": p(bulk=True, finance=True, merchMgmt=True, stats=True,
                    board=True, events=True, merchBuy=True,
                    memberSearch=True, memberAdd=True, memberDetail=True),
        # 관리자: 마스터 전용(앱관리·마스터창)을 제외한 전부 허용
        "app": p(bulk=True, finance=True, merchMgmt=True, stats=True,
                 board=True, events=True, merchBuy=True,
                 memberSearch=True, memberAdd=True, memberDetail=True),
        # 범스카우트(인가자): 수품구매·행사·게시판만, 타인 상세 불가(이름·번호만 조회)
        "personal": p(bulk=False, finance=False, merchMgmt=False, stats=False,
                      board=True, events=True, merchBuy=True,
                      memberSearch=True, memberAdd=False, memberDetail=False),
        # 서포터즈(일반회원): 같은 화면이나 개인정보(명단검색/상세) 불가
        "supporter": p(bulk=False, finance=False, merchMgmt=False, stats=False,
                       board=True, events=True, merchBuy=True,
                       memberSearch=False, memberAdd=False, memberDetail=False),
        # 비인가자: 최소 권한
        "guest": p(bulk=False, finance=False, merchMgmt=False, stats=False,
                   board=True, events=True, merchBuy=True,
                   memberSearch=False, memberAdd=False, memberDetail=False),
    }


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
        "admins": [],                   # 마스터가 관리자 권한을 부여한 인가번호 목록
        "rolePermissions": _default_role_perms(),  # 역할별 메뉴 접근권한(마스터 설정)
    }


def _role_perms():
    """역할별 메뉴권한 설정(누락 키는 기본값으로 보충)."""
    cfg = _load_json(CFG_FILE, _default_config())
    saved = cfg.get("rolePermissions", {}) or {}
    base = _default_role_perms()
    out = {}
    for role, dflt in base.items():
        merged = dict(dflt)
        role_saved = saved.get(role, {}) or {}
        for k in merged:
            if k in role_saved:
                merged[k] = bool(role_saved[k])
        out[role] = merged
    return out


def _perm_for(role, key):
    return bool(_role_perms().get(role, {}).get(key, False))


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


def _granted_admins():
    """마스터가 관리자 권한을 부여한 인가번호 집합."""
    cfg = _load_json(CFG_FILE, _default_config())
    lst = cfg.get("admins", [])
    if not isinstance(lst, list):
        return set()
    out = set()
    for x in lst:
        d = re.sub(r"[^0-9]", "", str(x))
        if d:
            out.add(d)
    return out


def _is_granted_admin(no):
    no = re.sub(r"[^0-9]", "", str(no or ""))
    return bool(no) and no in _granted_admins()


def _member_by_number(no):
    no = re.sub(r"[^0-9]", "", str(no or ""))
    if not no:
        return None
    for m in _load_json(DB_FILE, []):
        if re.sub(r"[^0-9]", "", str(m.get("number", ""))) == no:
            return m
    return None


def _is_regular_member(no):
    """해당 인가번호가 일반회원(서포터즈)인지 — isRegular 플래그 기준."""
    m = _member_by_number(no)
    return bool(m and m.get("isRegular") is True)


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


def _ev_media_images_recursive(year, title, sub=""):
    """media 폴더(하위폴더 포함)의 이미지 파일 목록을 재귀 수집."""
    fp = _ev_sub_dir(year, title, "media", sub)
    if not fp or not NAS.exists(fp):
        return []
    try:
        r = NAS.list(fp)
    except Exception:
        return []
    if not r.get("ok"):
        return []
    out = []
    for f in sorted(r.get("files") or [], key=lambda x: str(x.get("name", ""))):
        nm = str(f.get("name", ""))
        if nm.startswith("."):
            continue
        child = f"{sub}/{nm}" if sub else nm
        if f.get("isdir"):
            out.extend(_ev_media_images_recursive(year, title, child))
        elif _kind_of(nm) == "image":
            out.append({"name": nm, "sub": sub})
    return out


def _ev_all_photos():
    """모든 행사의 사진을 행사 순서대로 모아 반환(행사별 구분용 그룹).

    반환: {ok, events:[{id,year,title,period,place,count,photos:[{name,sub}]}], total}
    - 행사 순서: 최신 연도 우선, 연도 내 최신(제목 내림차순) 우선.
    """
    doc = _ev_doc()
    items = []
    for eid, e in doc.get("events", {}).items():
        year = str(e.get("year", "") or "")
        title = str(e.get("title", "") or "")
        if not year or not title:
            continue
        imgs = _ev_media_images_recursive(year, title)
        if not imgs:
            continue
        items.append({
            "id": eid,
            "year": year,
            "title": title,
            "period": str(e.get("period", "") or ""),
            "place": str(e.get("place", "") or ""),
            "count": len(imgs),
            "photos": imgs,
        })
    items.sort(key=lambda x: (x["year"] or "0000", x["title"]), reverse=True)
    return {
        "ok": True,
        "events": items,
        "total": sum(int(x["count"]) for x in items),
        "eventCount": len(items),
    }


# ============================ 행사 후기 게시판 ============================
def _review_doc():
    return _load_json(REVIEW_FILE, {"events": {}})


def _review_save(doc):
    _save_json(REVIEW_FILE, doc)


def _review_list(year, title):
    """행사 후기 목록(게시글=댓글트리) 반환. attachment는 참고용.
    각 글: {id, author, number, body, created, updated, password(해시), pwdHint,
            draft(bool), likes(int), comments:[{id,author,body,created,device,ip}]}
    """
    doc = _review_doc()
    eid = _ev_id(year, title)
    posts = doc.get("events", {}).get(eid, {}).get("posts", [])
    # 공개 글(비번 없음 + draft 아님) + (요청자가 관리자면 전부)
    return posts


def _review_save_posts(year, title, posts):
    doc = _review_doc()
    doc.setdefault("events", {}).setdefault(_ev_id(year, title), {})["posts"] = posts
    _review_save(doc)


def _review_sync_from_board(post):
    """게시판 '후기' 글 수정 → 행사 후기로 역연동(서로 연동)."""
    rid = str((post or {}).get("sourceReview", "") or "")
    year = str((post or {}).get("year", "") or "")
    title = str((post or {}).get("eventTitle", "") or "")
    if not rid or not year or not title:
        return
    try:
        with _REVIEW_WRITE_LOCK:
            doc = _review_doc()
            eid = _ev_id(year, title)
            posts = doc.get("events", {}).get(eid, {}).get("posts", [])
            tgt = next((x for x in posts if str(x.get("id")) == rid), None)
            if not tgt:
                return
            tgt["body"] = str((post or {}).get("body", "") or "")
            tgt["author"] = str((post or {}).get("author", "") or "")[:40]
            tgt["number"] = str((post or {}).get("number", "") or "")[:20]
            # 댓글/첨부/좋아요는 후기 원본을 유지(게시판 측 데이터로 덮어쓰지 않음)
            tgt["updated"] = _now_stamp()
            doc.setdefault("events", {}).setdefault(eid, {})["posts"] = posts
            _review_save(doc)
    except Exception:
        pass


def _review_delete_by_board(post):
    """게시판 '후기' 글 삭제 → 행사 후기도 함께 삭제(서로 연동)."""
    rid = str((post or {}).get("sourceReview", "") or "")
    year = str((post or {}).get("year", "") or "")
    title = str((post or {}).get("eventTitle", "") or "")
    if not rid or not year or not title:
        return
    try:
        with _REVIEW_WRITE_LOCK:
            doc = _review_doc()
            eid = _ev_id(year, title)
            posts = doc.get("events", {}).get(eid, {}).get("posts", [])
            keep = [x for x in posts if str(x.get("id")) != rid]
            if len(keep) != len(posts):
                doc.setdefault("events", {}).setdefault(eid, {})["posts"] = keep
                _review_save(doc)
    except Exception:
        pass


def _pwd_hash(pw):
    import hashlib
    return hashlib.sha256(("tsak$" + str(pw)).encode("utf-8")).hexdigest()


def _now_stamp():
    return datetime.datetime.now().strftime("%Y.%m.%d %H:%M:%S")


def _now_date():
    return datetime.datetime.now().strftime("%Y.%m.%d")


def _now_ymd(o):
    """주문 dict 에서 연도 문자열 추출(created 예: '2025.03.14 10:22')."""
    c = str((o or {}).get("created", ""))
    m = re.match(r"(\d{4})", c)
    return m.group(1) if m else str((o or {}).get("year", ""))


# ===================== 행사 + 수품판매 게시판 (#12) =====================
def _board_doc():
    return _load_json(BOARD_FILE, {"posts": []})


def _board_sync_review(year, title, post):
    """행사 후기를 게시판 '후기' 카테고리 글과 연동(생성/수정).
    같은 후기 id 를 sourceReview 로 갖는 게시판 글을 찾아 갱신하거나 새로 만든다.
    """
    try:
        with _BOARD_WRITE_LOCK:
            doc = _load_json(BOARD_FILE, {"posts": []})
            posts = doc.get("posts", [])
            rid = str((post or {}).get("id", "") or "")
            if not rid:
                return
            bid = next((str(x.get("id")) for x in posts
                        if str(x.get("sourceReview", "")) == rid), "")
            existing = next((x for x in posts
                             if str(x.get("id")) == bid), None)
            title_txt = f"[후기] {str(title or '').strip()}"
            new_post = {
                "id": bid or ("bd" + _secrets.token_urlsafe(6)),
                "category": "후기",
                "title": title_txt[:120],
                "body": str((post or {}).get("body", "") or ""),
                "author": str((post or {}).get("author", "") or "")[:40],
                "number": str((post or {}).get("number", "") or "")[:20],
                "created": existing.get("created") if existing else _now_stamp(),
                "updated": _now_stamp(),
                "likes": int((post or {}).get("likes", 0) or 0),
                "views": int(existing.get("views", 0) or 0) if existing else 0,
                "comments": ((post or {}).get("comments", []) or [])
                            if not existing else (existing.get("comments") or []),
                "attachments": (post or {}).get("attachments", []) or [],
                "media": (existing or {}).get("media", []),
                "links": (existing or {}).get("links", []),
                "hidden": bool(existing.get("hidden", False)) if existing else False,
                "device": str((post or {}).get("device", "") or "")[:120],
                "ip": str((post or {}).get("ip", "") or ""),
                "sourceReview": rid,
                "year": str(year or ""),
                "eventTitle": str(title or ""),
            }
            if existing:
                posts[posts.index(existing)] = new_post
            else:
                posts.append(new_post)
                try:
                    _board_notify(new_post)
                except Exception:
                    pass
            doc["posts"] = posts
            _save_json(BOARD_FILE, doc)
    except Exception:
        pass


def _board_delete_review(rid):
    """후기 삭제 시 연동된 게시판 '후기' 글도 함께 제거."""
    try:
        rid = str(rid or "")
        if not rid:
            return
        with _BOARD_WRITE_LOCK:
            doc = _load_json(BOARD_FILE, {"posts": []})
            posts = doc.get("posts", [])
            keep = [x for x in posts if str(x.get("sourceReview", "")) != rid]
            if len(keep) != len(posts):
                doc["posts"] = keep
                _save_json(BOARD_FILE, doc)
    except Exception:
        pass



def _board_save(doc):
    _save_json(BOARD_FILE, doc)


def _board_public(post, is_admin):
    """클라이언트 노출용으로 민감 필드(password 해시) 제거."""
    out = dict(post)
    out.pop("password", None)
    out["hasPassword"] = bool(post.get("password"))
    if not is_admin:
        out.pop("hidden", None)
    return out


def _board_next_id(posts):
    return "bd" + _secrets.token_urlsafe(6)


def _board_notify(post):
    """신규 게시글 → 관리자 이상 알림 큐에 적재."""
    doc = _load_json(NOTIFY_FILE, {"items": []})
    items = doc.get("items", [])
    items.insert(0, {
        "id": "nt" + _secrets.token_urlsafe(6),
        "type": "board",
        "title": str(post.get("title", "") or "새 게시글"),
        "category": str(post.get("category", "") or ""),
        "author": str(post.get("author", "") or ""),
        "postId": str(post.get("id", "") or ""),
        "text": "새 게시글이 등록되었습니다: " + str(post.get("title", "") or ""),
        "created": _now_stamp(),
        "read": False,
    })
    doc["items"] = items[:200]
    _save_json(NOTIFY_FILE, doc)


# ===================== 도로명주소 검색 (행정안전부 JUSO 오픈API) =====================
# 승인키가 설정되면 사용, 없으면 공공 테스트키(TESTJUSOGOKR)로 동작.
def _addr_confm_key():
    try:
        cfg = _load_json(CFG_FILE, {})
        k = str(cfg.get("jusoKey", "") or "").strip()
        return k or "TESTJUSOGOKR"
    except Exception:
        return "TESTJUSOGOKR"


def _addr_search(keyword, page="1", per="10"):
    """도로명/지번 주소 검색 결과 반환."""
    kw = str(keyword or "").strip()
    if not kw:
        return {"ok": True, "items": [], "total": 0}
    try:
        per = str(int(per))
    except Exception:
        per = "10"
    url = (
        "https://business.juso.go.kr/addrlink/addrLinkApi.do"
        "?confmKey=" + urllib.parse.quote(_addr_confm_key())
        + "&currentPage=" + urllib.parse.quote(str(page))
        + "&countPerPage=" + urllib.parse.quote(per)
        + "&keyword=" + urllib.parse.quote(kw)
        + "&resultType=json"
    )
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (TSAK App)",
            "Accept": "application/json",
        })
        with urllib.request.urlopen(req, timeout=12) as resp:
            raw = resp.read().decode("utf-8", "replace")
        j = json.loads(raw)
        res = j.get("results", {})
        common = res.get("common", {})
        code = str(common.get("errorCode", "0"))
        if code != "0":
            return {"ok": False, "items": [], "total": 0,
                    "error": common.get("errorMessage", "주소검색 오류")}
        items = []
        for it in (res.get("juso") or []):
            items.append({
                "road": (str(it.get("roadAddr", "")) or "").strip(),
                "roadPart2": (str(it.get("roadAddrPart2", "")) or "").strip(),
                "jibun": (str(it.get("jibunAddr", "")) or "").strip(),
                "zip": (str(it.get("zipNo", "")) or "").strip(),
                "bdNm": (str(it.get("bdNm", "")) or "").strip(),
                "siNm": (str(it.get("siNm", "")) or "").strip(),
                "sggNm": (str(it.get("sggNm", "")) or "").strip(),
            })
        return {"ok": True, "items": items,
                "total": int(common.get("totalCount", len(items)) or 0)}
    except Exception as e:
        return {"ok": False, "items": [], "total": 0, "error": str(e)}


# ============================ 수품구매 (굿즈/상품 주문) ============================
# 구글폼(공식 수품 안내)에서 연계된 기본 안내문 — 관리자 화면에서 항시 수정 가능.
DEFAULT_MERCH_GUIDE = {
    "title": "범스카우트 중앙회 수품 구매 안내",
    "membership": (
        "■ 범스카우트 인가자\n"
        "  - 연간회원: 10,000원\n"
        "  - 평생회원: 300,000원\n\n"
        "■ 서포터즈 (일반 대원·대장)\n"
        "  - 서포터즈 연간회원: 10,000원\n\n"
        "참고) 수품구매 시 납부"
    ),
    "rules": (
        "범스카우트 중앙회 공식 수품은 「범스카우트 인가자」만 구매 가능합니다.\n\n"
        "■ 인가자 전용 수품\n"
        "  - 범스카우트 중앙회 항건\n"
        "  - 평생회원 흉장\n"
        "  - 중앙회 공식 패치 및 약장\n"
        "  - 멘토 / 페런츠 메달 및 약장\n\n"
        "■ 서포터즈 구매 가능 수품\n"
        "  - 인가자 전용 품목 이외의 수품 및 굿즈"
    ),
    "sets": (
        "① 신규 인가자 세트 — 60,000원 (연회비 불포함)\n"
        "  · 조건: 2000호 이상 신규 인가자 중 중앙회 연간회원 최초 등록 시 1회 / 총 70,000원 납부\n"
        "  · 구성: 중앙회 항건 1 · 중앙회 가죽조임 1 · 멘토 메달(각인포함) 1 (페런츠 메달 변경 가능)\n\n"
        "② 평생회원 세트 — 90,000원 (평생회비 불포함)\n"
        "  · 조건: 2000호 이상 신규 인가자 중 중앙회 평생회원 등록 시 1회 / 총 390,000원 납부\n"
        "  · 구성: 중앙회 항건 1 · 공식 패치약장 2 · 금속 약장 2 · 중앙회 패치 2 · 가죽조임 1 · "
        "버클 1 · 멘토 금속약장 1 · 페런츠 금속약장 1 · 멘토 메달(각인) 1 · 페런츠 메달(각인) 1 · "
        "평생회원 조임(각인) 1 · 연간회원 뱃지 1\n"
        "  (멘토·페런츠 메달, 약장은 종류 변경 가능)"
    ),
    "notes": (
        "※ 각인이 필요한 메달 수품(멘토/페런츠)은 각인 작업을 위해 최소 3주 전 주문이 필요합니다.\n"
        "   국내 각인 업체 요청 시 1만원 추가 비용 발생(각인비·업체 배송료).\n"
        "※ 필요한 수품에만 필요 수량을 적어주세요.\n"
        "※ 자세한 문의: 한국범스카우트중앙회 사무처 (010-8496-8437)"
    ),
    # 온라인 결제 방법 안내 (PDF page12 최종 결정) — 관리자가 자유롭게 수정.
    "payment": (
        "현재 수품 구매는 아래 납부계좌로 입금(인터넷뱅킹/무통장)하는 방식입니다. "
        "입금자명에 인가자 이름을 기재해 주세요.\n"
        "· 온라인 카드결제·간편결제(PG) 도입은 별도 계약이 필요하여 준비 중입니다. 도입 시 "
        "본 안내를 통해 공지드립니다.\n"
        "· 카드결제 도입 전까지는 계좌 입금 후 개인 프로필의 수품구매 내역에서 진행상태를 "
        "확인해 주세요."
    ),
    # 연계 구매 링크(구글폼·네이버폼 등) — 주소가 유동적이므로 관리자가 직접 입력/수정한다.
    "formUrl": (
        "https://docs.google.com/forms/d/e/"
        "1FAIpQLSeW24jatei6gRJGFYTCvqYfFipKImbQdT6gVKSFs9WxCKQY4A/viewform"
    ),
    "formLabel": "공식 수품 구매 링크 열기",
    "updated": "",
}


def _merch_guide(cfg):
    """cfg.guide 를 기본값과 병합해 반환(누락 키 자동 보충)."""
    g = cfg.get("guide")
    if not isinstance(g, dict):
        g = {}
    for k, v in DEFAULT_MERCH_GUIDE.items():
        g.setdefault(k, v)
    return g


def _merch_doc():
    """수품구매 문서 구조:
    {
      "products": [ {id, name, kind, price, stock, options:[..], image, desc,
                     active, created} ],
      "orders":   [ {id, productId, product, kind, unitPrice, qty, option,
                     total, buyerName, buyerNumber, phone, address,
                     shipMethod('현장구매'|'택배발송'|'기타'), shipNote,
                     paid(bool), memo, created} ],
      "config":   { "annualFee": 10000, "salesOpen": true,
                    "account": {bank,no,holder},
                    "guide": {title,membership,rules,sets,notes,updated}, "updated" }
    }
    """
    d = _load_json(MERCH_FILE, {})
    if not isinstance(d, dict):
        d = {}
    d.setdefault("products", [])
    d.setdefault("orders", [])
    cfg = d.get("config")
    if not isinstance(cfg, dict):
        cfg = {}
    cfg.setdefault("annualFee", 10000)
    cfg.setdefault("salesOpen", True)
    acc = cfg.get("account")
    if not isinstance(acc, dict):
        acc = {}
    acc.setdefault("bank", "우리은행")
    acc.setdefault("no", "1005 102 281143")
    acc.setdefault("holder", "한국범스카우트중앙회")
    acc.setdefault("shipFee", 5000)
    cfg["account"] = acc
    cfg["guide"] = _merch_guide(cfg)
    d["config"] = cfg
    before_oo = list(d.get("orderOrder", []))
    _merch_doc_defaults(d)
    # 같은 배치(구매자·시각 동일) 기존 주문 자동 통합 — 파편화된 주문번호 정리
    _merch_unify_same_batch(d)
    # orderOrder 정합화(누락분 보충 + 통합/삭제로 사라진 stale 키 제거)
    _merch_rebuild_order(d)
    if d.get("orderOrder") != before_oo:
        try:
            _save_json(MERCH_FILE, d)
        except Exception as e:
            print("merch orderOrder save fail", e)
    if _merch_seed_once(d):
        # 최초 시드 결과를 파일에 영구 저장 (다음 조회부터 유지)
        try:
            _save_json(MERCH_FILE, d)
        except Exception as e:
            print("merch seed save fail", e)
    if _merch_seed_supplies_once(d):
        try:
            _save_json(MERCH_FILE, d)
        except Exception as e:
            print("supplies seed save fail", e)
    if _seed_makers_once(d):
        try:
            _save_json(MERCH_FILE, d)
        except Exception as e:
            print("makers seed save fail", e)
    if _seed_purchases_once(d):
        try:
            _save_json(MERCH_FILE, d)
        except Exception as e:
            print("purchases seed save fail", e)
    return d


def _merch_supplies_sorted(doc):
    """suppliesOrder(비품 id 배열) 기준으로 비품을 정렬해 반환."""
    items = list(doc.get("supplies", []))
    order = doc.get("suppliesOrder", [])
    pos = {str(k): i for i, k in enumerate(order)}
    return sorted(items, key=lambda p: pos.get(str(p.get("id")), 10 ** 9))


def _merch_plans_sorted(doc):
    """plansOrder(기획 id 배열) 기준으로 기획실 아이템을 정렬해 반환."""
    items = list(doc.get("plans", []))
    order = doc.get("plansOrder", [])
    pos = {str(k): i for i, k in enumerate(order)}
    return sorted(items, key=lambda p: pos.get(str(p.get("id")), 10 ** 9))


def _merch_survey_applicants(doc, plan_id):
    """특정 기획 아이템의 수요조사 신청자 명단(순번 포함) 및 최소수량 대비 현황."""
    plan = next((x for x in doc.get("plans", [])
                 if str(x.get("id")) == str(plan_id)), None)
    if not plan:
        return None
    apps = plan.get("applicants", [])
    if not isinstance(apps, list):
        apps = []
    minimum = int(plan.get("minQty", 0) or 0)
    return {
        "planId": str(plan_id),
        "name": plan.get("name", ""),
        "minimum": minimum,
        "count": len(apps),
        "applicants": apps,
    }


def _merch_save(doc):
    _save_json(MERCH_FILE, doc)


# 구글폼 공식 수품 안내 연계 기본 판매 목록 (최초 1회 시드)
#  - 이미지: 프로젝트에 생성한 상품 이미지 URL
_IMG = "https://www.genspark.ai/api/files/s/"
_SIZE_PANTS = ["S (28)", "M (30)", "L (32)", "XL (34)", "XXL (36)"]
DEFAULT_MERCH_PRODUCTS = [
    # ── 멤버십 세트 (가격 포함) ──
    {"name": "신규 인가자 세트", "kind": "멤버십 세트", "price": 60000, "stock": 999,
     "options": [], "image": "neckerchief.jpg",
     "desc": "중앙회 항건1·가죽조임1·멘토메달(각인)1 (연회비 불포함 · 2000호 이상 신규 인가자 연간회원 최초 등록 시 1회, 총 7만원 납부)"},
    {"name": "평생회원 세트", "kind": "멤버십 세트", "price": 90000, "stock": 999,
     "options": [], "image": "lifetime_woggle.jpg",
     "desc": "항건1·패치약장2·금속약장2·패치2·가죽조임1·버클1·멘토금속약장1·페런츠금속약장1·멘토메달(각인)1·페런츠메달(각인)1·평생회원조임(각인)1·연간회원뱃지1 (평생회비 불포함 · 총 39만원 납부)"},
    # ── 인가자 전용 수품 (구글폼 공식 가격표) ──
    {"name": "중앙회 항건 (넥커치프)", "kind": "인가자 전용", "price": 30000, "stock": 999,
     "options": [], "image": "neckerchief.jpg",
     "desc": "인가자(범스카우트) 전용 · 중앙회 항건 30,000원 · 수량을 적어주세요."},
    {"name": "중앙회 가죽조임", "kind": "인가자 전용", "price": 15000, "stock": 999,
     "options": [], "image": "woggle.jpg",
     "desc": "인가자 전용 · 가죽조임 15,000원 · 수량을 적어주세요."},
    {"name": "칠보조임", "kind": "인가자 전용", "price": 25000, "stock": 999,
     "options": [], "image": "chilbo_woggle.jpg",
     "desc": "인가자 전용 · 칠보조임 25,000원 · 수량을 적어주세요."},
    {"name": "가죽벨트", "kind": "인가자 전용", "price": 20000, "stock": 999,
     "options": ["26인치", "28인치"], "image": "leather_belt.jpg",
     "desc": "인가자 전용 · 가죽벨트 20,000원 · 사이즈 26, 28인치 · 수량을 적어주세요. (사이즈 없으면 한국스카우트 지원재단 홈페이지 참고)"},
    {"name": "중앙회 버클", "kind": "인가자 전용", "price": 10000, "stock": 999,
     "options": [], "image": "buckle.jpg",
     "desc": "인가자 전용 · 버클 10,000원 · 수량을 적어주세요."},
    {"name": "멘토 메달 (각인포함)", "kind": "인가자 전용", "price": 35000, "stock": 999,
     "options": [], "image": "medal_mentor.jpg",
     "desc": "인가자 전용 · 멘토메달 35,000원 · 각인할 인가번호와 수량을 적어주세요. · 최소 3주 전 주문 · 국내 각인 시 1만원 추가"},
    {"name": "페런츠 메달 (각인포함)", "kind": "인가자 전용", "price": 35000, "stock": 999,
     "options": [], "image": "medal_parent.jpg",
     "desc": "인가자 전용 · 페런츠메달 35,000원 · 각인할 인가번호와 수량을 적어주세요. · 최소 3주 전 주문 · 국내 각인 시 1만원 추가"},
    {"name": "범 공식 패치 약장", "kind": "인가자 전용", "price": 3000, "stock": 999,
     "options": [], "image": "patch_badge.jpg",
     "desc": "인가자 전용 · 범 공식 패치 약장 3,000원 · 수량을 적어주세요."},
    {"name": "범중앙회 패치", "kind": "인가자 전용", "price": 7000, "stock": 999,
     "options": [], "image": "patch.jpg",
     "desc": "인가자 전용 · 범중앙회 패치 7,000원 · 수량을 적어주세요."},
    {"name": "범 파우치", "kind": "인가자 전용", "price": 3000, "stock": 999,
     "options": [], "image": "pouch.jpg",
     "desc": "인가자 전용 · 범 파우치 3,000원 · 수량을 적어주세요."},
    {"name": "범 모자", "kind": "인가자 전용", "price": 28000, "stock": 999,
     "options": ["58", "60"], "image": "cap.jpg",
     "desc": "인가자 전용 · 범 모자 28,000원 · 사이즈 58, 60 · 수량과 사이즈를 적어주세요."},
    {"name": "활동바지", "kind": "인가자 전용", "price": 45000, "stock": 999,
     "options": _SIZE_PANTS, "image": "activity_pants.jpg",
     "desc": "인가자 전용 · 활동바지 45,000원 · 사이즈 S(28)/M(30)/L(32)/XL(34)/XXL(36) · 수량과 사이즈를 적어주세요."},
    {"name": "평생회원 흉장", "kind": "인가자 전용", "price": 20000, "stock": 999,
     "options": [], "image": "breast_badge.jpg",
     "desc": "인가자 전용 · 평생회원 흉장 20,000원 (평생회원 가입자만 구매가능) · 인가번호와 수량을 적어주세요."},
    {"name": "범슬링", "kind": "인가자 전용", "price": 10000, "stock": 999,
     "options": [], "image": "bungslim.jpg",
     "desc": "인가자 전용 · 범슬링 10,000원 · 수량을 적어주세요."},
    {"name": "멘토약장", "kind": "인가자 전용", "price": 3000, "stock": 999,
     "options": [], "image": "metal_badge.jpg",
     "desc": "인가자 전용 · 멘토약장 3,000원 · 수량을 적어주세요."},
    {"name": "페런츠약장", "kind": "인가자 전용", "price": 3000, "stock": 999,
     "options": [], "image": "metal_badge2.jpg",
     "desc": "인가자 전용 · 페런츠약장 3,000원 · 수량을 적어주세요."},
    {"name": "멘토 금속 약장", "kind": "인가자 전용", "price": 5000, "stock": 999,
     "options": [], "image": "metal_badge3.jpg",
     "desc": "인가자 전용 · 멘토 금속 약장 5,000원 · 수량을 적어주세요."},
    {"name": "페런츠 금속 약장", "kind": "인가자 전용", "price": 5000, "stock": 999,
     "options": [], "image": "metal_badge4.jpg",
     "desc": "인가자 전용 · 페런츠 금속 약장 5,000원 · 수량을 적어주세요."},
    {"name": "범 금속 약장", "kind": "인가자 전용", "price": 5000, "stock": 999,
     "options": [], "image": "metal_badge5.jpg",
     "desc": "인가자 전용 · 범 금속 약장 5,000원 · 수량을 적어주세요."},
    {"name": "연간회원 뱃지", "kind": "인가자 전용", "price": 5500, "stock": 999,
     "options": [], "image": "annual_badge.jpg",
     "desc": "인가자 전용 · 연간회원 뱃지 5,500원 · 연간회원 및 서포터즈 가입 시 1개 무상지급 · 추가구매 시 기입 · 수량을 적어주세요."},
]


MERCH_SEED_VERSION = 5  # 기본 수품목록 변경 시 올리면 자동 재시드(관리자 추가분은 보존)
SUPPLIES_SEED_VERSION = 1  # 중앙회 비품 목록 변경 시 올리면 자동 재시드

# 중앙회 비품 재고 리스트 (2026.08.31 양대슬 기준 시드 — 최초 1회)
#  각 항목: 품명/수량/비고. 이후 앱에서 추가·수정·삭제 가능.
DEFAULT_SUPPLIES = [
    ("3구 멀티탭", 3, "2026 정벌리 과정활동"),
    ("안전고글", 20, "2026 정벌리 과정활동"),
    ("망치", 15, "2026 정벌리 과정활동"),
    ("등산스틱", 10, "2026 정벌리 과정활동"),
    ("롤맨텐트", 3, "1동 불량 - 고으로 표기 / 사유 메모지에 기입"),
    ("롤맨 타프", 1, "1불량 고으로 표기 / 사유 메모지에 기입"),
    ("스크린타프", 2, "1불량 고으로 표기 / 사유 메모지에 기입"),
    ("롤맨 2구 버너", 1, "정상작동"),
    ("팩", 139, "새제품 : 97 / 사용중 : 10 / 불량 : 32"),
    ("비상담요", 15, ""),
    ("의사봉", 1, ""),
    ("경품추첨함", 1, ""),
    ("쟁반 대형", 2, ""),
    ("쟁반 소형", 1, ""),
    ("아이스박스", 1, "311호 이종학 선배님 기증"),
    ("사무용품", 1, "불펜, 메직, 가위, 칼, 각종"),
    ("감사장 액자 SAMPLE", 1, ""),
    ("다용도 액자", 1, ""),
    ("충회 장식용 3색 현수막", 6, "파랑 2 / 흰색 2 / 빨강 2"),
    ("배너거치대", 1, ""),
    ("재회횟사 배너 거치대 SET", 1, ""),
    ("ATAS 가입안내 배너 거치대 SET", 1, ""),
    ("부고기", 1, ""),
    ("중앙회 헹사 기", 1, ""),
    ("접이식 돌탑 박스", 6, "수품 정리용"),
]


def _merch_seed_supplies_once(doc):
    """중앙회 비품 기본 목록을 최초 1회 시드한다.
    - 시드 전용 비품('seeded':true)은 버전이 바뀌면 새 기본목록으로 교체.
    - 관리자가 직접 추가한 비품('seeded' 없음)은 보존.
    실제로 시드/갱신했으면 True 반환."""
    cfg = doc.get("config", {})
    cur = int(cfg.get("suppliesSeedVersion", 0) or 0)
    if cur == SUPPLIES_SEED_VERSION:
        return False
    kept = [s for s in doc.get("supplies", [])
            if isinstance(s, dict) and s.get("seeded") is not True]
    items = list(kept)
    for name, qty, note in DEFAULT_SUPPLIES:
        items.append({
            "id": "sp" + _secrets.token_urlsafe(5),
            "name": name,
            "qty": int(qty),
            "note": note,
            "updatedAt": _now_stamp(),   # 업데이트(수정) 날짜
            "checkedAt": "",             # 재고 확인한 날짜
            "checkedBy": "",             # 확인자 인가번호
            "checkedByName": "",         # 확인자 이름
            "updatedBy": "",             # 마지막 수정자 인가번호
            "updatedByName": "",         # 마지막 수정자 이름
            "created": _now_stamp(),
            "seeded": True,
        })
    doc["supplies"] = items
    cfg["suppliesSeedVersion"] = SUPPLIES_SEED_VERSION
    doc["config"] = cfg
    return True


# ==================== 물건 결제 (범중앙회 물건 구매/결제 내역) ====================
# xlsx(범중앙회 물건 결제 …app 전송용)를 앱 데이터로 정리한 구조.
#  doc["purchases"] = [ {id, group, category, size, qty, unitPrice, amount,
#                        note, photo, date, makerId, created, updatedAt} ]
#  엑셀에 박힌 실제 이미지(13종)를 merch_img_upload/xls_*.png 로 저장해 연결.
PURCHASES_SEED_VERSION = 4
MAKERS_SEED_VERSION = 1

# 물건 결제 시드 (그룹, 분류, 사이즈, 수량, 단가, 금액, 비고, 이미지파일, 제작자id)
_PURCHASE_SEED = [
    # ── 열전사 (합계 230,000) ──
    ("열전사", "열전사", "40mm", 100, 100, 10000, "", "xls_heat_transfer.png"),
    ("열전사", "열전사", "40mm", 100, 100, 10000, "", "xls_heat_transfer.png"),
    ("열전사", "열전사", "40mm", 100, 400, 40000, "", "xls_heat_transfer.png"),
    ("열전사", "열전사", "200mm", 100, 500, 50000, "", "xls_heat_transfer.png"),
    ("열전사", "열전사", "200mm", 100, 1200, 120000, "", "xls_heat_transfer.png"),
    # ── 뱃지 (합계 2,295,000) ──
    ("뱃지", "연간회원뱃지", "", 50, 2300, 115000, "연간회원뱃지",
     "xls_annual_badge.png"),
    ("뱃지", "공식 패치", "", 100, 3300, 330000, "범중앙회 공식 패치",
     "xls_patch_tiger.png"),
    ("뱃지", "중앙회 뱃지", "", 250, 2000, 500000, "", "xls_tsak_emblem.png"),
    ("뱃지", "약장(적)", "", 100, 2000, 200000, "",
     "xls_medal_ribbon_red.png"),
    ("뱃지", "약장(남)", "", 100, 2000, 200000, "",
     "xls_medal_ribbon_navy.png"),
    ("뱃지", "준비 뱃지", "", 100, 2300, 230000,
     "준비 뱃지 (연간회원뱃지 아님)", "xls_medal_ribbon_white.png"),
    ("뱃지", "뱃지", "", 50, 2000, 100000, "", "xls_2026_membership.png"),
    ("뱃지", "검정케이스", "", 200, 700, 140000, "", "xls_black_case.png"),
    ("뱃지", "금속스티커", "", 200, 700, 140000, "", "xls_badge_strip.png"),
    ("뱃지", "EVA", "", 200, 1700, 340000, "", "xls_badge_set.png"),
    # ── 굿즈 (합계 1,890,000) ──
    ("굿즈", "BP hat", "56cm", 1, 60000, 60000, "", "xls_bp_hat.png"),
    ("굿즈", "상의(카고팬츠)", "", 21, 30000, 630000,
     "s-4 / m-4 / l-6 / xl-3 / xxl-3 / xxxl-1", "xls_cargo_pants.png"),
    ("굿즈", "모자", "60cm", 50, 15000, 750000, "", "xls_bp_hat.png"),
    ("굿즈", "후드티", "", 15, 30000, 450000, "", "xls_heat_transfer.png"),
]

# 제작자 기본 시드 (제작자별 수품 제작 내역 — 결제/입금 정보 제외)
MAKERS_SEED = [
    {
        "category": "패치·뱃지·메달",
        "company": "안승희 제작",
        "ceo": "안승희",
        "manager": "안승희",
        "phone": "",
        "email": "",
        "memo": "범중앙회 물건(열전사·뱃지·굿즈) 제작 담당",
    },
]


def _seed_makers_once(doc):
    """기본 제작자(안승희)를 최초 1회 시드한다. 관리자 추가분은 보존."""
    cfg = doc.get("config", {})
    cur = int(cfg.get("makersSeedVersion", 0) or 0)
    if cur == MAKERS_SEED_VERSION:
        return False
    makers = [m for m in doc.get("makers", [])
              if isinstance(m, dict) and m.get("seeded") is not True]
    for base in MAKERS_SEED:
        m = dict(base)
        m["id"] = "mk" + _secrets.token_urlsafe(5)
        m["created"] = _now_stamp()
        m["seeded"] = True
        makers.append(m)
    doc["makers"] = makers
    cfg["makersSeedVersion"] = MAKERS_SEED_VERSION
    doc["config"] = cfg
    return True


def _seed_maker_id(doc):
    """시드된 제작자(안승희)의 id 반환 — 물건 결제 항목 배당용."""
    for m in doc.get("makers", []):
        if isinstance(m, dict) and m.get("seeded") is True:
            return str(m.get("id"))
    return ""


def _merch_purchases_sorted(doc):
    items = list(doc.get("purchases", []))
    order = doc.get("purchasesOrder", [])
    pos = {str(k): i for i, k in enumerate(order)}
    return sorted(items, key=lambda p: pos.get(str(p.get("id")), 10 ** 9))


def _seed_purchases_once(doc):
    """범중앙회 물건 결제 기본 목록을 최초 1회 시드한다.
    관리자가 직접 추가한 항목('seeded' 없음)은 보존."""
    cfg = doc.get("config", {})
    cur = int(cfg.get("purchasesSeedVersion", 0) or 0)
    if cur == PURCHASES_SEED_VERSION:
        return False
    kept = [p for p in doc.get("purchases", [])
            if isinstance(p, dict) and p.get("seeded") is not True]
    items = list(kept)
    order = [str(k) for k in doc.get("purchasesOrder", [])
             if any(str(x.get("id")) == str(k) for x in kept)]
    maker_id = _seed_maker_id(doc)
    stamp = "2026.09.23"

    for group, category, size, qty, unit_price, amount, note, photo in _PURCHASE_SEED:
        iid = "pu" + _secrets.token_urlsafe(5)
        items.append({
            "id": iid,
            "group": group,
            "category": category,
            "size": size,
            "qty": int(qty),
            "unitPrice": int(unit_price),
            "amount": int(amount),
            "note": note,
            "photo": photo,
            "date": stamp,
            "makerId": maker_id,
            "created": _now_stamp(),
            "updatedAt": _now_stamp(),
            "seeded": True,
        })
        order.append(iid)

    doc["purchases"] = items
    doc["purchasesOrder"] = order
    cfg["purchasesSeedVersion"] = PURCHASES_SEED_VERSION
    doc["config"] = cfg
    return True


def _merch_seed_once(doc):
    """기본 수품목록을 시드한다.
    - 시드 전용 상품('seeded':true)은 버전이 바뀌면 새 기본목록으로 교체.
    - 관리자가 직접 추가한 상품('seeded' 없음)은 그대로 보존.
    - ★중요: 시드 상품이라도 사용자가 편집한 필드(설명·가격·이미지·이름·옵션
      등)는 이름 기준으로 보존한다. (기본 desc 갱신이 사용자 편집을 덮어써
      설명이 초기화되던 문제 방지 — turn12 수정)
    실제로 시드/갱신했으면 True 반환.
    """
    cfg = doc.get("config", {})
    cur = int(cfg.get("seedVersion", 0) or 0)
    if cur == MERCH_SEED_VERSION:
        return False
    now = _now_stamp()
    prev_products = doc.get("products", [])
    # 관리자 추가 상품(seeded 아님)은 무조건 보존
    kept = [p for p in prev_products
            if isinstance(p, dict) and p.get("seeded") is not True]
    # 기존 시드 상품 → 이름 기준 맵 (사용자 편집 보존용)
    prev_seeded = {}
    for p in prev_products:
        if isinstance(p, dict) and p.get("seeded") is True:
            nm = str(p.get("name", "") or "").strip()
            if nm:
                prev_seeded[nm] = p
    prods = list(kept)
    for base in DEFAULT_MERCH_PRODUCTS:
        p = dict(base)
        nm = str(base.get("name", "") or "").strip()
        prev = prev_seeded.get(nm)
        p["id"] = (str(prev.get("id")) if prev and prev.get("id")
                   else "pr" + _secrets.token_urlsafe(5))
        # 사용자 편집 가능 필드는 기존 값이 있으면 보존 (덮어쓰기 방지)
        _preserve = ("desc", "name", "price", "kind", "stock", "options",
                     "image", "active", "cost", "created", "size",
                     "makerId", "specList", "quoteFile", "quoteFileName")
        if prev:
            for f in _preserve:
                if f in prev and prev.get(f) not in (None, ""):
                    p[f] = prev[f]
        p.setdefault("image", "")
        p.setdefault("size", "")
        p.setdefault("makerId", "")
        p.setdefault("active", True)
        p.setdefault("created", now)
        p["seeded"] = True
        prods.append(p)
    doc["products"] = prods
    cfg["seeded"] = True
    cfg["seedVersion"] = MERCH_SEED_VERSION
    doc["config"] = cfg
    return True


def _merch_member(ident):
    return _ev_member_by_ident(ident)


def _merch_fee_paid(ident, year=None):
    """연회비 납부 여부(평생회원은 항상 납부 처리)."""
    m = _merch_member(ident)
    if not m:
        return False, None
    if m.get("lifetimeMember") is True:
        return True, m
    fy = m.get("feeYears")
    if not isinstance(fy, dict):
        fy = {}
    yr = year or str(datetime.datetime.now().year)
    paid = fy.get(yr) is True or fy.get(yr + "년") is True
    if not paid:
        # paidYears 호환: 값 true 인 키에서 숫자 추출
        for k, v in fy.items():
            if v is True and re.sub(r"[^0-9]", "", str(k)) == re.sub(r"[^0-9]", "", yr):
                paid = True
                break
    return bool(paid), m


# ==================== 수품 판매관리 확장 (상태·예약·제작자·공여·재고) ====================
# 주문 진행 상태(파이프라인) — 개인 프로필 진행 바차트에 사용
MERCH_ORDER_STATUSES = ["입금확인중", "입금확인", "상품준비중", "택배발송준비중",
                        "택배발송", "배송완료", "현장수령완료", "주문취소"]
# 예약(수요조사) 상태 — 제작 여부 판단
MERCH_RESERVE_STATUSES = ["예약접수", "제작검토", "제작확정", "제작중", "입고완료", "취소"]


def _merch_status_idx(status, pipeline=None):
    pipeline = pipeline or MERCH_ORDER_STATUSES
    try:
        return pipeline.index(str(status))
    except ValueError:
        return 0


def _merch_name_short(name):
    """주문번호용 주문자 약자(성 제외 이름 2자, 짧으면 그대로)."""
    n = re.sub(r"\s+", "", str(name or ""))
    if not n:
        return "미상"
    if len(n) >= 3:
        return n[-2:]
    return n


def _merch_parse_dt(created):
    """'created' 문자열을 datetime 으로 파싱(초 포함/미포함 모두 허용)."""
    s = str(created or "").strip()
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d %H:%M"):
        try:
            return datetime.datetime.strptime(s, fmt)
        except Exception:
            continue
    return datetime.datetime.now()


def _merch_make_order_no(name, created, count):
    """주문번호 생성: {YYMMDD}-{HH:MM:SS}-{주문자}-{NNNN}
    예) 260928-18:55:30-이승준-0010  → 날짜·시간·주문자·아이템 수를 모두 유추 가능.
    'count' = 한 주문번호로 함께 구매한 아이템 수(장바구니 10개 → 0010)."""
    dt = _merch_parse_dt(created)
    ymd = dt.strftime("%y%m%d")
    hms = dt.strftime("%H:%M:%S")
    nm = re.sub(r"\s+", "", str(name or "")) or "미상"
    nm = nm[:10]
    try:
        cnt = int(count or 0)
    except Exception:
        cnt = 0
    return "%s-%s-%s-%04d" % (ymd, hms, nm, cnt)


def _merch_assign_no(doc, rec, count=None):
    """레코드에 중복 없는 주문번호(orderNo)를 부여하고 반환."""
    if rec.get("orderNo"):
        return rec["orderNo"]
    if count is None:
        cnt = rec.get("itemCount", rec.get("lineCount", 0))
        if not cnt:
            cnt = len(rec.get("lines", [])) or rec.get("qty", 0) or 0
    else:
        cnt = count
    base = _merch_make_order_no(rec.get("buyerName"), rec.get("created"), cnt)
    used = set()
    for o in doc.get("orders", []):
        if isinstance(o, dict) and o.get("orderNo"):
            used.add(str(o["orderNo"]))
    for r in doc.get("reservations", []):
        if isinstance(r, dict) and r.get("orderNo"):
            used.add(str(r["orderNo"]))
    no = base
    i = 2
    while no in used:
        no = "%s(%d)" % (base, i)
        i += 1
    rec["orderNo"] = no
    return no


def _merch_products_sorted(doc):
    """productOrder(상품 id 배열) 기준으로 상품을 정렬해 반환한다.
    목록에 없는 상품은 뒤에 원래 순서대로 붙인다."""
    prods = list(doc.get("products", []))
    order = doc.get("productOrder", [])
    pos = {str(k): i for i, k in enumerate(order)}
    return sorted(prods, key=lambda p: pos.get(str(p.get("id")), 10 ** 9))


def _norm_spec_list(v):
    """견적서 기반 세부항목(사양/옵션) 리스트를 정규화한다.
    각 항목은 {label, value, note} 형태(모두 문자열). 최대 60개·길이 제한."""
    out = []
    if not isinstance(v, list):
        return out
    for it in v[:60]:
        if not isinstance(it, dict):
            # "라벨: 값" 문자열도 허용
            s = str(it or "").strip()
            if not s:
                continue
            if ":" in s:
                a, b = s.split(":", 1)
                out.append({"label": a.strip()[:40],
                            "value": b.strip()[:120], "note": ""})
            else:
                out.append({"label": s[:40], "value": "", "note": ""})
            continue
        label = str(it.get("label", "") or "")[:40]
        value = str(it.get("value", "") or "")[:120]
        note = str(it.get("note", "") or "")[:200]
        if not (label or value or note):
            continue
        out.append({"label": label, "value": value, "note": note})
    return out


def _merch_doc_defaults(doc):
    """확장 필드 기본값 보장(예약/제작자/공여/재고/공지)."""
    doc.setdefault("orders", [])
    doc.setdefault("reservations", [])
    doc.setdefault("makers", [])
    doc.setdefault("stockLog", [])
    doc.setdefault("donations", [])
    doc.setdefault("orderOrder", [])   # 표시 순서(주문번호/번들키 배열, 앞=최신)
    doc.setdefault("productOrder", [])  # 상품 표시 순서(상품 id 배열, 앞=먼저)
    doc.setdefault("supplies", [])      # 중앙회 비품 재고 리스트(품명/수량/비고/갱신·확인 이력)
    doc.setdefault("suppliesOrder", [])  # 비품 표시 순서(비품 id 배열, 앞=먼저)
    doc.setdefault("purchases", [])      # 물건 결제(범중앙회 물건 구매/결제 내역)
    doc.setdefault("purchasesOrder", [])  # 물건 결제 표시 순서
    doc.setdefault("plans", [])          # 기획실 아이템(사진/설명/메모/가격/동영상/기획자 등)
    doc.setdefault("plansOrder", [])     # 기획실 표시 순서(기획 id 배열, 앞=먼저)
    doc.setdefault("bundles", [])      # 합친 주문 묶음 [{id,name,keys:[],created}]
    doc.setdefault("archive", [])      # 30일 경과 삭제분 영구 보전
    cfg = doc.get("config")
    if not isinstance(cfg, dict):
        cfg = {}
    cfg.setdefault("notices", "수품 구매 시 아래 유의사항을 반드시 확인해 주세요.")
    cfg.setdefault("annualFeeRequired", False)  # 엄격모드(True): 연회비 미납 시 주문 차단
    cfg.setdefault("reserveMode", False)        # 예약/수요조사 모드 전체 ON/OFF
    # 제작자 견적서/사업자등록증 파일 열람·다운로드 권한(마스터 전용이 기본).
    #  관리자(app) 접근 허용 여부를 마스터가 on/off 한다(테스트 후 개방용).
    cfg.setdefault("makerFileAdminAllowed", False)
    # 견적서 기반 판매상품 세부항목(제작 견적→상품 옵션/사양) 마스터 전용.
    #  관리자 접근 허용 여부를 마스터가 on/off 한다.
    cfg.setdefault("quoteSpecAdminAllowed", False)
    cfg.setdefault("statuses", list(MERCH_ORDER_STATUSES))
    cfg.setdefault("reserveStatuses", list(MERCH_RESERVE_STATUSES))
    doc["config"] = cfg
    for o in doc.get("orders", []):
        if isinstance(o, dict):
            o.setdefault("status", "입금확인중")
            o.setdefault("statusHistory", [])
            o.setdefault("annualFeeAdded", 0)
            o.setdefault("contactId", "")
            o.setdefault("contactType", "")
            o.setdefault("orderNo", "")
            o.setdefault("deleted", False)     # 소프트 삭제 여부
            o.setdefault("deletedAt", "")      # 삭제 시각(30일 후 완전삭제)
            o.setdefault("bundleId", "")       # 합쳐진 묶음 id(없으면 빈값)
    for r in doc.get("reservations", []):
        if isinstance(r, dict):
            r.setdefault("status", "예약접수")
            r.setdefault("statusHistory", [])
            r.setdefault("orderNo", "")
            r.setdefault("deleted", False)
            r.setdefault("deletedAt", "")
    for pr in doc.get("products", []):
        if isinstance(pr, dict):
            pr.setdefault("credentialOnly", False)  # 인가자 전용 여부
    # 주문번호 일괄 부여(기존 데이터 마이그레이션)
    for o in doc.get("orders", []):
        if isinstance(o, dict) and not o.get("orderNo"):
            _merch_assign_no(doc, o)
    for r in doc.get("reservations", []):
        if isinstance(r, dict) and not r.get("orderNo"):
            _merch_assign_no(doc, r)
    # 표시 순서 배열에 누락분 보충(최신순)
    _merch_rebuild_order(doc)
    return doc


def _merch_group_key(rec):
    """표시 그룹 키 — 합쳐진 주문은 bundleId, 아니면 orderNo."""
    b = str(rec.get("bundleId", "") or "").strip()
    if b:
        return "B:" + b
    no = str(rec.get("orderNo", "") or "").strip()
    return no if no else "#" + str(rec.get("id", ""))


def _merch_unify_same_batch(doc):
    """같은 구매자·같은 시각(생성 분)에 흩어진 기존 주문들을 하나의 주문번호로 통합.

    장바구니 일괄 주문 기능 도입 이전, 품목마다 별도 주문번호로 생성된 과거
    데이터를 자동 정리한다. (bundleId 로 이미 묶였거나 삭제분은 건드리지 않음.)
    """
    orders = doc.get("orders", [])
    groups = {}
    for o in orders:
        if not isinstance(o, dict):
            continue
        if o.get("deleted") is True or str(o.get("bundleId", "")).strip():
            continue
        buyer = re.sub(r"[^0-9]", "", str(o.get("buyerNumber", "") or ""))
        if not buyer:
            buyer = str(o.get("phone", "") or "")
        created = str(o.get("created", "") or "").strip()
        if not buyer or not created:
            continue
        groups.setdefault((buyer, created), []).append(o)
    changed = False
    for (buyer, created), arr in groups.items():
        if len(arr) < 2:
            continue
        # 대표 주문번호: 이미 번호가 있는 첫 항목 것을 공유(없으면 신규 부여)
        rep = next((x for x in arr if str(x.get("orderNo", "")).strip()), None)
        if rep is None:
            rep = arr[0]
            _merch_assign_no(doc, rep)
        shared = str(rep.get("orderNo", "")).strip()
        for x in arr:
            if str(x.get("orderNo", "")).strip() != shared:
                x["orderNo"] = shared
                changed = True
    return changed


def _merch_rebuild_order(doc):
    """orderOrder 배열을 문서의 그룹키들과 정합화(누락분 앞에 추가, 유효분 유지)."""
    all_recs = list(doc.get("orders", [])) + list(doc.get("reservations", []))
    # 현재 문서에 실제 존재하는 그룹키 집합 (통합/삭제로 사라진 stale 키 제거용)
    valid = set()
    for rec in all_recs:
        if isinstance(rec, dict) and rec.get("deleted") is not True:
            valid.add(_merch_group_key(rec))
    order = [
        k for k in doc.get("orderOrder", [])
        if isinstance(k, str) and k in valid
    ]
    seen = set(order)
    # 새로 생긴 그룹키(아직 배열에 없는 것)를 최신순으로 앞에 추가
    fresh = []
    all_recs.sort(key=lambda x: str(x.get("created", "")), reverse=True)
    for rec in all_recs:
        if not isinstance(rec, dict) or rec.get("deleted") is True:
            continue
        k = _merch_group_key(rec)
        if k not in seen:
            fresh.append(k)
            seen.add(k)
    doc["orderOrder"] = fresh + order
    return doc



def _merch_attach_to_member(ident, oid, kind="order"):
    """주문/예약/사전신청 id를 회원 프로필 수품 내역에 부착(중복 방지). 반환: 부착 성공 여부."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d or not oid:
        return False
    key = ("merchReservations" if kind == "reservation"
           else ("merchSurveys" if kind == "survey" else "merchOrders"))
    with _MEMBER_WRITE_LOCK:
        members = _ev_members()
        for i, m in enumerate(members):
            mn = re.sub(r"[^0-9]", "", str(m.get("number", "")))
            mp = re.sub(r"[^0-9]", "",
                        str(m.get("accessPhone") or m.get("phone") or ""))
            if d in (mn, mp):
                lst = m.get(key)
                if not isinstance(lst, list):
                    lst = []
                if oid not in lst:
                    lst.append(oid)
                m[key] = lst
                members[i] = m
                _save_json(DB_FILE, members)
                _touch_meta({"updatedBy": "merch"})
                return True
    return False


def _merch_detach_from_member(ident, oid, kind="order"):
    """회원 프로필에서 주문/예약/사전신청 id 제거(주문 삭제 시)."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d or not oid:
        return
    key = ("merchReservations" if kind == "reservation"
           else ("merchSurveys" if kind == "survey" else "merchOrders"))
    with _MEMBER_WRITE_LOCK:
        members = _ev_members()
        hit = False
        for i, m in enumerate(members):
            mn = re.sub(r"[^0-9]", "", str(m.get("number", "")))
            mp = re.sub(r"[^0-9]", "",
                        str(m.get("accessPhone") or m.get("phone") or ""))
            if d in (mn, mp):
                lst = m.get(key)
                if isinstance(lst, list) and oid in lst:
                    lst.remove(oid)
                    m[key] = lst
                    members[i] = m
                    hit = True
        if hit:
            _save_json(DB_FILE, members)
            _touch_meta({"updatedBy": "merch-del"})


def _merch_ensure_regular(phone, name="", email=""):
    """전화번호 기준 비인가(일반)회원 자동 생성/조회. 반환: 식별번호(숫자)."""
    d = re.sub(r"[^0-9]", "", str(phone or ""))
    if not d:
        return ""
    with _MEMBER_WRITE_LOCK:
        members = _ev_members()
        for m in members:
            mp = re.sub(r"[^0-9]", "",
                        str(m.get("accessPhone") or m.get("phone") or ""))
            if mp and mp == d:
                return re.sub(r"[^0-9]", "", str(m.get("number", ""))) or d
        existing = {re.sub(r"[^0-9]", "", str(x.get("number", "")))
                    for x in members}
        # 번호 재사용 금지: 기존 9000xx 최대값 + 1 부터 부여한다.
        #  (중간 번호가 비어도 재사용하지 않음 → 과거 주문/예약의 contactId 가
        #   다른 신규 회원에게 승계되어 타인 내역이 노출되는 보안 사고 방지)
        mx = 900000
        for x in members:
            n = re.sub(r"[^0-9]", "", str(x.get("number", "")))
            if n.startswith("9000") and len(n) >= 6:
                try:
                    mx = max(mx, int(n))
                except Exception:
                    pass
        newno = ""
        for cand in range(mx + 1, mx + 1 + max(1, len(members) + 10)):
            if str(cand) not in existing:
                newno = str(cand)
                break
        if not newno:
            newno = str(mx + 1)
        rec = {
            "id": "guest_" + newno,
            "number": newno,
            "name": str(name or "").strip() or "비인가 구매자",
            "unit": "", "league": "",
            "phone": d, "accessPhone": d, "loginId": d,
            "email": str(email or "")[:80],
            "isRegular": True,
            "personalPassword": _ev_phone_last4(d),
            "approvalStatus": "pending",
            "merchOrders": [],
        }
        members.append(rec)
        _save_json(DB_FILE, members)
        _touch_meta({"count": len(members), "updatedBy": "merch_guest"})
        return newno


def _merch_resolve_contact(num, phone, name="", email=""):
    """주문자 식별: 인가번호 우선, 없으면 전화로 비인가 자동생성.
    반환: (contactId, contactType('member'|'regular'|''))"""
    n = re.sub(r"[^0-9]", "", str(num or ""))
    p = re.sub(r"[^0-9]", "", str(phone or ""))
    if n:
        m = _ev_member_by_ident(n)
        if m:
            mno = re.sub(r"[^0-9]", "", str(m.get("number", ""))) or n
            return mno, ("regular" if m.get("isRegular") else "member")
    if p:
        # 비인가(전화) 회원은 자동생성/조회하여 '회원번호'를 contactId 로 사용한다.
        #  → 개인프로필이 회원번호로 조회해도 본인 주문이 정확히 매칭된다.
        m = _ev_member_by_ident(p)
        if m:
            mno = re.sub(r"[^0-9]", "", str(m.get("number", "")))
            if mno:
                return mno, ("regular" if m.get("isRegular") else "member")
        no = _merch_ensure_regular(p, name, email)
        if no:
            return re.sub(r"[^0-9]", "", str(no)), "regular"
    return n, ""


def _merch_json_product(pr):
    out = {k: pr.get(k) for k in
           ("id", "name", "kind", "price", "stock", "options", "image",
            "desc", "active", "makerId", "size")}
    # 각인 메달(멘토/페런츠)은 수여받는 사람(수령인) 정보 입력이 필수 → 프런트에서 폼 노출.
    out["recipientKind"] = _medal_recipient_kind(pr.get("name", ""))
    return out


def _medal_recipient_kind(name):
    """각인 메달 종류 판별 → 'mentor' | 'parent' | ''
    - 멘토 메달  : 수령인(멘토) 소속·이름·연락처 필요
    - 페런츠 메달: 수령인(보호자) 이름·연락처 필요
    (약장/패치 등 그 외 품목은 대상 아님)"""
    n = str(name or "")
    if "메달" not in n:
        return ""
    if "멘토" in n:
        return "mentor"
    if "페런츠" in n or "페렌츠" in n:
        return "parent"
    return ""


def _medal_recipient_ok(kind, rcp):
    """수령인 정보 유효성 검사(각인 메달 필수)."""
    if kind not in ("mentor", "parent"):
        return True
    if not isinstance(rcp, dict):
        return False
    name = str(rcp.get("name", "") or "").strip()
    phone = str(rcp.get("phone", "") or "").strip()
    if kind == "mentor":
        unit = str(rcp.get("unit", "") or "").strip()
        return bool(unit and name and phone)
    return bool(name and phone)


def _medal_recipient_clean(rcp):
    """저장용 수령인 정보 정규화."""
    if not isinstance(rcp, dict):
        return {}
    return {
        "unit": str(rcp.get("unit", "") or "")[:80],
        "name": str(rcp.get("name", "") or "")[:40],
        "phone": str(rcp.get("phone", "") or "")[:20],
    }


def _merch_mine(ident):
    """한 회원(인가번호/전화)의 주문/예약 내역 + 상태 파이프라인.
    삭제(소프트)된 주문은 구매자에게 노출하지 않는다."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    doc = _merch_doc()
    orders, reserves = [], []
    for o in doc.get("orders", []):
        if o.get("deleted") is True:
            continue
        if _merch_match_ident(o, d):
            orders.append(o)
    for r in doc.get("reservations", []):
        if r.get("deleted") is True:
            continue
        if _merch_match_ident(r, d):
            reserves.append(r)
    orders.sort(key=lambda x: str(x.get("created", "")), reverse=True)
    reserves.sort(key=lambda x: str(x.get("created", "")), reverse=True)
    return orders, reserves


def _merch_mine_surveys(ident):
    """한 회원(인가번호/전화)이 사전신청한 수요조사 수품 목록 + 순번/최소제작수량.
    프로필의 '수품구매' 항목에 예약(사전신청) 수품을 노출하기 위함."""
    d = re.sub(r"[^0-9]", "", str(ident or ""))
    if not d:
        return []
    doc = _merch_doc()
    out = []
    for pl in _merch_plans_sorted(doc):
        apps = pl.get("applicants", [])
        if not isinstance(apps, list):
            continue
        mine = None
        for a in apps:
            if _merch_match_ident(
                    {"contactId": a.get("contactId", ""),
                     "buyerNumber": a.get("number", ""),
                     "phone": a.get("phone", "")}, d):
                mine = a
                break
        if mine is None:
            continue
        out.append({
            "planId": pl.get("id"),
            "name": pl.get("name", ""),
            "photo": pl.get("photo", ""),
            "price": int(pl.get("price", 0) or 0),
            "minQty": int(pl.get("minQty", 0) or 0),
            "progress": pl.get("progress", ""),
            "maker": pl.get("maker", ""),
            "surveyOpen": pl.get("surveyOpen") is True,
            "count": len(apps),
            "myNo": mine.get("no", 0),
            "memo": mine.get("memo", ""),
            "at": mine.get("at", ""),
        })
    return out


DELETED_KEEP_DAYS = 30


def _merch_purge_deleted(doc):
    """삭제 후 30일이 지난 주문/예약을 archive로 이동(영구 보전, 화면 비노출)."""
    now = datetime.datetime.now()
    keep_orders, archive = [], doc.get("archive", [])
    if not isinstance(archive, list):
        archive = []
    changed = False
    for o in doc.get("orders", []):
        if isinstance(o, dict) and o.get("deleted") is True and o.get("deletedAt"):
            try:
                dt = datetime.datetime.fromisoformat(str(o["deletedAt"]))
            except Exception:
                dt = now
            if (now - dt).days >= DELETED_KEEP_DAYS:
                o["_archivedAt"] = _now_stamp()
                archive.append(o)
                changed = True
                continue
        keep_orders.append(o)
    keep_res, forders = [], doc.get("orders", [])
    for r in doc.get("reservations", []):
        if isinstance(r, dict) and r.get("deleted") is True and r.get("deletedAt"):
            try:
                dt = datetime.datetime.fromisoformat(str(r["deletedAt"]))
            except Exception:
                dt = now
            if (now - dt).days >= DELETED_KEEP_DAYS:
                r["_archivedAt"] = _now_stamp()
                archive.append(r)
                changed = True
                continue
        keep_res.append(r)
    if changed:
        doc["orders"] = keep_orders
        doc["reservations"] = keep_res
        doc["archive"] = archive
        # 표시순서에서 아카이브된 그룹키 제거
        valid = set()
        for rec in keep_orders + keep_res:
            valid.add(_merch_group_key(rec))
        doc["orderOrder"] = [k for k in doc.get("orderOrder", []) if k in valid]
    return doc


_PH2NO_CACHE = {"ts": 0.0, "map": {}}


def _phone_owner_map():
    """전화번호 → 회원번호 맵 (TTL 캐시: NAS 재조회 최소화).
    매 호출마다 회원목록을 읽으면 느리므로(주문 조회 지연) 30초 캐시한다."""
    import time as _t
    now = _t.time()
    if _PH2NO_CACHE["map"] and (now - _PH2NO_CACHE["ts"] < 30):
        return _PH2NO_CACHE["map"]
    m = {}
    for mem in _ev_members():
        no = re.sub(r"[^0-9]", "", str(mem.get("number", "")))
        for f in ("phone", "accessPhone", "loginId"):
            p = re.sub(r"[^0-9]", "", str(mem.get(f, "") or ""))
            if p and p not in m:
                m[p] = no
    _PH2NO_CACHE["ts"] = now
    _PH2NO_CACHE["map"] = m
    return m


def _merch_match_ident(rec, d):
    """주문/예약 레코드가 식별자 d(숫자)의 소유인지 판정.

    보안 강화: 비인가(일반)회원 자동생성 번호(900001~)가 재사용되면 과거
    주문의 contactId 가 다른 신규 회원에게 승계되어 타인 내역이 노출된다.
    따라서 contactId 단독 일치만으로는 매칭하지 않고, 레코드의 전화번호로
    조회한 실제 소유자 번호가 contactId 와 일치할 때만 인정한다.
    (전화번호 직접 일치는 재사용과 무관하게 항상 신뢰한다.)
    """
    if not d:
        return False
    ci = re.sub(r"[^0-9]", "", str(rec.get("contactId", "")))
    bn = re.sub(r"[^0-9]", "", str(rec.get("buyerNumber", "")))
    ph = re.sub(r"[^0-9]", "", str(rec.get("phone", "")))
    # ① 전화번호 직접 일치 — 재사용 충돌과 무관하게 항상 신뢰.
    if d in (bn, ph):
        return True
    # ② contactId 일치 — 레코드 전화의 실제 소유자가 contactId 와 같을 때만.
    if ci and ci == d:
        order_ph = ph or bn
        if not order_ph:
            return True  # 전화정보 없음 → contactId 신뢰
        owner = _phone_owner_map().get(order_ph, order_ph)
        return owner == ci
    # ③ 회원번호(d)로 조회 — 레코드 전화의 실제 소유자가 d 이면 본인 주문.
    #    (주문 시 contactId 가 전화번호로 저장된 경우도 회원번호 로그인에서 인식)
    order_ph = ph or bn
    if order_ph:
        owner = _phone_owner_map().get(order_ph, order_ph)
        if owner and owner == d:
            return True
    return False


def _merch_stats(doc):
    """누적판매·재고·예약 통계."""
    cfg = doc.get("config", {})
    orders = doc.get("orders", [])
    prods = doc.get("products", [])
    reserves = doc.get("reservations", [])
    total_sales = 0
    total_fee = 0
    by_status = {}
    by_product = {}
    by_month = {}
    sold_qty = {}
    for o in orders:
        if not isinstance(o, dict):
            continue
        if o.get("deleted") is True:
            continue
        if str(o.get("status", "")) == "주문취소":
            continue
        t = int(o.get("total", 0) or 0)
        fee = int(o.get("annualFeeAdded", 0) or 0)
        total_sales += t
        total_fee += fee
        st = str(o.get("status", "입금확인중"))
        by_status[st] = by_status.get(st, 0) + 1
        nm = str(o.get("product", ""))
        b = by_product.setdefault(nm, {"qty": 0, "amount": 0})
        b["qty"] += int(o.get("qty", 0) or 0)
        b["amount"] += t
        sold_qty[str(o.get("productId", ""))] = \
            sold_qty.get(str(o.get("productId", "")), 0) + int(o.get("qty", 0) or 0)
        ym = str(o.get("created", ""))[:7]
        if ym:
            by_month[ym] = by_month.get(ym, 0) + t
    stock = []
    for pr in prods:
        stock.append({
            "id": pr.get("id"), "name": pr.get("name"),
            "stock": int(pr.get("stock", 0) or 0),
            "sold": sold_qty.get(str(pr.get("id")), 0),
        })
    reserve_by_product = {}
    for r in reserves:
        if str(r.get("status", "")) == "취소":
            continue
        nm = str(r.get("product", ""))
        reserve_by_product[nm] = reserve_by_product.get(nm, 0) + \
            int(r.get("qty", 0) or 0)
    return {
        "orderCount": len([o for o in orders
                           if str(o.get("status", "")) != "주문취소"
                           and o.get("deleted") is not True]),
        "totalSales": total_sales,
        "totalAnnualFee": total_fee,
        "byStatus": by_status,
        "byProduct": by_product,
        "byMonth": dict(sorted(by_month.items())),
        "stock": stock,
        "reserveCount": len([r for r in reserves
                             if str(r.get("status", "")) != "취소"
                             and r.get("deleted") is not True]),
        "reserveByProduct": reserve_by_product,
    }


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


def _ev_link_attendees_to_profiles(entries, event_name):
    """참가자 목록을 회원 프로필(eventAttend)에 강제 연동한다.

    인가자·비인가자 모두 대상:
      · 인가번호/전화 일치 회원이 있으면 eventAttend[event_name]=True 로 기록.
      · 비인가자(전화만 있고 프로필이 없는 경우)는 일반회원(서포터즈) 계정을
        보장한 뒤 기록한다(_ev_guest_ensure_account_async 재사용).
    개인 프로필의 "내 행사" 및 참가 이력에 자동 반영된다.
    반환: 연동된 식별자 수.
    """
    title = str(event_name or "").strip()
    if not title:
        return 0
    idents = []
    guests = []
    for a in entries or []:
        if not isinstance(a, dict):
            continue
        ident = _ev_attendee_ident(a)
        if not ident:
            continue
        idents.append(ident)
        # 인가번호(number)가 비어 있으면 비인가(전화만)로 판단 → 계정 보장.
        if not re.sub(r"[^0-9]", "", str(a.get("number", "") or "")):
            guests.append((ident, str(a.get("name", "") or "")))
    hit = 0
    if idents:
        try:
            hit = _ev_member_set_event_batch(idents, title, True)
        except Exception:
            hit = 0
    # 전화만 있는 비인가자는 계정이 없으면 생성 후 연동(백그라운드).
    for phone, name in guests:
        try:
            _ev_guest_ensure_account_async(phone, name, title)
        except Exception:
            pass
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


# ==========================================================================
#  Phase 4 — 은행거래내역 종합 분석 (2013~ , 연도/월/행사별)
# ==========================================================================
def _finance_year_of(date_str, fallback_year=""):
    """문자열에서 4자리 연도 추출. (2013~2029)"""
    m = re.findall(r"(20\d{2})", str(date_str or ""))
    if m:
        y = m[0]
        if 2013 <= int(y) <= 2029:
            return y
    if fallback_year:
        return str(fallback_year)
    return ""


def _finance_month_of(date_str):
    """문자열에서 월(1~12) 추출. 실패 시 0."""
    s = str(date_str or "")
    # 2024-03-05 / 2024.3.5 / 2024/03/05 / 20240305
    m = re.search(r"(20\d{2})[-./]?\s*(\d{1,2})[-./]?\s*(\d{1,2})", s)
    if m:
        mo = int(m.group(2))
        if 1 <= mo <= 12:
            return mo
    m = re.search(r"(20\d{2})(\d{2})(\d{2})", s)
    if m:
        mo = int(m.group(2))
        if 1 <= mo <= 12:
            return mo
    return 0


def _bank_files_sorted():
    """은행거래내역 폴더의 파일 목록 — 최신 우선(항상 최신 파일부터 반영)."""
    target = f"{DATA_DIR}/{SUB_FOLDERS['bank']}"
    if not NAS.exists(target):
        return []
    r = NAS.list(target)
    if not r.get("ok"):
        return []
    files = [f for f in r["files"] if not f["isdir"]]
    # 파일명 역순 정렬 → 최신(연도/날짜 큰) 우선
    files.sort(key=lambda x: x["name"], reverse=True)
    return files


def _finance_analyze_all(force=False):
    """은행거래내역 폴더 전체를 2013년부터 분석.

    반환 구조:
      {
        ok, generatedAt, files:[{name,size}], years:{ "2024": {...} },
        events:{ "행사명": {...} }, totals:{...}
      }
    각 연도: { income, expense, net, count, byCategory:{}, byMonth:{1..12},
               byEvent:{}, rows:[...] }
    """
    members = _load_json(DB_FILE, [])
    rules = _load_json(MAT_FILE, _default_mat())
    files = _bank_files_sorted()

    years = {}
    events = {}
    all_rows = 0
    grand_income = 0
    grand_expense = 0
    proc_files = []

    def _bucket(y):
        if y not in years:
            years[y] = {
                "year": y, "income": 0, "expense": 0, "net": 0, "count": 0,
                "byCategory": {}, "byMonth": {str(i): {"income": 0, "expense": 0} for i in range(1, 13)},
                "byEvent": {}, "rows": [],
            }
        return years[y]

    for f in files:
        name = f["name"]
        ext = os.path.splitext(name)[1].lower()
        if ext not in (".xlsx", ".xls", ".csv", ".tsv", ".txt"):
            continue
        if name.startswith("~$") or name.startswith("."):
            continue
        fp = f"{DATA_DIR}/{SUB_FOLDERS['bank']}/{name}"
        try:
            content = NAS.read_bytes(fp)
        except Exception:
            continue
        try:
            sheets = _read_excel_sheets(content, name)
        except Exception:
            continue
        acct = _account_kind(name)
        n_file_rows = 0
        for sname, srows in sheets:
            if not srows:
                continue
            objs = _rows_to_objects(srows)
            if not objs:
                continue
            for o in objs:
                c = _classify(o, members, rules, account_kind=acct)
                dt = c.get("date", "")
                y = _finance_year_of(dt, (re.findall(r"(20\d{2})", name) or [""])[0])
                if not y:
                    continue
                # 2013년 이후만
                if int(y) < 2013:
                    continue
                amt = int(c.get("amount", 0) or 0)
                typ = c.get("type", "income")
                if amt <= 0:
                    continue
                b = _bucket(y)
                mo = _finance_month_of(dt)
                cat = c.get("category", "기타")
                ev = c.get("event", "") or "미분류"
                is_exp = (typ == "expense")
                if is_exp:
                    b["expense"] += amt
                    grand_expense += amt
                else:
                    b["income"] += amt
                    grand_income += amt
                b["count"] += 1
                all_rows += 1
                n_file_rows += 1
                ck = ("지출:" if is_exp else "수입:") + cat
                bc = b["byCategory"]
                bc[ck] = bc.get(ck, 0) + amt
                if mo:
                    b["byMonth"][str(mo)]["expense" if is_exp else "income"] += amt
                be = b["byEvent"]
                if ev not in be:
                    be[ev] = {"income": 0, "expense": 0}
                be[ev]["expense" if is_exp else "income"] += amt
                # 행사별 전역 집계(연도 무관)
                ge = events.setdefault(ev, {"event": ev, "income": 0, "expense": 0, "count": 0, "years": {}})
                ge["expense" if is_exp else "income"] += amt
                ge["count"] += 1
                ge["years"][y] = ge["years"].get(y, 0) + amt
                # 연도 rows(최근 200건 유지)
                if len(b["rows"]) < 400:
                    b["rows"].append({
                        "date": dt, "type": typ, "amount": amt,
                        "name": c.get("name", ""), "number": c.get("number", ""),
                        "category": cat, "event": c.get("event", ""),
                        "memo": c.get("memo", ""), "context": c.get("context", ""),
                        "file": name,
                    })
        if n_file_rows:
            proc_files.append({"name": name, "size": f.get("size", 0), "rows": n_file_rows})

    for y, b in years.items():
        b["net"] = b["income"] - b["expense"]
        b["rows"].sort(key=lambda r: str(r.get("date", "")), reverse=True)
        # byEvent 상위 정렬
        b["byEvent"] = dict(sorted(b["byEvent"].items(),
                                   key=lambda kv: -(kv[1]["income"] + kv[1]["expense"])))
    # byCategory 합계 정렬
    for y, b in years.items():
        b["byCategory"] = dict(sorted(b["byCategory"].items(),
                                      key=lambda kv: -kv[1]))

    out_years = dict(sorted(years.items(), reverse=True))
    return {
        "ok": True,
        "generatedAt": datetime.datetime.now().isoformat(),
        "files": proc_files,
        "fileCount": len(proc_files),
        "years": out_years,
        "events": dict(sorted(events.items(), key=lambda kv: -(kv[1]["income"] + kv[1]["expense"]))),
        "totals": {
            "income": grand_income, "expense": grand_expense,
            "net": grand_income - grand_expense, "rows": all_rows,
            "yearCount": len(out_years),
            "from": min(out_years.keys()) if out_years else "",
            "to": max(out_years.keys()) if out_years else "",
        },
    }


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
            "default-src 'self' blob:; script-src 'self' 'unsafe-inline' "
            "'unsafe-eval' blob:; style-src 'self' 'unsafe-inline' blob:; "
            "img-src 'self' data: blob:; font-src 'self' data:; "
            "connect-src 'self' https: blob:; frame-src 'self' blob:; "
            "child-src 'self' blob:; object-src 'none'; base-uri 'self'")
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

    def _is_https_req(self):
        """요청이 HTTPS(또는 HTTPS 리버스프록시 뒤)인지 판정.
        - X-Forwarded-Proto: https  (샌드박스/운영 프록시)
        - Forwarded: proto=https
        """
        try:
            xfp = (self.headers.get("X-Forwarded-Proto") or "").strip().lower()
            if xfp.split(",")[0].strip() == "https":
                return True
            fwd = (self.headers.get("Forwarded") or "").lower()
            if "proto=https" in fwd:
                return True
        except Exception:
            pass
        return False

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if getattr(self, "_pending_sid", None):
            # 세션토큰 쿠키 — HttpOnly 로 JS/XSS 탈취 차단, HTTPS 요청이면 Secure 부여.
            #  (앱은 응답 본문의 sid 를 X-TSAK-Session 헤더로 사용하므로 쿠키는
            #   보조 수단이며 HttpOnly 로 두어도 동작에 영향이 없다.)
            secure = "; Secure" if self._is_https_req() else ""
            self.send_header(
                "Set-Cookie",
                "tsak_sid=%s; Path=/; Max-Age=%d; SameSite=Strict; HttpOnly%s"
                % (urllib.parse.quote(self._pending_sid), _SESS_TTL, secure))
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

    def _serve_merch_image_named(self, name, src):
        """수품 이미지 제공.
        - name(파일명)이 있으면 로컬 merch_img 폴더에서 제공(우선).
        - 없으면 <업로드 이미지 폴더>에서 제공(관리자가 업로드한 상품 이미지).
        - 없으면 src(외부 URL)를 받아 캐시 후 제공.
        - crop=1 이면 상·하단 텍스트(설명/내답변 입력란)를 자동 크롭해 순수 수품
          이미지만 전달한다(요구사항: 수품 이미지 크롭).
        """
        safe = os.path.basename(str(name or ""))
        want_crop = False
        try:
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            want_crop = q.get("crop", ["0"])[0] in ("1", "true", "yes")
        except Exception:
            want_crop = False
        if safe:
            local = os.path.join(HERE, "merch_img", safe)
            if not os.path.exists(local):
                local = os.path.join(MERCH_IMG_UPLOAD_DIR, safe)
            if os.path.exists(local):
                try:
                    with open(local, "rb") as f:
                        body = f.read()
                    ctype = ("image/png" if safe.lower().endswith(".png")
                             else "image/gif" if safe.lower().endswith(".gif")
                             else "image/webp" if safe.lower().endswith(".webp")
                             else "image/jpeg")
                    if want_crop:
                        body = _crop_merch_image(body, local)
                    return self._bytes_cache(body, ctype, max_age=604800,
                                             immutable=not want_crop)
                except Exception as e:
                    return self._json({"ok": False, "error": str(e)}, 500)
        return self._serve_merch_image(src)

    def _serve_merch_image(self, src):
        """외부 상품 이미지를 받아 같은 출처로 전달(캐시). CORS/혼합콘텐츠 회피."""
        if not src or not (src.startswith("http://") or src.startswith("https://")):
            return self._json({"ok": False, "error": "src"}, 400)
        key = hashlib.sha1(src.encode("utf-8")).hexdigest()
        cache_dir = os.path.join(HERE, ".merch_img_cache")
        cache_path = os.path.join(cache_dir, key)
        try:
            if os.path.exists(cache_path):
                with open(cache_path, "rb") as f:
                    body = f.read()
                return self._bytes_cache(body, "image/jpeg", max_age=86400)
            req = urllib.request.Request(src, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read()
                ctype = resp.headers.get("Content-Type", "image/jpeg")
            try:
                os.makedirs(cache_dir, exist_ok=True)
                with open(cache_path, "wb") as f:
                    f.write(body)
            except Exception:
                pass
            return self._bytes_cache(body, ctype, max_age=86400)
        except Exception as e:
            return self._json({"ok": False, "error": str(e)}, 502)

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
            # ---- 도로명주소 검색 (행정안전부 JUSO 오픈API, 공개·무인증) ----
            if p == "/api/address/search":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                kw = (q.get("q", [""])[0] or "").strip()
                page = (q.get("page", ["1"])[0] or "1").strip()
                return self._json(_addr_search(kw, page))
            # ---- 수품상품 이미지 프록시 (로컬 이미지/외부 이미지를 같은 출처로 제공) ----
            if p == "/api/merch/img":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                nm = (q.get("name", [""])[0] or "").strip()
                src = (q.get("src", [""])[0] or "").strip()
                return self._serve_merch_image_named(nm, src)
            # ---- 수품 제작자 첨부파일 서빙 (견적서/사진/기타) ----
            if p == "/api/merch/file":
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                nm = _safe_name(q.get("name", [""])[0] or "")
                if not nm:
                    return self._json({"ok": False, "error": "no_name"}, 400)
                # 제작자 첨부파일 접근제어.
                #  · 견적서(quoteFile)/사업자등록증(bizLicenseFile)은 민감파일 →
                #    마스터 전용. 관리자(app)는 config.makerFileAdminAllowed=on 일 때만 허용.
                #  · 그 외(사진/기타)는 관리자 이상 허용.
                s = self._sess() or {}
                tier = str(s.get("tier") or "")
                doc = _merch_doc()
                sensitive = False
                for mk in doc.get("makers", []):
                    if not isinstance(mk, dict):
                        continue
                    if nm == str(mk.get("quoteFile", "") or "") or \
                       nm == str(mk.get("bizLicenseFile", "") or ""):
                        sensitive = True
                        break
                if sensitive:
                    cfg = doc.get("config", {}) or {}
                    allow_admin = cfg.get("makerFileAdminAllowed") is True
                    if tier != "master" and not (tier == "app" and allow_admin):
                        return self._json(
                            {"ok": False, "error": "forbidden_master_only",
                             "message": "견적서/사업자등록증은 마스터만 열람할 수 있습니다."},
                            403)
                elif tier not in ("app", "master"):
                    return self._json(
                        {"ok": False, "error": "unauthorized"}, 401)
                path = MERCH_MAKER_DIR + "/" + nm
                if NAS.exists(path):
                    ct = MIME.get(_ext_of(nm), "application/octet-stream")
                    return self._serve_nas_file(path, ct)
                return self._json({"ok": False, "error": "not found"}, 404)
            # ---- 버전 감지(업데이트 반영) ----
            # 빌드 산출물(main.dart.js)의 수정시각을 버전으로 노출한다.
            # 재빌드(재배포) 시 값이 바뀌므로 클라이언트가 자동 감지/새로고침한다.
            if p == "/version.json":
                # 1순위: 빌드 시 심어둔 version.json 의 스탬프(앱과 동일 값 → 정확 감지).
                #   ※ 이 파일은 로컬(build/web)에 있으므로 NAS 용 _load_json 이 아니라
                #     로컬 파일을 직접 읽는다.
                # 2순위(폴백): main.dart.js mtime (한국시간 KST).
                vj = {}
                try:
                    with open(os.path.join(STATIC_DIR, "version.json"),
                              encoding="utf-8") as _f:
                        vj = json.load(_f)
                except Exception:
                    vj = {}
                stamp = str(vj.get("version") or vj.get("build_id") or "").strip()
                if not stamp or not stamp.isdigit():
                    stamp = "0"
                    try:
                        bf = os.path.join(STATIC_DIR, "main.dart.js")
                        mt = os.path.getmtime(bf)
                        try:
                            from zoneinfo import ZoneInfo
                            dt = datetime.datetime.fromtimestamp(
                                mt, ZoneInfo("Asia/Seoul"))
                        except Exception:
                            dt = datetime.datetime.fromtimestamp(mt)
                        stamp = dt.strftime("%Y%m%d%H%M%S")
                    except Exception:
                        stamp = "0"
                vj["build_id"] = int(stamp)
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
            # ---- 관리자 지정 (마스터 전용) ----
            #  마스터가 특정 인가번호(회원)에게 관리자 권한을 부여/회수한다.
            #  부여된 인가번호는 개인 로그인 시 app(관리자) 세션을 받는다.
            if p == "/api/admin/admins":
                if not self._require("master"):
                    return
                admins = sorted(_granted_admins())
                # 후보: 전체 인가자(관리자 후보) 이름/번호 힌트
                members = _load_json(DB_FILE, [])
                name_of = {}
                for m in members:
                    no = re.sub(r"[^0-9]", "", str(m.get("number", "")))
                    if no:
                        name_of[no] = str(m.get("name", ""))
                rows = [{"number": n, "name": name_of.get(n, "")}
                        for n in admins]
                return self._json({"ok": True, "admins": rows,
                                   "count": len(rows)})
            if p == "/api/members":
                # F01: 무인증 차단 + 역할별 최소 항목
                if not self._require():
                    return
                s = self._sess() or {}
                members = _load_json(DB_FILE, [])
                members = _scope_members(s.get("tier"), s.get("who"), members,
                                         regular=bool(s.get("regular")))
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
            # ---- 프로필 열람 로그 기록 ----
            #  마스터/관리자/다른 회원이 개인 프로필을 열람한 이력을 남긴다.
            #  본인 로그인(personal/guest가 자기 번호)은 self=true 로 기록.
            if p == "/api/member/access-log/view":
                s = self._sess()
                if not s:
                    return self._json({"ok": False, "error": "unauthorized"}, 401)
                d = json.loads(self._body() or b"{}")
                target = re.sub(r"[^0-9]", "", str(d.get("number", "")))
                if not target:
                    return self._json({"ok": False, "error": "number"}, 400)
                ua = self.headers.get("User-Agent", "")
                ip = self.client_address[0] if self.client_address else ""
                viewer_tier = str(s.get("tier", ""))
                viewer_who = str(s.get("who", ""))
                # 개인/비인가자가 본인 프로필을 열람한 경우 → 로그인 기록만으로
                #  충분하므로 중복 열람기록은 남기지 않는다.
                is_self = (viewer_tier in ("personal", "guest")
                           and viewer_who and viewer_who == target)
                if not is_self:
                    _log_access_view(viewer_tier, viewer_who, target, ua, ip)
                return self._json({"ok": True, "logged": (not is_self)})
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
            if p == "/api/link/pending":
                # 멘토·페런츠 연결 승인 대기 목록(관리자·마스터).
                if not self._require("admin"):
                    return
                pending = _link_pending_members()
                return self._json({"ok": True, "pending": pending,
                                   "count": len(pending)})
            # ---- Phase4: 은행거래 종합분석 (캐시 우선, 관리자·마스터) ----
            if p == "/api/finance/analysis":
                if not self._require("admin"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                force = (q.get("force", ["0"])[0] or "0") in ("1", "true", "yes")
                cached = _load_json(FINANCE_ANALYSIS_FILE, None)
                if cached and not force and cached.get("ok"):
                    return self._json({"ok": True, "cached": True, "analysis": cached})
                data = _finance_analyze_all(force=force)
                try:
                    with LOCK:
                        _save_json(FINANCE_ANALYSIS_FILE, data)
                except Exception:
                    pass
                return self._json({"ok": True, "cached": False, "analysis": data})
            if p == "/api/finance/analysis/fresh":
                # 항상 최신 폴더 기준으로 재분석(작업중 화면용 - 동기 실행)
                if not self._require("admin"):
                    return
                data = _finance_analyze_all(force=True)
                try:
                    with LOCK:
                        _save_json(FINANCE_ANALYSIS_FILE, data)
                except Exception:
                    pass
                return self._json({"ok": True, "analysis": data})
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
            # ---- 역할별 메뉴 접근권한 (조회: 인증, 설정: 마스터 전용) ----
            if p == "/api/perms":
                if not self._require():
                    return
                return self._json({"ok": True, "perms": _role_perms()})
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
            if p == "/api/event/photos/all":
                if not self._require():
                    return
                return self._json(_ev_all_photos())
            if p == "/api/event/review/list":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                year = q.get("year", [""])[0]
                title = q.get("title", [""])[0]
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                posts = _review_list(year, title)
                out = []
                for pst in posts:
                    if pst.get("draft") and not is_admin:
                        continue
                    o = {k: pst.get(k) for k in
                         ("id", "author", "number", "body", "created", "updated",
                          "draft", "likes", "attachments")}
                    o["likes"] = int(pst.get("likes", 0) or 0)
                    o["locked"] = bool(pst.get("password"))
                    o["pwdHint"] = pst.get("pwdHint", "")
                    cms = []
                    for cm in (pst.get("comments") or []):
                        c = {k: cm.get(k) for k in
                             ("id", "author", "body", "created")}
                        if is_admin:
                            c["device"] = cm.get("device", "")
                            c["ip"] = cm.get("ip", "")
                            c["number"] = cm.get("number", "")
                        cms.append(c)
                    o["comments"] = cms
                    if is_admin:
                        o["device"] = pst.get("device", "")
                        o["ip"] = pst.get("ip", "")
                    out.append(o)
                out.sort(key=lambda x: str(x.get("created", "")), reverse=True)
                return self._json({"ok": True, "posts": out,
                                   "isAdmin": is_admin})
            # ---------- 행사 + 수품판매 게시판 (#12) ----------
            if p == "/api/board/list":
                if not self._require():
                    return
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                doc = _board_doc()
                out = []
                for pst in doc.get("posts", []):
                    if pst.get("hidden") and not is_admin:
                        continue
                    out.append(_board_public(pst, is_admin))
                out.sort(key=lambda x: str(x.get("created", "")), reverse=True)
                return self._json({"ok": True, "posts": out, "isAdmin": is_admin})
            if p == "/api/board/get":
                if not self._require():
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                bid = q.get("id", [""])[0]
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                doc = _board_doc()
                pst = next((x for x in doc.get("posts", [])
                            if str(x.get("id")) == bid), None)
                if not pst:
                    return self._json({"ok": False, "error": "not found"}, 404)
                if pst.get("hidden") and not is_admin:
                    return self._json({"ok": False, "error": "hidden"}, 403)
                return self._json({"ok": True, "post": _board_public(pst, is_admin)})
            if p == "/api/notify/list":
                if not self._require("admin"):
                    return
                doc = _load_json(NOTIFY_FILE, {"items": []})
                items = doc.get("items", [])
                unread = sum(1 for x in items if not x.get("read"))
                return self._json({"ok": True, "items": items[:100], "unread": unread})
            # ---------- 수품구매 (굿즈) ----------
            if p == "/api/merch":
                # 로그인 없이도 공개 조회 가능 (무인증 구매 버튼용)
                doc = _merch_doc()
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                ident = q.get("ident", [""])[0]
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                cfg = doc.get("config", {})
                # 연회비 납부 여부(연도별). ident 없으면 판단 보류
                year = q.get("year", [""])[0] or str(datetime.datetime.now().year)
                fee_paid = False
                buyer = None
                if ident:
                    fee_paid, m = _merch_fee_paid(ident, year)
                    if m:
                        buyer = {"name": m.get("name", ""),
                                 "number": re.sub(r"[^0-9]", "", str(m.get("number", ""))),
                                 "phone": m.get("phone", ""),
                                 "lifetime": m.get("lifetimeMember") is True}
                # 세션 신원(개인 로그인)도 인가자로 간주
                sess_who = re.sub(r"[^0-9]", "", str(s.get("who", "")))
                is_credentialed = bool(
                    (buyer and buyer.get("number")) or sess_who)
                prods = []
                # 상품구성(관리자) 페이지 순서(productOrder)대로 노출 — 기본순서 일치
                for pr in _merch_products_sorted(doc):
                    if pr.get("active") is False and not is_admin:
                        continue
                    # 인가자 전용 상품은 비인가(비로그인·전화) 사용자에게도 노출한다.
                    #  (요구사항) 상품 구매는 누구나 가능하되, 결제 단계에서 인가번호를
                    #  입력하면 해당 회원의 수품구매 내역에 자동 연동된다.
                    prods.append({k: pr.get(k) for k in
                                  ("id", "name", "kind", "price", "stock",
                                   "options", "image", "desc", "active",
                                   "credentialOnly")}
                                 | {"recipientKind":
                                    _medal_recipient_kind(pr.get("name", ""))})
                # 수요조사 진행중인 기획 아이템(누구나 조회 — 사전신청용).
                surveys = []
                for pl in _merch_plans_sorted(doc):
                    if pl.get("surveyOpen") is not True:
                        continue
                    apps = pl.get("applicants", [])
                    if not isinstance(apps, list):
                        apps = []
                    surveys.append({
                        "id": pl.get("id"),
                        "name": pl.get("name", ""),
                        "photo": pl.get("photo", ""),
                        "video": pl.get("video", ""),
                        "desc": pl.get("desc", ""),
                        "memo": pl.get("memo", ""),
                        "price": int(pl.get("price", 0) or 0),
                        "maker": pl.get("maker", ""),
                        "submittedAt": pl.get("submittedAt", ""),
                        "progress": pl.get("progress", ""),
                        "minQty": int(pl.get("minQty", 0) or 0),
                        "count": len(apps),
                        "applicants": apps,   # 개인 페이지 순번/명단 확인용
                    })
                return self._json({
                    "ok": True,
                    "products": prods,
                    "surveys": surveys,
                    "config": {
                        "annualFee": int(cfg.get("annualFee", 10000) or 0),
                        "salesOpen": cfg.get("salesOpen", True) is not False,
                        "annualFeeRequired": cfg.get("annualFeeRequired", False) is True,
                        "reserveMode": cfg.get("reserveMode", False) is True,
                        "account": cfg.get("account", {}),
                        "guide": _merch_guide(cfg),
                        "notices": str(cfg.get("notices", "") or ""),
                        "statuses": cfg.get("statuses", list(MERCH_ORDER_STATUSES)),
                        "reserveStatuses": cfg.get("reserveStatuses",
                                                   list(MERCH_RESERVE_STATUSES)),
                    },
                    "feePaid": bool(fee_paid),
                    "buyer": buyer,
                    "isAdmin": is_admin,
                    "year": year,
                })
            if p == "/api/merch/mine":
                # 내 수품 주문/예약 내역(상태 파이프라인 포함). ident=인가번호|전화
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                ident = q.get("ident", [""])[0]
                s = self._sess() or {}
                if not ident and s.get("who"):
                    ident = s.get("who")
                orders, reserves = _merch_mine(ident)
                surveys = _merch_mine_surveys(ident)
                doc = _merch_doc()
                cfg = doc.get("config", {})
                return self._json({
                    "ok": True,
                    "orders": orders,
                    "reservations": reserves,
                    "surveys": surveys,
                    "statuses": cfg.get("statuses", list(MERCH_ORDER_STATUSES)),
                    "reserveStatuses": cfg.get("reserveStatuses",
                                               list(MERCH_RESERVE_STATUSES)),
                })
            if p == "/api/merch/enroll-fee":
                # 연회비만 단독 납부(수품 구매 없이). 무인증 가능.
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                ident = q.get("ident", [""])[0]
                if not ident:
                    return self._json({"ok": False, "error": "no_ident"}, 400)
                doc = _merch_doc()
                cfg = doc.get("config", {})
                fee = int(cfg.get("annualFee", 10000) or 0)
                year = q.get("year", [""])[0] or str(datetime.datetime.now().year)
                oid = "fee" + _secrets.token_urlsafe(6)
                oc, octype = _merch_resolve_contact(ident, ident)
                order = {
                    "id": oid, "year": year, "productId": "__annual_fee__",
                    "product": "연회비 납부", "kind": "연회비",
                    "unitPrice": fee, "qty": 1, "option": "", "total": fee,
                    "annualFeeAdded": fee, "annualFeeOnly": True,
                    "buyerName": "", "buyerNumber": oc or "",
                    "contactId": oc, "contactType": octype,
                    "phone": q.get("phone", [""])[0], "email": "",
                    "address": "", "shipMethod": "해당없음", "shipNote": "",
                    "paid": False, "status": "입금확인중", "statusHistory": [],
                    "memo": "연회비 납부", "created": _now_stamp(),
                }
                _merch_assign_no(doc, order)
                doc.setdefault("orders", []).append(order)
                _merch_save(doc)
                if oc:
                    _merch_attach_to_member(oc, oid, "order")
                return self._json({"ok": True, "order": order,
                                   "account": cfg.get("account", {})})
            if p == "/api/merch/admin":
                if not self._require("admin"):
                    return
                doc = _merch_doc()
                # 삭제 후 30일 경과분을 archive로 이동(화면 비노출·영구보전)
                _merch_purge_deleted(doc)
                _merch_save(doc)
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                # 주문 필터(선택): year, productId, paid
                orders = list(doc.get("orders", []))
                yr = q.get("year", [""])[0]
                if yr:
                    orders = [o for o in orders
                              if _now_ymd(o).startswith(yr)
                              or str(o.get("year", "")) == yr]
                orders.sort(key=lambda x: str(x.get("created", "")), reverse=True)
                reserves = list(doc.get("reservations", []))
                reserves.sort(key=lambda x: str(x.get("created", "")), reverse=True)
                # 견적서 기반 세부항목 — 마스터는 항상, 관리자는 설정이 on일 때만 수신.
                cfgd = doc.get("config", {})
                spec_ok = self._auth_ok("master") or (
                    cfgd.get("quoteSpecAdminAllowed") is True)
                prods_out = _merch_products_sorted(doc)
                # 원가·제작일은 마스터 전용 — 비마스터 응답에서는 제거한다.
                if not self._auth_ok("master"):
                    prods_out = [
                        {k: v for k, v in pr.items()
                         if k not in ("cost",)}
                        for pr in prods_out
                    ]
                if not spec_ok:
                    prods_out = [
                        {k: v for k, v in pr.items()
                         if k not in ("specList", "quoteFile", "quoteFileName")}
                        for pr in prods_out
                    ]
                # 물건결제 원가(cost)도 마스터 전용 — 비마스터 응답에서 제거.
                purchases_out = _merch_purchases_sorted(doc)
                if not self._auth_ok("master"):
                    purchases_out = [
                        {k: v for k, v in pc.items() if k != "cost"}
                        for pc in purchases_out
                    ]
                return self._json({
                    "ok": True,
                    "products": prods_out,
                    "orders": orders,
                    "reservations": reserves,
                    "makers": doc.get("makers", []),
                    "donations": doc.get("donations", []),
                    "stockLog": doc.get("stockLog", []),
                    "supplies": _merch_supplies_sorted(doc),
                    "purchases": purchases_out,
                    "plans": _merch_plans_sorted(doc),
                    "config": doc.get("config", {}),
                    "orderOrder": doc.get("orderOrder", []),
                    "bundles": doc.get("bundles", []),
                    "archived": doc.get("archive", []),
                })
            if p == "/api/merch/reports":
                if not self._require("admin"):
                    return
                doc = _merch_doc()
                return self._json({"ok": True, "stats": _merch_stats(doc)})
            if p == "/api/merch/ledger":
                # 수품판매대장 — 주문+예약 통합 대장(관리자 출력용).
                if not self._require("admin"):
                    return
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                y = q.get("year", [""])[0]
                m = q.get("month", [""])[0]
                kind = q.get("kind", [""])[0]  # order | reserve | '' (전체)
                doc = _merch_doc()
                rows = []

                def _match(rec):
                    if y and str(rec.get("year", "")) != str(y):
                        return False
                    c = str(rec.get("created", ""))
                    if m and ("." + m.zfill(2) + ".") not in c:
                        return False
                    return True

                for o in doc.get("orders", []):
                    if isinstance(o, dict) and _match(o):
                        rows.append(dict(o, _kind="주문"))
                for r in doc.get("reservations", []):
                    if isinstance(r, dict) and _match(r):
                        rows.append(dict(r, _kind="예약"))
                if kind == "order":
                    rows = [x for x in rows if x.get("_kind") == "주문"]
                elif kind == "reserve":
                    rows = [x for x in rows if x.get("_kind") == "예약"]
                rows.sort(key=lambda x: str(x.get("created", "")), reverse=True)
                # 집계
                def _amt(x):
                    return int(x.get("grandTotal", x.get("total", x.get("_amount", 0)))
                               or 0)
                summary = {
                    "rows": len(rows),
                    "orderCount": sum(1 for x in rows if x.get("_kind") == "주문"),
                    "reserveCount": sum(1 for x in rows if x.get("_kind") == "예약"),
                    "amountTotal": sum(_amt(x) for x in rows
                                       if x.get("_kind") == "주문"),
                    "paidCount": sum(1 for x in rows if x.get("paid") is True),
                    "unpaidCount": sum(1 for x in rows
                                       if x.get("_kind") == "주문"
                                       and x.get("paid") is not True),
                }
                return self._json({"ok": True, "rows": rows, "summary": summary})
            if p == "/api/merch/ledger/csv":
                # 수품판매대장 CSV 다운로드.
                if not self._require("admin"):
                    return
                import io as _io
                import csv as _csv
                q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                y = q.get("year", [""])[0]
                m = q.get("month", [""])[0]
                doc = _merch_doc()
                buf = _io.StringIO()
                w = _csv.writer(buf)
                w.writerow(["주문번호", "구분", "구매일시", "주문자", "인가번호",
                            "상품", "종류", "수량", "옵션", "사이즈", "금액",
                            "연회비", "합계", "입금", "진행상태", "배송", "주소",
                            "연락처", "이메일", "메모"])
                for o in doc.get("orders", []):
                    if not isinstance(o, dict):
                        continue
                    c = str(o.get("created", ""))
                    if y and not c.startswith(y):
                        continue
                    if m and ("." + m.zfill(2) + ".") not in c:
                        continue
                    w.writerow([
                        o.get("orderNo", ""), "주문", c, o.get("buyerName", ""),
                        o.get("buyerNumber", ""), o.get("product", ""),
                        o.get("kind", ""), o.get("qty", 1), o.get("option", ""),
                        o.get("size", ""), o.get("total", 0),
                        o.get("annualFeeAdded", 0),
                        o.get("grandTotal", o.get("total", 0)),
                        "완료" if o.get("paid") is True else "미납",
                        o.get("status", ""), o.get("shipMethod", ""),
                        o.get("address", ""), o.get("phone", ""),
                        o.get("email", ""), o.get("memo", ""),
                    ])
                for r in doc.get("reservations", []):
                    if not isinstance(r, dict):
                        continue
                    c = str(r.get("created", ""))
                    if y and not c.startswith(y):
                        continue
                    if m and ("." + m.zfill(2) + ".") not in c:
                        continue
                    w.writerow([
                        r.get("orderNo", ""), "예약", c, r.get("buyerName", ""),
                        r.get("buyerNumber", ""), r.get("product", ""),
                        r.get("kind", ""), r.get("qty", 1), r.get("option", ""),
                        r.get("size", ""), "", "", "", "", r.get("status", ""),
                        "", "", r.get("phone", ""), r.get("email", ""),
                        r.get("note", ""),
                    ])
                data = buf.getvalue()
                body = ("\ufeff" + data).encode("utf-8")  # BOM(엑셀 한글)
                self.send_response(200)
                self.send_header("Content-Type",
                                 "text/csv; charset=utf-8")
                self.send_header(
                    "Content-Disposition",
                    "attachment; filename=tsak_merch_ledger.csv")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                try:
                    self.wfile.write(body)
                except Exception:
                    pass
                return
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
                                      "manifest.json") or \
                        _os.path.splitext(name)[1].lower() in (".ttf", ".woff", ".woff2", ".otf")
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
                elif ext in (".ttf", ".woff", ".woff2", ".otf"):
                    # ⚠️ 폰트(특히 MaterialIcons)는 앱 코드 변경에 따라 서브셋 내용이 바뀐다.
                    #  immutable(1년) 로 캐시하면 사용자가 새 아이콘을 영영 못 본다(PC 누락 원인).
                    #  항상 재검증(ETag 304) → 내용이 바뀌면 즉시 새 폰트로 교체된다.
                    cache = "no-cache"
                elif "/canvaskit/" in fp or ext == ".wasm" or \
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
            if p == "/api/perms/set":
                if not self._require("master"):
                    return
                d = json.loads(self._body() or b"{}")
                role = str(d.get("role", "")).strip()
                if role not in _default_role_perms():
                    return self._json({"ok": False, "error": "bad role"}, 400)
                updates = d.get("updates", d.get("perms", {})) or {}
                if not isinstance(updates, dict):
                    updates = {}
                cfg = _load_json(CFG_FILE, _default_config())
                rp = cfg.get("rolePermissions") or _default_role_perms()
                cur = dict(rp.get(role) or _default_role_perms()[role])
                for k, v in updates.items():
                    if str(k) in cur:
                        cur[str(k)] = bool(v)
                rp[role] = cur
                cfg["rolePermissions"] = rp
                _save_json(CFG_FILE, cfg)
                return self._json({"ok": True, "role": role, "perms": cur})
            if p == "/api/admin/grant":
                d = json.loads(self._body() or b"{}")
                if not _is_master_val(d.get("master")):
                    return self._json({"ok": False, "error": "master"}, 401)
                no = re.sub(r"[^0-9]", "", str(d.get("number", "")))
                if not no:
                    return self._json({"ok": False, "error": "number"}, 400)
                # 실제 존재하는 인가자인지 확인
                m = _ev_member_by_ident(no)
                if not m or not str(m.get("number", "")).strip():
                    return self._json(
                        {"ok": False, "error": "not_found"}, 404)
                with LOCK:
                    cfg = _load_json(CFG_FILE, _default_config())
                    lst = cfg.setdefault("admins", [])
                    if not isinstance(lst, list):
                        lst = []
                    if no not in lst:
                        lst.append(no)
                    cfg["admins"] = sorted(
                        set(re.sub(r"[^0-9]", "", str(x)) for x in lst if x))
                    _save_json(CFG_FILE, cfg)
                return self._json({"ok": True, "admins": cfg["admins"],
                                   "number": no,
                                   "name": str(m.get("name", ""))})
            if p == "/api/admin/revoke":
                d = json.loads(self._body() or b"{}")
                if not _is_master_val(d.get("master")):
                    return self._json({"ok": False, "error": "master"}, 401)
                no = re.sub(r"[^0-9]", "", str(d.get("number", "")))
                if not no:
                    return self._json({"ok": False, "error": "number"}, 400)
                with LOCK:
                    cfg = _load_json(CFG_FILE, _default_config())
                    lst = cfg.get("admins", [])
                    if isinstance(lst, list):
                        cfg["admins"] = [
                            re.sub(r"[^0-9]", "", str(x))
                            for x in lst
                            if re.sub(r"[^0-9]", "", str(x)) != no]
                    else:
                        cfg["admins"] = []
                    _save_json(CFG_FILE, cfg)
                return self._json({"ok": True, "admins": cfg["admins"],
                                   "number": no})
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
                    sid = _sess_new("guest", no, regular=True) if ok else ""
                    if sid:
                        self._set_sid_cookie(sid)
                    return self._json(
                        {"ok": ok, "role": role, "number": no,
                         "supporter": bool(ok), "sid": sid})
                ok, role = _verify(tier, value)
                # 세션에 기록할 신원: 개인은 인가번호, 그 외는 role
                who = ""
                if ok and tier == "personal":
                    who = re.sub(r"[^0-9]", "", str(ident))
                # 마스터가 관리자 권한을 부여한 인가번호는 개인 로그인이어도
                #  관리자(app) 세션을 받는다(마스터 권한 부여 기능).
                granted_admin = False
                sess_tier = tier
                if ok and tier == "personal" and _is_granted_admin(who):
                    granted_admin = True
                    sess_tier = "app"
                # 개인 로그인이라도 일반회원(서포터즈)이면 role 을 supporter 로 알린다.
                is_supporter = False
                if ok and tier == "personal" and not granted_admin:
                    is_supporter = _is_regular_member(who)
                if ok:
                    _log_access_login(tier, role,
                                      who or re.sub(r"[^0-9]", "", str(ident)),
                                      who, _ua, _ip)
                sid = _sess_new(sess_tier, who,
                                regular=bool(is_supporter)) if ok else ""
                if sid:
                    self._set_sid_cookie(sid)
                return self._json(
                    {"ok": ok, "role": role, "silent": (tier == "master"),
                     "admin": granted_admin, "supporter": is_supporter,
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
                    sid = _sess_new("personal", ident,
                                    regular=_is_regular_member(ident))
                elif tier == "guest":
                    if len(ident) < 4:
                        return self._json({"ok": False, "error": "id"}, 400)
                    sid = _sess_new("guest", ident, regular=True)
                else:
                    return self._json({"ok": False, "error": "tier"}, 400)
                # [수정] 앱은 개인/마스터 로그인을 로컬에서 검증하고 세션만
                #  grant 받는 경우가 많아 접속 로그가 남지 않았다. 실제 로그인
                #  (=세션 복원이 아닌 최초 인증)일 때 클라이언트가 log=true 를
                #  보내면 여기서도 로그인 이력을 기록한다.
                if bool(d.get("log")):
                    _ua = self.headers.get("User-Agent", "")
                    _ip = self.client_address[0] if self.client_address else ""
                    _role = {"master": "master", "app": "app",
                             "personal": "personal", "guest": "일반회원"}.get(
                        tier, tier)
                    try:
                        _log_access_login(tier, _role, ident, ident, _ua, _ip)
                    except Exception as _e:
                        print("session grant log fail", _e)
                self._set_sid_cookie(sid)
                return self._json({"ok": True, "sid": sid, "tier": tier})
            # ============ 전역 인증 게이트 (F01/F02) ============
            #  로그인/로그아웃을 제외한 모든 변경(쓰기) 요청은 유효한 세션 필요.
            #  관리자 전용 경로는 추가로 tier 검사.
            if p.startswith("/api/"):
                # QR 행사참여(스캔) 경로·수품구매 주문/예약·수요조사 사전신청은 공개.
                if (p.startswith("/api/event/qr/")
                        or p in ("/api/merch/order", "/api/merch/reserve",
                                 "/api/merch/survey/apply")):
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
                    elif mode == "bulk":
                        # 선택 삭제: items=[{ts, ident}, ...] 정확히 일치하는 건만 제거.
                        items = d.get("items") or []
                        keys = set()
                        for it in items:
                            if not isinstance(it, dict):
                                continue
                            t = str(it.get("ts", ""))
                            k = re.sub(r"[^0-9]", "", str(it.get("ident", "")))
                            keys.add((t, k))
                        if keys:
                            logs = [
                                x for x in logs
                                if (str(x.get("ts", "")),
                                    re.sub(r"[^0-9]", "", str(x.get("ident", ""))))
                                not in keys
                            ]
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
            if p == "/api/link/set":
                # 멘토·페런츠 연결 승인/보류/대기 처리(관리자·마스터).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                action = str(d.get("action", "approve"))
                note = str(d.get("note", "") or "")
                idents = d.get("idents")
                if not isinstance(idents, list):
                    idents = [d.get("ident", "")]
                idents = [str(x) for x in idents if str(x).strip()]
                if not idents:
                    return self._json({"ok": False, "error": "ident"}, 400)
                status = {
                    "approve": "approved", "hold": "held",
                    "pending": "pending",
                }.get(action, "approved")
                done = 0
                for x in idents:
                    ok, _ = _set_member_link(x, status, note)
                    if ok:
                        done += 1
                return self._json({"ok": True, "done": done})
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
            if p == "/api/member/name-visible":
                # 관리자·마스터: 회원 이름 공개/비공개 토글 (개인 프로필 좌우 버튼)
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                ident = re.sub(r"[^0-9]", "", str(d.get("ident", "") or ""))
                visible = d.get("visible", True) is not False
                if not ident:
                    return self._json({"ok": False, "error": "no_ident"}, 400)
                with _MEMBER_WRITE_LOCK:
                    members = _ev_members()
                    hit = None
                    for i, m in enumerate(members):
                        num = re.sub(r"[^0-9]", "", str(m.get("number", "")))
                        ph = re.sub(r"[^0-9]", "",
                                    str(m.get("accessPhone") or m.get("phone") or ""))
                        lid = re.sub(r"[^0-9]", "", str(m.get("loginId", "")))
                        if ident in (num, ph, lid):
                            m["nameVisible"] = visible
                            members[i] = m
                            hit = m
                            break
                    if hit is None:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    _save_json(DB_FILE, members)
                    _touch_meta({"updatedBy": "name-visible"})
                return self._json({"ok": True, "nameVisible": visible})
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
            # ============ 행사 후기 게시판 (POST) ============
            if p == "/api/event/review/post":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                year = d.get("year", ""); title = d.get("title", "")
                s = self._sess() or {}
                posts = _review_list(year, title)
                pid = str(d.get("id", "") or ("p" + _secrets.token_urlsafe(6)))
                existing = next((x for x in posts if str(x.get("id")) == pid), None)
                new_post = {
                    "id": pid,
                    "author": str(d.get("author", "") or "")[:40],
                    "number": str(d.get("number", "") or "")[:20],
                    "body": str(d.get("body", "") or ""),
                    "created": existing.get("created") if existing else _now_stamp(),
                    "updated": _now_stamp(),
                    "draft": bool(d.get("draft")),
                    "likes": int(existing.get("likes", 0) or 0) if existing else 0,
                    "comments": existing.get("comments", []) if existing else [],
                    "attachments": d.get("attachments", (existing or {}).get("attachments", [])),
                    "device": str(d.get("device", "") or "")[:120],
                    "ip": self.client_address[0] if self.client_address else "",
                }
                pw = str(d.get("password", "") or "")
                if pw:
                    new_post["password"] = _pwd_hash(pw)
                    new_post["pwdHint"] = str(d.get("pwdHint", "") or "")[:40]
                elif existing:
                    new_post["password"] = existing.get("password")
                    new_post["pwdHint"] = existing.get("pwdHint", "")
                if existing:
                    posts[posts.index(existing)] = new_post
                else:
                    posts.append(new_post)
                _review_save_posts(year, title, posts)
                # 게시판 '후기' 카테고리와 자동 연동(생성/수정)
                if not new_post.get("draft"):
                    _board_sync_review(year, title, new_post)
                return self._json({"ok": True, "id": pid})
            if p == "/api/event/review/comment":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                year = d.get("year", ""); title = d.get("title", "")
                pid = str(d.get("postId", "") or "")
                posts = _review_list(year, title)
                post = next((x for x in posts if str(x.get("id")) == pid), None)
                if not post:
                    return self._json({"ok": False, "error": "post not found"}, 404)
                # 비밀번호 보호 글에는 비번 확인 후 댓글 허용 (작성자/관리자 예외)
                sself = self._sess() or {}
                is_admin = sself.get("tier") in ("app", "master")
                if post.get("password") and not is_admin:
                    if _pwd_hash(str(d.get("password", ""))) != post.get("password"):
                        return self._json({"ok": False, "error": "password"}, 403)
                cm = {
                    "id": "c" + _secrets.token_urlsafe(6),
                    "author": str(d.get("author", "") or "")[:40],
                    "number": str(d.get("number", "") or "")[:20],
                    "body": str(d.get("body", "") or ""),
                    "created": _now_stamp(),
                    "device": str(d.get("device", "") or "")[:120],
                    "ip": self.client_address[0] if self.client_address else "",
                }
                post.setdefault("comments", []).append(cm)
                _review_save_posts(year, title, posts)
                _board_sync_review(year, title, post)
                return self._json({"ok": True, "id": cm["id"]})
            if p == "/api/event/review/like":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                year = d.get("year", ""); title = d.get("title", "")
                pid = str(d.get("postId", "") or "")
                on = bool(d.get("on", True))
                posts = _review_list(year, title)
                post = next((x for x in posts if str(x.get("id")) == pid), None)
                if not post:
                    return self._json({"ok": False, "error": "post not found"}, 404)
                cur = int(post.get("likes", 0) or 0)
                post["likes"] = max(0, cur + (1 if on else -1))
                _review_save_posts(year, title, posts)
                _board_sync_review(year, title, post)
                return self._json({"ok": True, "likes": post["likes"]})
            if p == "/api/event/review/delete":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                year = d.get("year", ""); title = d.get("title", "")
                pid = str(d.get("postId", "") or "")
                cid = str(d.get("commentId", "") or "")
                posts = _review_list(year, title)
                if cid:
                    post = next((x for x in posts if str(x.get("id")) == pid), None)
                    if post:
                        post["comments"] = [c for c in post.get("comments", [])
                                            if str(c.get("id")) != cid]
                        _review_save_posts(year, title, posts)
                        return self._json({"ok": True})
                post = next((x for x in posts if str(x.get("id")) == pid), None)
                if post:
                    sself = self._sess() or {}
                    is_admin = sself.get("tier") in ("app", "master")
                    if post.get("password") and not is_admin:
                        if _pwd_hash(str(d.get("password", ""))) != post.get("password"):
                            return self._json({"ok": False, "error": "password"}, 403)
                    posts.remove(post)
                    _review_save_posts(year, title, posts)
                    # 연동된 게시판 '후기' 글도 함께 삭제
                    _board_delete_review(pid)
                return self._json({"ok": True})
            # ---------- 행사 + 수품판매 게시판 (#12) POST ----------
            if p == "/api/board/post":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                doc = _board_doc()
                posts = doc.get("posts", [])
                bid = str(d.get("id", "") or ("bd" + _secrets.token_urlsafe(6)))
                existing = next((x for x in posts if str(x.get("id")) == bid), None)
                # 수정 권한: 원글 작성자 본인 또는 관리자
                if existing and not is_admin:
                    if str(existing.get("author", "")) != str(s.get("who", "")):
                        return self._json({"ok": False, "error": "forbidden"}, 403)
                    if existing.get("password"):
                        if _pwd_hash(str(d.get("password", ""))) != existing.get("password"):
                            return self._json({"ok": False, "error": "password"}, 403)
                new_post = {
                    "id": bid,
                    "category": str(d.get("category", "") or "일반")[:20],
                    "title": str(d.get("title", "") or "")[:120],
                    "body": str(d.get("body", "") or ""),
                    "author": str(d.get("author", "") or "")[:40],
                    "number": str(d.get("number", "") or "")[:20],
                    "created": existing.get("created") if existing else _now_stamp(),
                    "updated": _now_stamp(),
                    "likes": int(existing.get("likes", 0) or 0) if existing else 0,
                    "views": int(existing.get("views", 0) or 0) if existing else 0,
                    "comments": existing.get("comments", []) if existing else [],
                    "attachments": d.get("attachments", (existing or {}).get("attachments", [])),
                    "media": d.get("media", (existing or {}).get("media", [])),
                    "links": d.get("links", (existing or {}).get("links", [])),
                    "hidden": bool(d.get("hidden", (existing or {}).get("hidden", False))),
                    "device": str(d.get("device", "") or "")[:120],
                    "ip": self.client_address[0] if self.client_address else "",
                }
                # 후기 연동 메타 보존(게시판 '후기' → 행사 후기 역연동용)
                if existing:
                    for _k in ("sourceReview", "year", "eventTitle"):
                        if existing.get(_k) is not None:
                            new_post[_k] = existing.get(_k)
                pw = str(d.get("password", "") or "")
                if pw:
                    new_post["password"] = _pwd_hash(pw)
                    new_post["pwdHint"] = str(d.get("pwdHint", "") or "")[:40]
                elif existing:
                    new_post["password"] = existing.get("password")
                    new_post["pwdHint"] = existing.get("pwdHint", "")
                if existing:
                    posts[posts.index(existing)] = new_post
                else:
                    # 신규 글 → 목록에 추가 + 관리자 이상 알림 큐 적재
                    posts.append(new_post)
                    try:
                        _board_notify(new_post)
                    except Exception:
                        pass
                doc["posts"] = posts
                _board_save(doc)
                # '후기' 카테고리 글이면 행사 후기로 역연동(편집 반영)
                if existing and str(new_post.get("category", "")) == "후기":
                    _review_sync_from_board(new_post)
                return self._json({"ok": True, "id": bid})
            if p == "/api/board/comment":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                bid = str(d.get("postId", "") or "")
                doc = _board_doc()
                posts = doc.get("posts", [])
                post = next((x for x in posts if str(x.get("id")) == bid), None)
                if not post:
                    return self._json({"ok": False, "error": "post not found"}, 404)
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                if post.get("password") and not is_admin:
                    if _pwd_hash(str(d.get("password", ""))) != post.get("password"):
                        return self._json({"ok": False, "error": "password"}, 403)
                cm = {
                    "id": "c" + _secrets.token_urlsafe(6),
                    "author": str(d.get("author", "") or "")[:40],
                    "number": str(d.get("number", "") or "")[:20],
                    "body": str(d.get("body", "") or ""),
                    "created": _now_stamp(),
                    "device": str(d.get("device", "") or "")[:120],
                    "ip": self.client_address[0] if self.client_address else "",
                }
                post.setdefault("comments", []).append(cm)
                _board_save(doc)
                return self._json({"ok": True, "id": cm["id"]})
            if p == "/api/board/like":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                bid = str(d.get("postId", "") or "")
                on = bool(d.get("on", True))
                doc = _board_doc()
                post = next((x for x in doc.get("posts", []) if str(x.get("id")) == bid), None)
                if not post:
                    return self._json({"ok": False, "error": "post not found"}, 404)
                cur = int(post.get("likes", 0) or 0)
                post["likes"] = max(0, cur + (1 if on else -1))
                _board_save(doc)
                return self._json({"ok": True, "likes": post["likes"]})
            if p == "/api/board/delete":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                bid = str(d.get("postId", "") or "")
                cid = str(d.get("commentId", "") or "")
                doc = _board_doc()
                posts = doc.get("posts", [])
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                post = next((x for x in posts if str(x.get("id")) == bid), None)
                if cid and post:
                    post["comments"] = [c for c in post.get("comments", [])
                                        if str(c.get("id")) != cid]
                    _board_save(doc)
                    return self._json({"ok": True})
                if post:
                    if not is_admin:
                        if str(post.get("author", "")) != str(s.get("who", "")):
                            return self._json({"ok": False, "error": "forbidden"}, 403)
                        if post.get("password"):
                            if _pwd_hash(str(d.get("password", ""))) != post.get("password"):
                                return self._json({"ok": False, "error": "password"}, 403)
                    posts.remove(post)
                    _board_save(doc)
                    # '후기' 카테고리 글이면 행사 후기도 함께 삭제(역연동)
                    if str(post.get("category", "")) == "후기":
                        _review_delete_by_board(post)
                return self._json({"ok": True})
            if p == "/api/board/hide":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                bid = str(d.get("postId", "") or "")
                doc = _board_doc()
                post = next((x for x in doc.get("posts", []) if str(x.get("id")) == bid), None)
                if post:
                    post["hidden"] = bool(d.get("hidden", True))
                    _board_save(doc)
                return self._json({"ok": True, "hidden": bool((post or {}).get("hidden"))})
            if p == "/api/board/view":
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                bid = str(d.get("postId", "") or "")
                doc = _board_doc()
                post = next((x for x in doc.get("posts", []) if str(x.get("id")) == bid), None)
                if post:
                    post["views"] = int(post.get("views", 0) or 0) + 1
                    _board_save(doc)
                return self._json({"ok": True, "views": int((post or {}).get("views", 0) or 0)})
            # ---------- 수품구매 (굿즈) POST ----------
            if p == "/api/merch/order":
                # 무인증(비로그인) 구매 가능. 연회비 미납이라도 '엄격모드'일 때만 차단.
                d = json.loads(self._body() or b"{}")
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                doc = _merch_doc()
                cfg = doc.get("config", {})
                if cfg.get("salesOpen", True) is False and not is_admin:
                    return self._json(
                        {"ok": False, "error": "sales_closed"}, 403)
                # ---------- 배치(장바구니 통합) 주문 ----------
                # 같은 장바구니의 모든 품목이 **하나의 주문번호(orderNo)** 를 공유한다.
                _lines = d.get("lines")
                if isinstance(_lines, list) and _lines:
                    ident0 = re.sub(r"[^0-9]", "",
                                    str(d.get("buyerNumber", "") or ""))
                    phone0 = str(d.get("phone", "") or "")
                    bname0 = str(d.get("buyerName", "") or "")
                    email0 = str(d.get("email", "") or "")
                    # 연회비 게이트(엄격모드)
                    if (cfg.get("annualFeeRequired", False) is True
                            and not is_admin):
                        paid0, _m0 = _merch_fee_paid(ident0, d.get("year"))
                        if not paid0:
                            return self._json(
                                {"ok": False, "error": "annual_fee_required"},
                                403)
                    fee_added0 = 0
                    if d.get("addAnnualFee") is True:
                        try:
                            fee_added0 = int(cfg.get("annualFee", 0) or 0)
                        except Exception:
                            fee_added0 = 0
                    oc0, octype0 = _merch_resolve_contact(
                        ident0, phone0, bname0, email0)
                    created0 = _now_stamp()
                    ship0 = str(d.get("shipMethod", "") or "현장구매")
                    # 유효 라인 수집
                    built = []
                    total0 = 0
                    for li, ln in enumerate(_lines):
                        if not isinstance(ln, dict):
                            continue
                        lpid = str(ln.get("productId", "") or "")
                        lprod = next((x for x in doc.get("products", [])
                                      if str(x.get("id")) == lpid), None)
                        if not lprod:
                            continue
                        try:
                            lunit = int(ln.get("unitPrice",
                                               lprod.get("price", 0)) or 0)
                            lqty = max(1, int(ln.get("qty", 1) or 1))
                        except Exception:
                            lunit, lqty = 0, 1
                        lfee = fee_added0 if li == 0 else 0
                        ltotal = lunit * lqty
                        total0 += ltotal
                        # 각인 메달(멘토/페런츠) 수령인 정보 — 라인별 필수.
                        mkind = _medal_recipient_kind(lprod.get("name", ""))
                        raw_recips = ln.get("recipients")
                        if not isinstance(raw_recips, list):
                            raw_recips = ([ln.get("recipient")]
                                          if isinstance(ln.get("recipient"), dict)
                                          else [])
                        recips = [_medal_recipient_clean(r) for r in raw_recips
                                  if isinstance(r, dict)]
                        if mkind:
                            # 필수: 최소 1명 + 제출된 모든 수령인이 유효해야 함.
                            if not recips or not all(
                                    _medal_recipient_ok(mkind, r)
                                    for r in recips):
                                return self._json({
                                    "ok": False,
                                    "error": "medal_recipient_required",
                                    "recipientKind": mkind,
                                    "product": str(lprod.get("name", "")),
                                }, 400)
                        built.append((lprod, lunit, lqty, lfee, ltotal,
                                      str(ln.get("option", "")
                                          or d.get("option", "") or ""),
                                      str(ln.get("size", "")
                                          or d.get("size", "") or ""),
                                      mkind, recips))
                    if not built:
                        return self._json(
                            {"ok": False, "error": "product_not_found"}, 404)
                    # 대표 주문번호: 총 아이템 수(수량 합)를 포함해 1개 생성 후 전 라인 공유
                    rep = {"buyerName": bname0, "created": created0,
                           "grandTotal": total0 + fee_added0}
                    shared_no = _merch_assign_no(
                        doc, rep, count=sum(b[2] for b in built))
                    out_orders = []
                    for (lprod, lunit, lqty, lfee, ltotal,
                         lopt, lsize, mkind, recips) in built:
                        oid = "o" + _secrets.token_urlsafe(6)
                        order = {
                            "id": oid,
                            "year": str(datetime.datetime.now().year),
                            "productId": str(lprod.get("id", "")),
                            "product": str(lprod.get("name", "")),
                            "kind": str(lprod.get("kind", "")),
                            "unitPrice": lunit,
                            "qty": lqty,
                            "option": lopt,
                            "size": lsize,
                            "total": ltotal,
                            "annualFeeAdded": lfee,
                            "grandTotal": ltotal + lfee,
                            "recipientKind": mkind,
                            "recipients": recips,
                            "recipient": (recips[0] if recips else {}),
                            "buyerName": bname0[:40],
                            "buyerNumber": ident0,
                            "contactId": oc0,
                            "contactType": octype0,
                            "phone": phone0[:20],
                            "email": email0[:80],
                            "address": str(d.get("address", "") or "")[:200],
                            "shipMethod": ship0,
                            "shipNote": str(d.get("shipNote", "") or "")[:200],
                            "paid": False,
                            "status": "입금확인중",
                            "statusHistory": [{"status": "입금확인중",
                                               "at": created0, "by": "system"}],
                            "memo": str(d.get("memo", "") or "")[:200],
                            "created": created0,
                            "orderNo": shared_no,
                        }
                        doc.setdefault("orders", []).append(order)
                        if oc0:
                            _merch_attach_to_member(oc0, oid, "order")
                        out_orders.append(order)
                    _merch_save(doc)
                    return self._json({
                        "ok": True,
                        "orders": out_orders,
                        "orderNo": shared_no,
                        "order": out_orders[0],
                        "contactId": oc0,
                        "contactType": octype0,
                        "account": cfg.get("account", {}),
                    })
                # ---------- 단일 품목 주문(기존) ----------
                pid = str(d.get("productId", "") or "")
                prod = next((x for x in doc.get("products", [])
                             if str(x.get("id")) == pid), None)
                if not prod:
                    return self._json(
                        {"ok": False, "error": "product_not_found"}, 404)
                ident = re.sub(r"[^0-9]", "", str(d.get("buyerNumber", "") or ""))
                phone = str(d.get("phone", "") or "")
                bname = str(d.get("buyerName", "") or "")
                email = str(d.get("email", "") or "")
                # 연회비 게이트 — '엄격모드(annualFeeRequired)'일 때만 차단.
                #  엄격모드가 아니면 구매단계에서 '연간회비 납부 여부'를 직접 선택하여
                #  미납 시 총액에 연회비가 자동 추가된다(간편 프로세스).
                fee_added = 0
                if cfg.get("annualFeeRequired", False) is True and not is_admin:
                    paid, _m = _merch_fee_paid(ident, d.get("year"))
                    if not paid:
                        return self._json(
                            {"ok": False, "error": "annual_fee_required"}, 403)
                # 구매단계에서 '연간회비 납부 안함' 선택 시 연회비를 총액에 가산
                if d.get("addAnnualFee") is True:
                    try:
                        fee_added = int(cfg.get("annualFee", 0) or 0)
                    except Exception:
                        fee_added = 0
                try:
                    unit = int(d.get("unitPrice", prod.get("price", 0)) or 0)
                    qty = int(d.get("qty", 1) or 1)
                except Exception:
                    unit, qty = 0, 1
                qty = max(1, qty)
                total = unit * qty
                ship = str(d.get("shipMethod", "") or "현장구매")
                # 각인 메달(멘토/페런츠) 수령인 정보 — 필수.
                mkind = _medal_recipient_kind(prod.get("name", ""))
                raw_recips = d.get("recipients")
                if not isinstance(raw_recips, list):
                    raw_recips = ([d.get("recipient")]
                                  if isinstance(d.get("recipient"), dict) else [])
                recips = [_medal_recipient_clean(r) for r in raw_recips
                          if isinstance(r, dict)]
                if mkind and (not recips or not all(
                        _medal_recipient_ok(mkind, r) for r in recips)):
                    return self._json({
                        "ok": False,
                        "error": "medal_recipient_required",
                        "recipientKind": mkind,
                        "product": str(prod.get("name", "")),
                    }, 400)
                # 주문자 식별: 인가번호 우선, 없으면 전화로 비인가 자동생성
                oc, octype = _merch_resolve_contact(ident, phone, bname, email)
                oid = "o" + _secrets.token_urlsafe(6)
                order = {
                    "id": oid,
                    "year": str(datetime.datetime.now().year),
                    "productId": pid,
                    "product": str(prod.get("name", "")),
                    "kind": str(prod.get("kind", "")),
                    "unitPrice": unit,
                    "qty": qty,
                    "option": str(d.get("option", "") or ""),
                    "size": str(d.get("size", "") or ""),
                    "total": total,
                    "annualFeeAdded": fee_added,
                    "grandTotal": total + fee_added,
                    "recipientKind": mkind,
                    "recipients": recips,
                    "recipient": (recips[0] if recips else {}),
                    "buyerName": bname[:40],
                    "buyerNumber": ident,
                    "contactId": oc,
                    "contactType": octype,
                    "phone": phone[:20],
                    "email": email[:80],
                    "address": str(d.get("address", "") or "")[:200],
                    "shipMethod": ship,
                    "shipNote": str(d.get("shipNote", "") or "")[:200],
                    "paid": False,
                    "status": "입금확인중",
                    "statusHistory": [{"status": "입금확인중",
                                       "at": _now_stamp(), "by": "system"}],
                    "memo": str(d.get("memo", "") or "")[:200],
                    "created": _now_stamp(),
                }
                _merch_assign_no(doc, order, count=1)
                doc.setdefault("orders", []).append(order)
                _merch_save(doc)
                # 인가자/비인가자 프로필에 주문 내역 부착
                if oc:
                    _merch_attach_to_member(oc, oid, "order")
                return self._json({"ok": True, "order": order,
                                   "contactId": oc, "contactType": octype,
                                   "account": cfg.get("account", {})})
            if p == "/api/merch/reserve":
                # 예약/수요조사 — 구매의사 접수(제작 판단용). 무인증 가능.
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                cfg = doc.get("config", {})
                pid = str(d.get("productId", "") or "")
                prod = next((x for x in doc.get("products", [])
                             if str(x.get("id")) == pid), None)
                if not prod:
                    return self._json(
                        {"ok": False, "error": "product_not_found"}, 404)
                ident = re.sub(r"[^0-9]", "", str(d.get("buyerNumber", "") or ""))
                phone = str(d.get("phone", "") or "")
                bname = str(d.get("buyerName", "") or "")
                email = str(d.get("email", "") or "")
                try:
                    qty = max(1, int(d.get("qty", 1) or 1))
                except Exception:
                    qty = 1
                oc, octype = _merch_resolve_contact(ident, phone, bname, email)
                rid = "r" + _secrets.token_urlsafe(6)
                rec = {
                    "id": rid,
                    "year": str(datetime.datetime.now().year),
                    "productId": pid,
                    "product": str(prod.get("name", "")),
                    "kind": str(prod.get("kind", "")),
                    "qty": qty,
                    "option": str(d.get("option", "") or ""),
                    "size": str(d.get("size", "") or ""),
                    "buyerName": bname[:40],
                    "buyerNumber": ident,
                    "contactId": oc,
                    "contactType": octype,
                    "phone": phone[:20],
                    "email": email[:80],
                    "note": str(d.get("note", "") or "")[:200],
                    "status": "예약접수",
                    "statusHistory": [{"status": "예약접수",
                                       "at": _now_stamp(), "by": "system"}],
                    "created": _now_stamp(),
                }
                try:
                    _est = int(prod.get("price", 0) or 0) * qty
                except Exception:
                    _est = 0
                rec["_amount"] = _est
                _merch_assign_no(doc, rec)
                doc.setdefault("reservations", []).append(rec)
                _merch_save(doc)
                if oc:
                    _merch_attach_to_member(oc, rid, "reservation")
                return self._json({"ok": True, "reservation": rec,
                                   "contactId": oc, "contactType": octype})
            if p == "/api/merch/product":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                pid = str(d.get("id", "") or ("pr" + _secrets.token_urlsafe(5)))
                prods = doc.get("products", [])
                existing = next((x for x in prods if str(x.get("id")) == pid), None)
                item = {
                    "id": pid,
                    "name": str(d.get("name", "") or "")[:80],
                    "kind": str(d.get("kind", "") or "")[:40],
                    "price": int(d.get("price", 0) or 0),
                    "stock": int(d.get("stock", 0) or 0),
                    "options": d.get("options", (existing or {}).get("options", [])),
                    "image": str(d.get("image", "") or "")[:300],
                    "desc": str(d.get("desc", "") or "")[:400],
                    "size": str(d.get("size", "") or "")[:80],
                    "makerId": str(d.get("makerId", "") or "")[:40],
                    # 원가(선택) · 제작일 — 마스터 전용 금액/제작 정보.
                    "cost": int(d.get("cost", (existing or {}).get("cost", 0)) or 0),
                    "madeDate": str(
                        d.get("madeDate", (existing or {}).get("madeDate", ""))
                        or "")[:40],
                    # 견적서 기반 세부항목(사양/옵션) — 마스터 전용 관리, 관리자 노출은
                    #  설정(quoteSpecAdminAllowed)에 따른다. [{label, value, note}]
                    "specList": _norm_spec_list(
                        d.get("specList", (existing or {}).get("specList", []))),
                    # 견적서 원본 파일(마스터 전용 파일열람 대상)
                    "quoteFile": str(
                        d.get("quoteFile", (existing or {}).get("quoteFile", ""))
                        or "")[:300],
                    "quoteFileName": str(
                        d.get("quoteFileName",
                              (existing or {}).get("quoteFileName", ""))
                        or "")[:200],
                    "active": d.get("active", True) is not False,
                    "credentialOnly": d.get("credentialOnly", False) is True,
                    "created": (existing or {}).get("created", _now_stamp()),
                }
                if existing:
                    # 시드/기타 플래그 보존
                    for k in ("seeded",):
                        if k in existing:
                            item[k] = existing[k]
                    prods[prods.index(existing)] = item
                else:
                    prods.append(item)
                doc["products"] = prods
                _merch_save(doc)
                return self._json({"ok": True, "product": item})
            if p == "/api/merch/product/delete":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                pid = str(d.get("id", "") or "")
                before = len(doc.get("products", []))
                doc["products"] = [x for x in doc.get("products", [])
                                   if str(x.get("id")) != pid]
                _merch_save(doc)
                return self._json({"ok": True, "removed": before - len(doc["products"])})
            if p == "/api/merch/products/order":
                # 상품 표시 순서 저장(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                ids = [str(x) for x in (d.get("ids") or [])]
                doc["productOrder"] = ids
                _merch_save(doc)
                return self._json({"ok": True, "count": len(ids)})
            if p == "/api/merch/purchase":
                # 물건 결제 항목 등록/수정(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                sid = str(d.get("id", "") or "")
                s = self._sess() or {}
                who = str(s.get("who", "") or "")
                who_name = str(d.get("whoName", "") or s.get("name", "") or "")
                items = doc.get("purchases", [])
                existing = next((x for x in items
                                 if str(x.get("id")) == sid), None) if sid else None
                now = _now_stamp()

                def _pint(v, dv=0):
                    try:
                        return int(v)
                    except Exception:
                        return dv

                if existing is None:
                    item = {
                        "id": sid or ("pu" + _secrets.token_urlsafe(5)),
                        "group": str(d.get("group", "") or "")[:40],
                        "category": str(d.get("category", "") or "")[:60],
                        "size": str(d.get("size", "") or "")[:40],
                        "qty": _pint(d.get("qty", 0)),
                        "unitPrice": _pint(d.get("unitPrice", 0)),
                        "amount": _pint(d.get("amount", 0)),
                        "note": str(d.get("note", "") or "")[:400],
                        "photo": str(d.get("photo", "") or "")[:300],
                        "date": str(d.get("date", "") or "")[:40],
                        "makerId": str(d.get("makerId", "") or "")[:40],
                        "cost": _pint(d.get("cost", 0)),
                        "madeDate": str(d.get("madeDate", "") or "")[:40],
                        "created": now,
                        "updatedAt": now,
                        "updatedBy": who,
                        "updatedByName": who_name,
                    }
                    items.append(item)
                else:
                    for k, ln in (("group", 40), ("category", 60), ("size", 40),
                                  ("note", 400), ("photo", 300), ("date", 40),
                                  ("makerId", 40), ("madeDate", 40)):
                        if k in d:
                            existing[k] = str(d.get(k, "") or "")[:ln]
                    for k in ("qty", "unitPrice", "amount", "cost"):
                        if k in d:
                            existing[k] = _pint(d.get(k, 0))
                    existing["updatedAt"] = now
                    existing["updatedBy"] = who
                    existing["updatedByName"] = who_name
                    item = existing
                doc["purchases"] = items
                order = [str(x) for x in doc.get("purchasesOrder", [])]
                for it in items:
                    if str(it.get("id")) not in order:
                        order.append(str(it.get("id")))
                order = [k for k in order
                         if any(str(it.get("id")) == k for it in items)]
                doc["purchasesOrder"] = order
                cfg = doc.get("config")
                if not isinstance(cfg, dict):
                    cfg = {}
                cfg["purchasesUpdatedAt"] = now
                doc["config"] = cfg
                _merch_save(doc)
                return self._json({"ok": True, "item": item})
            if p == "/api/merch/purchase/delete":
                # 물건 결제 항목 삭제(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                sid = str(d.get("id", "") or "")
                before = len(doc.get("purchases", []))
                doc["purchases"] = [x for x in doc.get("purchases", [])
                                    if str(x.get("id")) != sid]
                doc["purchasesOrder"] = [
                    k for k in doc.get("purchasesOrder", []) if str(k) != sid]
                cfg = doc.get("config")
                if not isinstance(cfg, dict):
                    cfg = {}
                cfg["purchasesUpdatedAt"] = _now_stamp()
                doc["config"] = cfg
                _merch_save(doc)
                return self._json({"ok": True,
                                   "removed": before - len(doc["purchases"])})
            if p == "/api/merch/supplies":
                # 비품 등록/수정(관리자).
                #  - id 없으면 신규. id 있으면 수정.
                #  - 확인자(인가번호/이름)는 세션에서 자동 기록. 별도 override 가능.
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                sid = str(d.get("id", "") or "")
                s = self._sess() or {}
                who = str(s.get("who", "") or "")
                who_name = str(d.get("whoName", "") or s.get("name", "") or "")
                items = doc.get("supplies", [])
                existing = next((x for x in items
                                 if str(x.get("id")) == sid), None) if sid else None
                now = _now_stamp()

                def _sint(v, dv=0):
                    try:
                        return int(v)
                    except Exception:
                        return dv

                if existing is None:
                    item = {
                        "id": sid or ("sp" + _secrets.token_urlsafe(5)),
                        "name": str(d.get("name", "") or "")[:80],
                        "qty": _sint(d.get("qty", 0)),
                        "note": str(d.get("note", "") or "")[:400],
                        "photo": str(d.get("photo", "") or "")[:300],
                        "updatedAt": now,
                        "updatedBy": who,
                        "updatedByName": who_name,
                        "checkedAt": str(d.get("checkedAt", "") or ""),
                        "checkedBy": str(d.get("checkedBy", "") or who),
                        "checkedByName": str(d.get("checkedByName", "") or who_name),
                        "created": now,
                    }
                    items.append(item)
                else:
                    for k in ("name", "note"):
                        if k in d:
                            item_len = 80 if k == "name" else 400
                            existing[k] = str(d.get(k, "") or "")[:item_len]
                    if "photo" in d:
                        existing["photo"] = str(d.get("photo", "") or "")[:300]
                    if "qty" in d:
                        existing["qty"] = _sint(d.get("qty", 0))
                    if "checkedAt" in d:
                        existing["checkedAt"] = str(d.get("checkedAt", "") or "")
                        existing["checkedBy"] = str(
                            d.get("checkedBy", "") or who)
                        existing["checkedByName"] = str(
                            d.get("checkedByName", "") or who_name)
                    existing["updatedAt"] = now
                    existing["updatedBy"] = who
                    existing["updatedByName"] = who_name
                    item = existing
                doc["supplies"] = items
                # suppliesOrder 정합화(누락분 뒤에 추가)
                order = [str(x) for x in doc.get("suppliesOrder", [])]
                for it in items:
                    if str(it.get("id")) not in order:
                        order.append(str(it.get("id")))
                order = [k for k in order
                         if any(str(it.get("id")) == k for it in items)]
                doc["suppliesOrder"] = order
                cfg = doc.get("config")
                if not isinstance(cfg, dict):
                    cfg = {}
                cfg["suppliesUpdatedAt"] = now
                doc["config"] = cfg
                _merch_save(doc)
                return self._json({"ok": True, "item": item})
            if p == "/api/merch/supplies/delete":
                # 비품 삭제(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                sid = str(d.get("id", "") or "")
                before = len(doc.get("supplies", []))
                doc["supplies"] = [x for x in doc.get("supplies", [])
                                   if str(x.get("id")) != sid]
                doc["suppliesOrder"] = [
                    k for k in doc.get("suppliesOrder", []) if str(k) != sid]
                cfg = doc.get("config")
                if not isinstance(cfg, dict):
                    cfg = {}
                cfg["suppliesUpdatedAt"] = _now_stamp()
                doc["config"] = cfg
                _merch_save(doc)
                return self._json({"ok": True,
                                   "removed": before - len(doc["supplies"])})
            if p == "/api/merch/supplies/order":
                # 비품 표시 순서 저장(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                ids = [str(x) for x in (d.get("ids") or [])]
                doc["suppliesOrder"] = ids
                _merch_save(doc)
                return self._json({"ok": True, "count": len(ids)})
            if p == "/api/merch/plan":
                # 기획실 아이템 등록/수정(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                pid = str(d.get("id", "") or "")
                s = self._sess() or {}
                who = str(d.get("who", "") or s.get("who", "") or "")
                who_name = str(d.get("whoName", "") or "")
                plans = doc.get("plans", [])
                existing = next((x for x in plans
                                 if str(x.get("id")) == pid), None) if pid else None
                now = _now_stamp()

                def _i(v, dv=0):
                    try:
                        return int(v)
                    except Exception:
                        return dv

                if existing is None:
                    item = {
                        "id": pid or ("pl" + _secrets.token_urlsafe(5)),
                        "name": str(d.get("name", "") or "")[:80],
                        "photo": str(d.get("photo", "") or "")[:300],
                        "video": str(d.get("video", "") or "")[:300],
                        "desc": str(d.get("desc", "") or "")[:2000],
                        "memo": str(d.get("memo", "") or "")[:1000],
                        "price": _i(d.get("price", 0)),
                        "maker": str(d.get("maker", "") or "")[:80],   # 기획자
                        "submittedAt": str(d.get("submittedAt", "") or ""),  # 기획안 제출일
                        "progress": str(d.get("progress", "") or "")[:200],  # 현재 진행상황
                        "minQty": _i(d.get("minQty", 0)),   # 최소 제작 착수 수량
                        "surveyOpen": d.get("surveyOpen") is True,  # 수요조사 진행 여부
                        "applicants": [],
                        "created": now,
                        "createdBy": who,
                        "createdByName": who_name,
                    }
                    plans.append(item)
                else:
                    for k in ("name", "photo", "video", "desc", "memo", "maker",
                              "submittedAt", "progress"):
                        if k in d:
                            lim = 2000 if k == "desc" else (
                                1000 if k == "memo" else (
                                    300 if k in ("photo", "video") else 200))
                            existing[k] = str(d.get(k, "") or "")[:lim]
                    if "price" in d:
                        existing["price"] = _i(d.get("price", 0))
                    if "minQty" in d:
                        existing["minQty"] = _i(d.get("minQty", 0))
                    if "surveyOpen" in d:
                        existing["surveyOpen"] = d.get("surveyOpen") is True
                    item = existing
                item["updatedAt"] = now
                doc["plans"] = plans
                order = [str(x) for x in doc.get("plansOrder", [])]
                for it in plans:
                    if str(it.get("id")) not in order:
                        order.append(str(it.get("id")))
                order = [k for k in order
                         if any(str(it.get("id")) == k for it in plans)]
                doc["plansOrder"] = order
                _merch_save(doc)
                return self._json({"ok": True, "item": item})
            if p == "/api/merch/plan/delete":
                # 기획 아이템 삭제(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                pid = str(d.get("id", "") or "")
                before = len(doc.get("plans", []))
                doc["plans"] = [x for x in doc.get("plans", [])
                                if str(x.get("id")) != pid]
                doc["plansOrder"] = [
                    k for k in doc.get("plansOrder", []) if str(k) != pid]
                _merch_save(doc)
                return self._json({"ok": True,
                                   "removed": before - len(doc["plans"])})
            if p == "/api/merch/plan/order":
                # 기획실 표시 순서 저장(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                ids = [str(x) for x in (d.get("ids") or [])]
                doc["plansOrder"] = ids
                _merch_save(doc)
                return self._json({"ok": True, "count": len(ids)})
            if p == "/api/merch/survey/apply":
                # 수요조사 사전신청 (누구나 가능 — 로그인 불필요).
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                pid = str(d.get("planId", "") or "")
                plan = next((x for x in doc.get("plans", [])
                             if str(x.get("id")) == pid), None)
                if not plan:
                    return self._json({"ok": False, "error": "plan_not_found"}, 404)
                if plan.get("surveyOpen") is not True:
                    return self._json(
                        {"ok": False, "error": "survey_closed"}, 400)
                name = str(d.get("name", "") or "").strip()[:40]
                if not name:
                    return self._json({"ok": False, "error": "name"}, 400)
                s = self._sess() or {}
                sess_who = re.sub(r"[^0-9]", "", str(s.get("who", "") or ""))
                number = str(d.get("number", "") or "").strip()[:20]
                if not number and sess_who:
                    number = sess_who   # 인가자 로그인 시 인가번호 자동
                phone = str(d.get("phone", "") or "").strip()[:30]
                email = str(d.get("email", "") or "").strip()[:80]
                memo = str(d.get("memo", "") or "").strip()[:300]
                try:
                    quantity = int(d.get("quantity", 1) or 1)
                except Exception:
                    quantity = 1
                if quantity < 1:
                    quantity = 1
                # 인가자/비인가자 구분 — 수품구매와 동일 프로세스.
                #   인가번호 우선, 없으면 전화번호로 비인가(일반)회원 자동 생성.
                #   → 인가번호가 있으면 해당 회원의 수품구매 내역에 자동 연동된다.
                contact_id, contact_type = _merch_resolve_contact(
                    number, phone, name, email)
                contact_id_n = re.sub(r"[^0-9]", "", str(contact_id or ""))
                apps = plan.get("applicants", [])
                if not isinstance(apps, list):
                    apps = []
                # 중복 신청 방지(전화번호 또는 식별번호 기준)
                if phone and any(str(a.get("phone", "")) == phone for a in apps):
                    return self._json(
                        {"ok": False, "error": "duplicate"}, 409)
                ap_id = "ap" + _secrets.token_urlsafe(5)
                apps.append({
                    "id": ap_id,
                    "name": name,
                    "number": number,            # 범스카우트 인가번호(선택)
                    "contactId": contact_id_n,   # 인가번호 또는 자동생성 전화식별번호
                    "contactType": contact_type, # 'member' | 'regular' | ''
                    "phone": phone,
                    "email": email,
                    "memo": memo,
                    "quantity": quantity,        # 신청 수량
                    "at": _now_stamp(),
                    "no": len(apps) + 1,         # 신청 순번
                })
                plan["applicants"] = apps
                # 회원 프로필에 사전신청 부착 → 프로필 수품구매 항목에 노출
                if contact_id_n:
                    _merch_attach_to_member(contact_id_n, ap_id, "survey")
                _merch_save(doc)
                return self._json({"ok": True, "count": len(apps),
                                   "no": len(apps),
                                   "contactId": contact_id_n,
                                   "contactType": contact_type})
            if p == "/api/merch/survey/applicants":
                # 수요조사 신청자 명단 조회.
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                pid = str(d.get("planId", "") or "")
                data = _merch_survey_applicants(doc, pid)
                if data is None:
                    return self._json({"ok": False, "error": "plan_not_found"}, 404)
                return self._json({"ok": True, "survey": data})
            if p == "/api/merch/order/update":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                oid = str(d.get("id", "") or "")
                order = next((x for x in doc.get("orders", [])
                              if str(x.get("id")) == oid), None)
                if not order:
                    return self._json({"ok": False, "error": "not found"}, 404)
                if "paid" in d:
                    order["paid"] = bool(d.get("paid"))
                if "status" in d:
                    newst = str(d.get("status", "") or "")
                    if newst and newst != str(order.get("status", "")):
                        order["status"] = newst
                        hist = order.get("statusHistory")
                        if not isinstance(hist, list):
                            hist = []
                        hist.append({"status": newst, "at": _now_stamp(),
                                     "by": (self._sess() or {}).get("tier", "admin")})
                        order["statusHistory"] = hist
                        # 입금확인/배송완료 시 paid 자동 갱신
                        if newst in ("입금확인",):
                            order["paid"] = True
                if "memo" in d:
                    order["memo"] = str(d.get("memo", "") or "")[:200]
                if "product" in d:
                    nm = str(d.get("product", "") or "").strip()
                    if nm:
                        order["product"] = nm[:80]
                if "size" in d:
                    order["size"] = str(d.get("size", "") or "")[:80]
                if "option" in d:
                    order["option"] = str(d.get("option", "") or "")[:80]
                if "unitPrice" in d:
                    try:
                        order["unitPrice"] = max(0, int(d.get("unitPrice", 0) or 0))
                    except Exception:
                        pass
                if "buyerName" in d:
                    order["buyerName"] = str(d.get("buyerName", "") or "")[:40]
                if "buyerNumber" in d:
                    order["buyerNumber"] = re.sub(
                        r"[^0-9]", "", str(d.get("buyerNumber", "") or ""))
                if "phone" in d:
                    order["phone"] = str(d.get("phone", "") or "")[:20]
                if "email" in d:
                    order["email"] = str(d.get("email", "") or "")[:80]
                if "address" in d:
                    order["address"] = str(d.get("address", "") or "")[:200]
                if "shipMethod" in d:
                    order["shipMethod"] = str(d.get("shipMethod", "") or "")
                if "shipNote" in d:
                    order["shipNote"] = str(d.get("shipNote", "") or "")[:200]
                if "annualFeeAdded" in d:
                    try:
                        order["annualFeeAdded"] = int(d.get("annualFeeAdded", 0) or 0)
                    except Exception:
                        pass
                if "qty" in d:
                    try:
                        order["qty"] = max(1, int(d.get("qty", 1) or 1))
                    except Exception:
                        pass
                # ── 주문(그룹) 부가정보: 배송비·송장·배송사진·수령확인 ──
                if "shipFee" in d:
                    try:
                        order["shipFee"] = max(0, int(d.get("shipFee", 0) or 0))
                    except Exception:
                        pass
                if "invoice" in d:
                    order["invoice"] = str(d.get("invoice", "") or "")[:60]
                if "invoiceCompany" in d:
                    order["invoiceCompany"] = str(d.get("invoiceCompany", "") or "")[:40]
                if "shipPhoto" in d:
                    order["shipPhoto"] = str(d.get("shipPhoto", "") or "")[:300]
                if "shipPhoto2" in d:
                    order["shipPhoto2"] = str(d.get("shipPhoto2", "") or "")[:300]
                if "shipDate" in d:
                    order["shipDate"] = str(d.get("shipDate", "") or "")[:40]
                if "paidDate" in d:
                    order["paidDate"] = str(d.get("paidDate", "") or "")[:40]
                # 구매자 수령확인 (관리자 대행/본인)
                if "received" in d:
                    order["received"] = bool(d.get("received"))
                    if order["received"]:
                        order["receivedAt"] = str(
                            d.get("receivedAt", "") or _now_stamp())[:40]
                    else:
                        order["receivedAt"] = ""
                order["total"] = int(order.get("unitPrice", 0) or 0) * int(order.get("qty", 1) or 1)
                order["grandTotal"] = (order["total"]
                                       + int(order.get("annualFeeAdded", 0) or 0)
                                       + int(order.get("shipFee", 0) or 0))
                order["updated"] = _now_stamp()
                _merch_save(doc)
                return self._json({"ok": True, "order": order})
            if p == "/api/merch/reserve/update":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                rid = str(d.get("id", "") or "")
                rec = next((x for x in doc.get("reservations", [])
                            if str(x.get("id")) == rid), None)
                if not rec:
                    return self._json({"ok": False, "error": "not found"}, 404)
                if "status" in d:
                    newst = str(d.get("status", "") or "")
                    if newst and newst != str(rec.get("status", "")):
                        rec["status"] = newst
                        hist = rec.get("statusHistory")
                        if not isinstance(hist, list):
                            hist = []
                        hist.append({"status": newst, "at": _now_stamp(),
                                     "by": (self._sess() or {}).get("tier", "admin")})
                        rec["statusHistory"] = hist
                if "memo" in d:
                    rec["memo"] = str(d.get("memo", "") or "")[:200]
                if "qty" in d:
                    try:
                        rec["qty"] = max(1, int(d.get("qty", 1) or 1))
                    except Exception:
                        pass
                rec["updated"] = _now_stamp()
                _merch_save(doc)
                return self._json({"ok": True, "reservation": rec})
            if p == "/api/merch/reserve/delete":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                rid = str(d.get("id", "") or "")
                rec = next((x for x in doc.get("reservations", [])
                            if str(x.get("id")) == rid), None)
                doc["reservations"] = [x for x in doc.get("reservations", [])
                                       if str(x.get("id")) != rid]
                _merch_save(doc)
                if rec and rec.get("contactId"):
                    _merch_detach_from_member(rec.get("contactId"), rid, "reservation")
                return self._json({"ok": True})
            if p == "/api/merch/img/upload":
                # 상품 이미지 업로드(multipart 아님: {name, data(base64)}).
                #  저장: 관리자 업로드 폴더 → 상품.image = 저장파일명.
                if not self._require("admin"):
                    return
                raw = self._body()
                d = json.loads(raw or b"{}")
                fname = _safe_name(str(d.get("filename", "") or ""))
                b64 = str(d.get("data", "") or "")
                if not fname or not b64:
                    return self._json({"ok": False, "error": "bad"}, 400)
                import base64 as _b64
                try:
                    blob = _b64.b64decode(b64.split(",")[-1])
                except Exception:
                    return self._json({"ok": False, "error": "decode"}, 400)
                if len(blob) > 30 * 1024 * 1024:
                    return self._json({"ok": False, "error": "too_large"}, 400)
                stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                stored = "pr_" + stamp + "_" + fname
                try:
                    os.makedirs(MERCH_IMG_UPLOAD_DIR, exist_ok=True)
                    with open(os.path.join(MERCH_IMG_UPLOAD_DIR, stored), "wb") as f:
                        f.write(blob)
                except Exception as e:
                    # NAS 폴더가 있으면 그쪽으로 폴백
                    try:
                        NAS.write(MERCH_MAKER_DIR + "/" + stored, blob)
                    except Exception:
                        return self._json({"ok": False, "error": str(e)}, 500)
                return self._json({
                    "ok": True, "file": stored,
                    "url": "/api/merch/img?name=" + urllib.parse.quote(stored)})
            if p == "/api/merch/maker/upload":
                # 제작자 첨부파일 업로드(multipart 아님: {name, data(base64)})
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}") if False else None
                raw = self._body()
                d = json.loads(raw or b"{}")
                fname = _safe_name(str(d.get("filename", "") or ""))
                b64 = str(d.get("data", "") or "")
                if not fname or not b64:
                    return self._json({"ok": False, "error": "bad"}, 400)
                # 주의: do_POST 내부에서 'import base64' 를 쓰면 함수 전체에서
                #  base64 가 로컬로 취급되어 앞쪽 /api/files 핸들러가 깨진다.
                #  전역 import 를 그대로 사용한다.
                try:
                    blob = base64.b64decode(b64.split(",")[-1])
                except Exception:
                    return self._json({"ok": False, "error": "decode"}, 400)
                if len(blob) > 30 * 1024 * 1024:
                    return self._json({"ok": False, "error": "too_large"}, 400)
                stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                stored = f"{stamp}_{fname}"
                try:
                    NAS.write(MERCH_MAKER_DIR + "/" + stored, blob)
                except Exception as e:
                    return self._json({"ok": False, "error": str(e)}, 500)
                return self._json({"ok": True, "file": stored,
                                   "url": "/api/merch/file?name=" + urllib.parse.quote(stored)})
            if p == "/api/merch/maker":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                mid = str(d.get("id", "") or ("mk" + _secrets.token_urlsafe(5)))
                makers = doc.get("makers", [])
                existing = next((x for x in makers if str(x.get("id")) == mid), None)
                fields = ("category", "company", "ceo", "manager", "phone", "email",
                          "madeDate", "unitPrice", "quoteFile", "amount", "paidDate",
                          "shipDate", "photo", "memo", "account", "bizLicenseFile",
                          "bizNumber", "paidAmount")
                item = dict(existing) if existing else {"id": mid,
                                                        "created": _now_stamp()}
                item["id"] = mid
                for k in fields:
                    if k in d:
                        if k in ("unitPrice", "amount", "paidAmount"):
                            try:
                                item[k] = int(d.get(k, 0) or 0)
                            except Exception:
                                item[k] = 0
                        elif k == "extraFiles":
                            item[k] = d.get(k, [])
                        else:
                            item[k] = str(d.get(k, "") or "")[:300]
                # 입금완료 여부(명시적 플래그) — paidDate 만으로도 완료 판정 가능.
                if "paid" in d:
                    item["paid"] = bool(d.get("paid"))
                if "progress" in d and isinstance(d.get("progress"), list):
                    item["progress"] = d.get("progress")
                if "extraFiles" in d and isinstance(d.get("extraFiles"), list):
                    item["extraFiles"] = d.get("extraFiles")
                item["updated"] = _now_stamp()
                if existing:
                    makers[makers.index(existing)] = item
                else:
                    makers.append(item)
                doc["makers"] = makers
                _merch_save(doc)
                return self._json({"ok": True, "maker": item})
            if p == "/api/merch/maker/delete":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                mid = str(d.get("id", "") or "")
                doc["makers"] = [x for x in doc.get("makers", [])
                                 if str(x.get("id")) != mid]
                _merch_save(doc)
                return self._json({"ok": True})
            if p == "/api/merch/donation":
                # 수품 공여(행사/홍보) 기록
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                did = str(d.get("id", "") or ("dn" + _secrets.token_urlsafe(5)))
                don = doc.get("donations", [])
                existing = next((x for x in don if str(x.get("id")) == did), None)
                # 삭제 요청
                if d.get("delete") is True and existing:
                    don.remove(existing)
                    doc["donations"] = don
                    _merch_save(doc)
                    return self._json({"ok": True, "deleted": did})
                item = dict(existing) if existing else {"id": did,
                                                        "created": _now_stamp()}
                item["id"] = did
                # 금액(정수)
                if "amount" in d:
                    try:
                        item["amount"] = int(d.get("amount", 0) or 0)
                    except Exception:
                        item["amount"] = 0
                # 수량(정수)
                if "qty" in d:
                    try:
                        item["qty"] = int(d.get("qty", 0) or 0)
                    except Exception:
                        item["qty"] = 0
                # 텍스트 필드(구/신 필드명 모두 수용)
                text_map = [
                    ("product", ("product", "item")),
                    ("recipient", ("recipient", "target")),
                    ("event", ("event",)),
                    ("date", ("date",)),
                    ("memo", ("memo", "note")),
                ]
                for canon, keys in text_map:
                    for k in keys:
                        if k in d:
                            item[canon] = str(d.get(k, "") or "")[:300]
                            break
                item["updated"] = _now_stamp()
                if existing:
                    don[don.index(existing)] = item
                else:
                    don.append(item)
                doc["donations"] = don
                _merch_save(doc)
                return self._json({"ok": True, "donation": item})
            if p == "/api/merch/stock":
                # 재고 입출고 기록(누적/조정)
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                pid = str(d.get("productId", "") or "")
                delta = 0
                try:
                    delta = int(d.get("delta", 0) or 0)
                except Exception:
                    delta = 0
                prod = next((x for x in doc.get("products", [])
                             if str(x.get("id")) == pid), None)
                if not prod:
                    return self._json({"ok": False, "error": "product_not_found"}, 404)
                try:
                    prod["stock"] = max(0, int(prod.get("stock", 0) or 0) + delta)
                except Exception:
                    prod["stock"] = 0
                log = doc.get("stockLog", [])
                log.insert(0, {"productId": pid, "product": prod.get("name", ""),
                               "delta": delta, "after": prod["stock"],
                               "note": str(d.get("note", "") or "")[:120],
                               "at": _now_stamp()})
                doc["stockLog"] = log[:500]
                _merch_save(doc)
                return self._json({"ok": True, "stock": prod["stock"]})
            if p == "/api/merch/order/delete":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                oid = str(d.get("id", "") or "")
                rec = next((x for x in doc.get("orders", [])
                            if str(x.get("id")) == oid), None)
                before = len(doc.get("orders", []))
                doc["orders"] = [x for x in doc.get("orders", [])
                                 if str(x.get("id")) != oid]
                _merch_save(doc)
                if rec and rec.get("contactId"):
                    _merch_detach_from_member(rec.get("contactId"), oid, "order")
                return self._json({"ok": True, "removed": before - len(doc["orders"])})
            if p == "/api/merch/order/delete-group":
                # 같은 주문번호(orderNo)의 모든 품목을 한 번에 삭제(관리자).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                orderno = str(d.get("orderNo", "") or "").strip()
                if not orderno:
                    return self._json({"ok": False, "error": "orderNo"}, 400)
                victims = [x for x in doc.get("orders", [])
                           if str(x.get("orderNo", "")) == orderno]
                doc["orders"] = [x for x in doc.get("orders", [])
                                 if str(x.get("orderNo", "")) != orderno]
                _merch_save(doc)
                for rec in victims:
                    if rec.get("contactId"):
                        _merch_detach_from_member(rec.get("contactId"),
                                                  rec.get("id"), "order")
                return self._json({"ok": True, "removed": len(victims)})
            if p == "/api/merch/order/receive":
                # 구매자 수령확인 — 본인(세션) 또는 관리자가 지정 주문번호를
                #  '수령완료' 처리한다. ident로 본인 여부 확인.
                if not self._require():
                    return
                d = json.loads(self._body() or b"{}")
                s = self._sess() or {}
                is_admin = s.get("tier") in ("app", "master")
                doc = _merch_doc()
                orderno = str(d.get("orderNo", "") or "").strip()
                oid = str(d.get("id", "") or "").strip()
                targets = [x for x in doc.get("orders", [])
                           if (orderno and str(x.get("orderNo", "")) == orderno)
                           or (oid and str(x.get("id", "")) == oid)]
                if not targets:
                    return self._json({"ok": False, "error": "not_found"}, 404)
                # 권한: 관리자이거나, 세션 신원이 주문자와 일치해야 함
                if not is_admin:
                    sess_who = re.sub(r"[^0-9]", "", str(s.get("who", "")))
                    ok_any = any(_merch_match_ident(x, sess_who) for x in targets)
                    if not sess_who or not ok_any:
                        return self._json(
                            {"ok": False, "error": "unauthorized"}, 403)
                receive = bool(d.get("received", True))
                stamp = _now_stamp()
                for x in targets:
                    x["received"] = receive
                    x["receivedAt"] = stamp if receive else ""
                    # 수령 시 배송완료 상태로 승격(진행중인 경우만)
                    if receive and '취소' not in str(x.get("status", "")):
                        x["status"] = "배송완료"
                        hist = x.get("statusHistory")
                        if not isinstance(hist, list):
                            hist = []
                        hist.append({"status": "배송완료", "at": stamp,
                                     "by": "구매자" if not is_admin else "admin"})
                        x["statusHistory"] = hist
                    x["updated"] = stamp
                _merch_save(doc)
                return self._json({"ok": True, "count": len(targets),
                                   "orders": targets})
            # ---- 주문 일괄편집: 소프트 삭제 / 복원 / 순서변경 / 합치기 ----
            if p == "/api/merch/orders/delete":
                # 선택한 그룹키들(주문번호 또는 B:bundleId)을 소프트 삭제.
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                keys = [str(x) for x in (d.get("keys") or []) if str(x).strip()]
                stamp = _now_stamp()
                n = 0
                victims = []
                for o in doc.get("orders", []):
                    if _merch_group_key(o) in keys:
                        o["deleted"] = True
                        o["deletedAt"] = stamp
                        n += 1
                        victims.append(o)
                for r in doc.get("reservations", []):
                    if _merch_group_key(r) in keys:
                        r["deleted"] = True
                        r["deletedAt"] = stamp
                        n += 1
                        victims.append(r)
                # 삭제 그룹은 순서 배열에서 제거(맨 아래 '삭제됨' 영역에 별도 표시)
                doc["orderOrder"] = [k for k in doc.get("orderOrder", [])
                                     if k not in keys]
                _merch_save(doc)
                return self._json({"ok": True, "count": n})
            if p == "/api/merch/orders/restore":
                # 삭제된 주문 복원(30일 이내).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                keys = [str(x) for x in (d.get("keys") or []) if str(x).strip()]
                n = 0
                for o in doc.get("orders", []):
                    if _merch_group_key(o) in keys and o.get("deleted") is True:
                        o["deleted"] = False
                        o["deletedAt"] = ""
                        n += 1
                for r in doc.get("reservations", []):
                    if _merch_group_key(r) in keys and r.get("deleted") is True:
                        r["deleted"] = False
                        r["deletedAt"] = ""
                        n += 1
                _merch_rebuild_order(doc)
                _merch_save(doc)
                return self._json({"ok": True, "count": n})
            if p == "/api/merch/orders/hard-delete":
                # 삭제된 주문 즉시 영구 삭제(회원 프로필에서도 분리).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                keys = [str(x) for x in (d.get("keys") or []) if str(x).strip()]
                removed = [x for x in doc.get("orders", [])
                           if _merch_group_key(x) in keys]
                doc["orders"] = [x for x in doc.get("orders", [])
                                 if _merch_group_key(x) not in keys]
                doc["orderOrder"] = [k for k in doc.get("orderOrder", [])
                                     if k not in keys]
                _merch_save(doc)
                for rec in removed:
                    if rec.get("contactId"):
                        _merch_detach_from_member(
                            rec.get("contactId"), rec.get("id"), "order")
                return self._json({"ok": True, "removed": len(removed)})
            if p == "/api/merch/orders/order":
                # 표시 순서 저장(드래그 재정렬 결과). keys=최종 순서 배열.
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                keys = [str(x) for x in (d.get("keys") or []) if str(x).strip()]
                if keys:
                    # 누락 그룹은 뒤에 보충
                    allk = []
                    seen = set()
                    for rec in list(doc.get("orders", [])) + \
                            list(doc.get("reservations", [])):
                        if rec.get("deleted") is True:
                            continue
                        k = _merch_group_key(rec)
                        if k not in seen:
                            seen.add(k)
                            allk.append(k)
                    final = [k for k in keys if k in seen]
                    final += [k for k in allk if k not in final]
                    doc["orderOrder"] = final
                _merch_save(doc)
                return self._json({"ok": True, "orderOrder": doc["orderOrder"]})
            if p == "/api/merch/orders/merge":
                # 선택한 주문들을 하나로 '합치기'(묶음배송/추가주문 통합용).
                #  단, 합치더라도 각 주문번호는 그대로 유지 → 주문서에 개별 표기.
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                keys = [str(x) for x in (d.get("keys") or []) if str(x).strip()]
                if len(keys) < 2:
                    return self._json(
                        {"ok": False, "error": "need_2_or_more"}, 400)
                bid = "b" + _secrets.token_urlsafe(5)
                name = str(d.get("name", "") or "").strip()
                hit = 0
                nos = []
                for rec in list(doc.get("orders", [])) + \
                        list(doc.get("reservations", [])):
                    if _merch_group_key(rec) in keys:
                        rec["bundleId"] = bid
                        hit += 1
                        if rec.get("orderNo"):
                            nos.append(str(rec.get("orderNo")))
                if hit == 0:
                    return self._json({"ok": False, "error": "not_found"}, 404)
                if not name:
                    name = "묶음 " + (nos[0] if nos else bid)
                bundle = {"id": bid, "name": name[:60], "orderNos": nos,
                          "created": _now_stamp(),
                          "by": (self._sess() or {}).get("tier", "admin")}
                bundles = doc.get("bundles", [])
                if not isinstance(bundles, list):
                    bundles = []
                bundles.append(bundle)
                doc["bundles"] = bundles
                # 순서 배열에서 개별 키 제거 후 묶음키(B:bid)를 맨 앞에 추가
                bkey = "B:" + bid
                doc["orderOrder"] = [bkey] + [
                    k for k in doc.get("orderOrder", []) if k not in keys]
                _merch_save(doc)
                return self._json({"ok": True, "bundle": bundle,
                                   "count": hit})
            if p == "/api/merch/orders/unmerge":
                # 합친 묶음 해제.
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                bid = str(d.get("bundleId", "") or "").strip()
                if not bid:
                    return self._json({"ok": False, "error": "bundleId"}, 400)
                n = 0
                for rec in list(doc.get("orders", [])) + \
                        list(doc.get("reservations", [])):
                    if str(rec.get("bundleId", "")) == bid:
                        rec["bundleId"] = ""
                        n += 1
                doc["bundles"] = [b for b in doc.get("bundles", [])
                                  if str(b.get("id")) != bid]
                _merch_rebuild_order(doc)
                _merch_save(doc)
                return self._json({"ok": True, "count": n})
            if p == "/api/merch/orders/archive":
                # 30일 초과로 아카이브된(보관) 주문 내역 조회.
                if not self._require("admin"):
                    return
                doc = _merch_doc()
                _merch_purge_deleted(doc)
                _merch_save(doc)
                arch = doc.get("archive", [])
                arch = [a for a in arch if isinstance(a, dict)]
                arch.sort(key=lambda x: str(x.get("_archivedAt", "")),
                          reverse=True)
                return self._json({"ok": True, "archive": arch,
                                   "count": len(arch),
                                   "keepDays": DELETED_KEEP_DAYS})
            if p == "/api/merch/config":
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                doc = _merch_doc()
                cfg = doc.get("config", {})
                if "annualFee" in d:
                    try:
                        cfg["annualFee"] = int(d.get("annualFee", 0) or 0)
                    except Exception:
                        pass
                if "salesOpen" in d:
                    cfg["salesOpen"] = bool(d.get("salesOpen"))
                if "annualFeeRequired" in d:
                    cfg["annualFeeRequired"] = bool(d.get("annualFeeRequired"))
                if "reserveMode" in d:
                    cfg["reserveMode"] = bool(d.get("reserveMode"))
                # 견적서/사업자등록증 파일 열람권한 관리자 허용 여부(마스터만 설정)
                if "makerFileAdminAllowed" in d:
                    cfg["makerFileAdminAllowed"] = bool(
                        d.get("makerFileAdminAllowed"))
                # 견적서 기반 판매상품 세부항목 관리자 노출 허용 여부(마스터만 설정)
                if "quoteSpecAdminAllowed" in d:
                    cfg["quoteSpecAdminAllowed"] = bool(
                        d.get("quoteSpecAdminAllowed"))
                if "notices" in d:
                    cfg["notices"] = str(d.get("notices", "") or "")
                if "statuses" in d and isinstance(d.get("statuses"), list):
                    st = [str(x) for x in d.get("statuses") if str(x).strip()]
                    if st:
                        cfg["statuses"] = st
                if "reserveStatuses" in d and isinstance(d.get("reserveStatuses"), list):
                    st = [str(x) for x in d.get("reserveStatuses") if str(x).strip()]
                    if st:
                        cfg["reserveStatuses"] = st
                if "account" in d and isinstance(d.get("account"), dict):
                    a = cfg.get("account", {})
                    for k in ("bank", "no", "holder"):
                        if k in d["account"]:
                            a[k] = str(d["account"][k] or "")
                    if "shipFee" in d["account"]:
                        try:
                            a["shipFee"] = int(d["account"]["shipFee"] or 0)
                        except Exception:
                            pass
                    cfg["account"] = a
                if "guide" in d and isinstance(d.get("guide"), dict):
                    g = _merch_guide(cfg)
                    for k in ("title", "membership", "rules", "sets", "notes",
                              "formUrl", "formLabel", "payment"):
                        if k in d["guide"]:
                            g[k] = str(d["guide"][k] or "")
                    g["updated"] = _now_stamp()
                    cfg["guide"] = g
                cfg["updated"] = _now_stamp()
                doc["config"] = cfg
                _merch_save(doc)
                return self._json({"ok": True, "config": cfg})
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
            if p == "/api/event/meta":
                # 행사 사용자 정의 '메뉴추가' 탭 저장 (PDF page9 최종 결정).
                if not self._require("admin"):
                    return
                d = json.loads(self._body() or b"{}")
                year = _ev_safe(d.get("year", ""))
                title = _ev_safe(d.get("title", ""))
                if not title:
                    return self._json({"ok": False, "error": "title"}, 400)
                tabs_in = d.get("customTabs")
                with LOCK:
                    doc = _ev_doc()
                    eid = _ev_id(year, title)
                    e = doc.get("events", {}).get(eid)
                    if not e:
                        return self._json({"ok": False, "error": "not found"}, 404)
                    if isinstance(tabs_in, list):
                        clean = []
                        for t in tabs_in[:40]:
                            if not isinstance(t, dict):
                                continue
                            nm = str(t.get("name", "") or "")[:60].strip()
                            if not nm:
                                continue
                            clean.append({
                                "name": nm,
                                "note": str(t.get("note", "") or "")[:4000],
                            })
                        e["customTabs"] = clean
                    _ev_save(doc)
                return self._json({"ok": True, "customTabs": e.get("customTabs", [])})
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
                    e.setdefault("customTabs", [])   # 사용자 정의 메뉴추가 탭
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
                # 회원 프로필(eventAttend) 연동 — 인가자·비인가자 모두 자동 반영.
                try:
                    _ev_link_attendees_to_profiles(
                        d.get("attendees", []), title)
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
                # 회원 프로필(eventAttend) 연동 — 인가자·비인가자 모두 자동 반영.
                if entries:
                    try:
                        _ev_link_attendees_to_profiles(entries, title)
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
