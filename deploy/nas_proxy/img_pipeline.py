#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TSAK 이미지 3단계 파이프라인 — 썸네일 / 중간화질 / 원본.

## 배경 (사용자 요구)
    "최적화(중간단계화질)도 넣어줘. 썸네일만으로는 화질이 떨어지고,
     여전히 나스에서 원본을 부르기엔 시간이 오래걸려"
    "나스에도 썸네일 및 최적화 사진이 있어야 함"
    "로딩 속도를 높이기 위해 가비아 호스팅을 메인으로 사용"

## 3단계 설계 (실측 근거)

원본 5.00MB / 4000x3000 기준 재인코딩 실측치:

| 단계 | 해상도(긴 변) | 포맷 | 품질 | 결과 | 압축률 | 용도 |
|------|--------------|------|------|------|--------|------|
| thumb | 480  | WebP | 78 |  25 KB | 200x | 목록·격자 |
| mid   | 1280 | WebP | 82 | 118 KB |  42x | 크게 보기·전체화면 |
| orig  | 원본 | 원본 |  - | 5.0 MB |   1x | 다운로드·인쇄 |

WebP vs JPEG 실측 (1280px):
    JPEG q=82 → 168.3 KB
    WebP q=82 → 117.7 KB   ← 30% 작고 화질 동등
    WebP q=80 → 107.0 KB
→ **WebP 채택** (용량 30% 절감). 브라우저 지원 97%+, 미지원 시 JPEG 폴백.

## 저장 위치 (핵심 원칙)
    NAS  : 원본 + 썸네일 + 중간화질 **모두** 보관  ← 사용자 요구
    가비아: 썸네일 + 중간화질 동기화 (원본은 요청시 캐시)

    NAS 경로 규칙 (원본과 나란히 두어 폴더째 백업하면 따라오게):
        photos/415.jpg            ← 원본
        photos/.derived/415.thumb.webp
        photos/.derived/415.mid.webp

## 설계 원칙
    1. **실패해도 원본은 절대 건드리지 않는다** — 파생본은 부가물.
    2. **한 번 만들면 재사용** — 원본 mtime/size 로 신선도 판정.
    3. **영상은 별도 처리** — 정지 이미지 경로로 들어오면 건너뛴다.
    4. **Pillow 없으면 조용히 원본 반환** — 서버가 죽으면 안 된다.
