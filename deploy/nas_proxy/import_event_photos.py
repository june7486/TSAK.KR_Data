#!/usr/bin/env python3
"""범중앙회 기존 홈피 행사사진 일괄 가져오기.

- zip(사진/YYMMDD_행사명/…) 폴더명에서 **연도·행사명**을 도출해 행사 생성.
- 각 행사의 `03_사진+동영상_(업로드가능)` 폴더로 사진 업로드.
- 업로드한 사진의 **썸네일(480px)까지 생성**(앱 규격과 동일).

프록시 서버(proxy_server.py)의 내부 함수(_ev_*, _make_image_thumb2, NAS)를
그대로 재사용해 앱과 100% 동일한 규격으로 저장한다.

사용: python3 import_event_photos.py [--workers N] [--limit N] [--dry]
"""
import argparse
import collections
import io
import os
import re
import sys
import threading
import unicodedata as ud
import zipfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import proxy_server as P  # noqa: E402  (config + NAS 클라이언트 + 헬퍼 재사용)

ZIP = "/home/user/event_photos_raw/범중앙회기존홈피사진.zip"

_lock = threading.Lock()
_stat = collections.Counter()


def fix_name(raw: str) -> str:
    """cp437 로 잘못 해석된 zip 파일명을 원래 UTF-8 한글로 복원."""
    try:
        return ud.normalize("NFC", raw.encode("cp437").decode("utf-8"))
    except Exception:
        return ud.normalize("NFC", raw)


def _yr(yy: int) -> int:
    """2자리 연도 → 4자리 (80~99=1900년대, 00~79=2000년대)."""
    return 1900 + yy if yy >= 80 else 2000 + yy


def parse_event_folder(folder: str):
    """폴더명에서 (연도, 행사명) 도출.

    지원 형식:
      20150208_선배기업탐방…  → 2015
      160112_아타스게더링-광주 → 2016
      2014_상주잼버리          → 2014
      0808_12회한국잼버리      → 2008
      91년노경하-김형회선배    → 1991
    """
    f = folder.strip()
    m = re.match(r"^(\d{8})_+(.+)$", f)          # YYYYMMDD
    if m:
        return m.group(1)[:4], m.group(2).strip()
    m = re.match(r"^(\d{6})_+(.+)$", f)          # YYMMDD
    if m:
        return str(_yr(int(m.group(1)[:2]))), m.group(2).strip()
    m = re.match(r"^((?:19|20)\d{2})_+(.+)$", f)  # YYYY
    if m:
        return m.group(1), m.group(2).strip()
    m = re.match(r"^(\d{4})_+(.+)$", f)          # YYMM
    if m:
        return str(_yr(int(m.group(1)[:2]))), m.group(2).strip()
    m = re.match(r"^(\d{2})[_\-\s]+(.+)$", f)     # YY_…
    if m:
        return str(_yr(int(m.group(1)))), m.group(2).strip()
    m = re.match(r"^(\d{2})년[_\-\s]*(.+)$", f)   # YY년…
    if m:
        return str(_yr(int(m.group(1)))), m.group(2).strip()
    return None, None


def year_of_filename(fname: str):
    """파일명 접두어/포함된 날짜로 연도를 추정(기타 폴더 분류용)."""
    m = re.match(r"^(\d{8})", fname)
    if m:
        return m.group(1)[:4]
    m = re.match(r"^(\d{6})", fname)
    if m:
        return str(_yr(int(m.group(1)[:2])))
    m = re.search(r"((?:19|20)\d{2})", fname)
    if m:
        return m.group(1)
    return None


def collect(zf):
    """{(연도, 행사명): [(zip경로, 파일명), …]} — 이미지 파일만.

    일반 폴더는 폴더명에서 연도·행사명을 도출하고,
    '기타' 폴더는 파일명 날짜로 연도를 나눠 '기타' 행사로 묶는다.
    """
    groups = collections.defaultdict(list)
    for raw in zf.namelist():
        nn = fix_name(raw)
        if "__MACOSX" in nn:
            continue
        parts = nn.split("/")
        if len(parts) != 3 or parts[0] != "사진":
            continue
        folder, fname = parts[1], parts[2]
        if not fname or fname.startswith("."):
            continue
        if P._kind_of(fname) != "image":
            continue
        if folder == "기타":
            y = year_of_filename(fname) or "2013"
            groups[(y, "기타")].append((raw, fname))
        else:
            y, t = parse_event_folder(folder)
            if not y or not t:
                print(f"  [건너뜀] 연도/이름 파싱 실패: {folder}")
                continue
            groups[(y, t)].append((raw, fname))
    return groups