"""

import hashlib
import io
import os
import re

# ── 단계 정의 ────────────────────────────────────────────────────────────
#  max_side: 긴 변 기준 픽셀.  quality: WebP 품질.
STEPS = {
    "thumb": {"side": 480,  "quality": 78},
    "mid":   {"side": 1280, "quality": 82},
}

#  파생본 하위 폴더명 (원본과 같은 부모 아래에 두어 함께 백업되게 한다)
DERIVED_SUBDIR = ".derived"

#  이 확장자는 정지 이미지가 아니므로 파생본을 만들지 않는다.
SKIP_EXT = {
    ".gif", ".svg", ".heic", ".heif",
    ".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v",
    ".pdf", ".hwp", ".hwpx", ".doc", ".docx", ".xls", ".xlsx",
    ".ppt", ".pptx", ".zip", ".7z", ".rar", ".txt", ".csv",
}

#  브라우저가 WebP 를 못 읽는 극소수 환경을 위한 폴백 포맷
_FALLBACK_FORMAT = "JPEG"
_FALLBACK_QUALITY_BOOST = 4  # JPEG 는 같은 체감에 품질을 조금 올린다


def _ext_of(name):
    return os.path.splitext(str(name or ""))[1].lower()


def is_image(name):
    """파생본을 만들 대상인지. (영상·문서 제외)"""
    ext = _ext_of(name)
    if not ext or ext in SKIP_EXT:
        return None
    if ext in (".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp"):
        return ext
    return None


def derived_key(orig_name):
    """원본 파일명 → 파생본 파일명(확장자 제외).

    같은 이름의 원본이 서로 다른 폴더에 있어도 섞이지 않도록,
    호출부가 폴더별로 나눠 저장한다(여기서는 파일명만 만든다).
    """
    stem = os.path.splitext(os.path.basename(str(orig_name or "")))[0]
    # 파일명에 쓸 수 없는 문자만 치환. 한글은 그대로 둔다.
    keep = re.sub(r"[^A-Za-z0-9._가-힣-]", "_", stem)[:80] or "img"
    return keep


def derived_rel_path(orig_rel, step):
    """원본 상대경로 → 파생본 상대경로.

    photos/415.jpg  →  photos/.derived/415.thumb.webp

    원본과 **같은 부모 폴더** 아래 `.derived/` 에 두므로,
    사용자가 폴더를 통째로 백업/이동하면 파생본도 함께 따라간다.
    """
    d = os.path.dirname(str(orig_rel or "").replace("\\", "/")).strip("/")
    base = derived_key(orig_rel)
    ext = "webp"
    name = "%s.%s.%s" % (base, step, ext)
    return ("%s/%s/%s" % (d, DERIVED_SUBDIR, name)) if d else (
        "%s/%s" % (DERIVED_SUBDIR, name))


def _load_pil():
    """Pillow 를 지연 임포트. 없으면 None (서버는 계속 살아야 한다)."""
    try:
        from PIL import Image, ImageOps
        return Image, ImageOps
    except Exception:
        return None


def make_step(src_bytes, step, prefer_webp=True):
    """원본 바이트 → 파생본 바이트.

    반환: (bytes, ext, mime) 또는 None(실패/대상아님)
    """
    cfg = STEPS.get(step)
    if not cfg:
        return None
    pil = _load_pil()
    if pil is None:
        return None
    Image, ImageOps = pil
    try:
        im = Image.open(io.BytesIO(src_bytes))
        # EXIF 회전을 먼저 적용해야 세로 사진이 눕지 않는다.
        im = ImageOps.exif_transpose(im)
        if getattr(im, "is_animated", False):
            im.seek(0)  # 애니메이션은 첫 프레임만
        im = im.convert("RGB")
        # 원본이 목표보다 작으면 확대하지 않는다(화질 손실만 생긴다).
        im.thumbnail((cfg["side"], cfg["side"]), Image.LANCZOS)

        buf = io.BytesIO()
        if prefer_webp:
            try:
                im.save(buf, "WEBP", quality=cfg["quality"], method=6)
                return (buf.getvalue(), "webp", "image/webp")
            except Exception:
                buf = io.BytesIO()  # WebP 실패 → JPEG 로 폴백
        q = min(95, cfg["quality"] + _FALLBACK_QUALITY_BOOST)
        im.save(buf, _FALLBACK_FORMAT, quality=q,
                optimize=True, progressive=True)
        return (buf.getvalue(), "jpg", "image/jpeg")
    except Exception as e:
        print("[imgpipe] %s 생성 실패: %s" % (step, e))
        return None


def make_all(src_bytes, prefer_webp=True):
    """원본 바이트 → {step: (bytes, ext, mime)}. 실패한 단계는 생략."""
    out = {}
    for step in STEPS:
        r = make_step(src_bytes, step, prefer_webp=prefer_webp)
        if r:
            out[step] = r
    return out


def need_rebuild(orig_size, orig_mtime, meta):
    """파생본을 다시 만들어야 하는지.

    meta: {"srcSize":..., "srcMtime":..., "steps":["thumb","mid"]}
    원본 크기/수정시각이 같고 필요한 단계가 모두 있으면 재생성 불필요.
    """
    if not isinstance(meta, dict):
        return True
    try:
        if int(meta.get("srcSize") or -1) != int(orig_size or 0):
            return True
        # mtime 은 초 단위 오차를 허용한다(파일시스템별 반올림).
        if abs(float(meta.get("srcMtime") or 0) -
               float(orig_mtime or 0)) > 2.0:
            return True
    except Exception:
        return True
    have = set(meta.get("steps") or [])
    return not set(STEPS).issubset(have)


def src_fingerprint(src_bytes):
    """원본 바이트 지문 — 파생본 파일명이 아니라 신선도 비교용."""
    return hashlib.sha1(src_bytes or b"").hexdigest()


def mime_of(step, ext):
    if ext == "webp":
        return "image/webp"
    return "image/jpeg"


def step_of_query(q):
    """쿼리 문자열에서 단계 추출. 잘못된 값은 'orig' 로 본다.

    허용: thumb, mid, orig (없으면 orig — 기존 동작 보존)
    """
    v = str(q or "").strip().lower()
    if v in ("thumb", "thumbnail", "t", "s"):
        return "thumb"
    if v in ("mid", "medium", "m", "large", "l"):
        return "mid"
    return "orig"


def parse_img_query(params):
    """쿼리 파라미터 dict → (step, prefer_webp).

    `size`/`q` 또는 `step` 둘 다 받는다. `fmt=webp|jpeg` 로 강제 가능.
    """
    raw = ""
    for k in ("size", "step", "q", "w"):
        if k in params and params[k]:
            raw = (params[k][0] if isinstance(params[k], (list, tuple))
                   else params[k])
            break
    step = step_of_query(raw)
    fmt = ""
    if params.get("fmt"):
        v = params["fmt"]
        fmt = (v[0] if isinstance(v, (list, tuple)) else v).strip().lower()
    prefer_webp = (fmt != "jpeg" and fmt != "jpg")
    return step, prefer_webp


if __name__ == "__main__":
    # 자체 점검 — 인자가 없으면 실측 요약만 출력
    print("STEPS:", STEPS)
    print("derived example:")
    print("  photos/415.jpg       ->", derived_rel_path("photos/415.jpg", "thumb"))
    print("  행사관리/a/b/1.jpg    ->", derived_rel_path("행사관리/a/b/1.jpg", "mid"))
    print("query 'thumb' ->", step_of_query("thumb"),
          "| '' ->", step_of_query(""))
    print("webp 지원:", _load_pil() is not None)