def ensure_event(year, title, meta):
    """events.json 에 행사를 등록(없으면 생성, 있으면 빈 정보만 보강)."""
    with _lock:
        doc = P._ev_doc()
        eid = P._ev_id(year, title)
        e = doc.setdefault("events", {}).setdefault(eid, {})
        e.setdefault("year", year)
        e.setdefault("title", title)
        e.setdefault("period", "")
        e.setdefault("place", "")
        e.setdefault("desc", meta.get("desc", ""))
        e.setdefault("createdBy", "기존홈피 사진 가져오기")
        for k in ("attendees", "fees", "expenses", "requested",
                  "accessLog", "uploaders", "fileTimes", "customTabs"):
            e.setdefault(k, [] if k not in ("uploaders", "fileTimes") else {})
        e["photoCount"] = e.get("photoCount", 0)
        P._ev_save(doc)
        return eid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    zf = zipfile.ZipFile(ZIP)
    groups = collect(zf)
    # 사진 있는 행사만, 사진 수 내림차순
    items = sorted(groups.items(), key=lambda kv: -len(kv[1]))
    print(f"행사 {len(items)}개 / 사진 {sum(len(v) for _, v in items)}장")

    # 1) 행사 일괄 등록 (events.json 1회 읽기 + 1회 쓰기)
    #    - 폴더 생성은 업로드(NAS.write 의 create_parents)가 자동 처리하므로 생략.
    plan = []
    if not args.dry:
        doc = P._ev_doc()
        for (year, title), files in items:
            eid = P._ev_id(year, title)
            e = doc.setdefault("events", {}).setdefault(eid, {})
            e.setdefault("year", year)
            e.setdefault("title", title)
            e.setdefault("period", "")
            e.setdefault("place", "")
            e.setdefault("desc", "")
            e.setdefault("createdBy", "기존홈피 사진 가져오기")
            for k, d in (("attendees", []), ("fees", []), ("expenses", []),
                         ("requested", []), ("accessLog", []),
                         ("uploaders", {}), ("fileTimes", {}),
                         ("customTabs", [])):
                e.setdefault(k, d)
            e["photoCount"] = e.get("photoCount", 0)
        P._ev_save(doc)
    for (year, title), files in items:
        if args.dry:
            print(f"  {year} | {title:40s} | {len(files):4d}장")
            continue
        media = P._ev_sub_dir(year, title, "media")
        plan.append((year, title, media, files))

    if args.dry:
        return

    # 2) 업로드 + 썸네일 (병렬)
    jobs = []
    for year, title, media, files in plan:
        for zpath, fname in files:
            jobs.append((year, title, media, zpath, fname))
    if args.limit:
        jobs = jobs[: args.limit]
    print(f"처리 대상: {len(jobs)}장 (워커 {args.workers})")

    lock = threading.Lock()
    done = [0]

    def work(job):
        year, title, media, zpath, fname = job
        safe = P._safe_name(fname)
        try:
            with zf.open(zpath) as f:
                data = f.read()
            if not data:
                with lock:
                    _stat["empty"] += 1
                return
            # 원본 업로드
            P.NAS.write(f"{media}/{safe}", data)
            # 썸네일 즉석 생성(앱 규격 480px) — 같은 바이트 재사용(추가 읽기 없음)
            try:
                P._make_image_thumb2(data, year, title, safe)
                with lock:
                    _stat["thumb"] += 1
            except Exception as ex:
                with lock:
                    _stat["thumb_fail"] += 1
                print("  thumb fail", safe, ex)
            with lock:
                _stat["ok"] += 1
        except Exception as ex:
            with lock:
                _stat["fail"] += 1
            print("  upload fail", safe, ex)
            return
        with lock:
            done[0] += 1
            if done[0] % 100 == 0 or done[0] == len(jobs):
                print(f"  진행 {done[0]}/{len(jobs)}  "
                      f"(업로드 {_stat['ok']} · 썸네일 {_stat['thumb']} · "
                      f"실패 {_stat['fail']})")

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        list(ex.map(work, jobs))

    # 3) 행사별 사진 수 기록
    counts = collections.Counter()
    for year, title, media, files in plan:
        counts[(year, title)] += len(files)
    with _lock:
        doc = P._ev_doc()
        for (year, title), c in counts.items():
            e = doc.setdefault("events", {}).get(P._ev_id(year, title))
            if e is not None:
                e["photoCount"] = c
        P._ev_save(doc)

    print("\n=== 완료 ===")
    print(f"업로드 {_stat['ok']}  썸네일 {_stat['thumb']}  "
          f"실패 {_stat['fail']}  빈파일 {_stat['empty']}")
    for year, title, media, files in plan:
        print(f"  {year} | {title:40s} | {len(files):4d}장")


if __name__ == "__main__":
    main()
