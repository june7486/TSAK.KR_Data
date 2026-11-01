#!/usr/bin/env python3
"""생성된 PDF 의 **페이지별 머리행 반복**을 검증한다 (pypdf 사용).

## 왜 필요한가
앱은 인쇄용 HTML 과 **PDF 파일** 두 경로로 출력한다.
  · HTML  : `print_doc.dart` 의 `thead{display:table-header-group}` (CSS 규격)
  · PDF   : `doc_pdf.dart` 의 **수동 페이지 나눔** (pw.Table 은 canSpan=false 라
            한 행이 페이지를 넘으면 잘린다 → 직접 높이를 재서 나눈다)

CSS 로는 PDF 경로를 증명할 수 없다. 그래서 실제 바이트를 만들어 열어 본다.

## 사용법
    # 1) PDF 생성 (테스트가 build/pdf_check/*.pdf 로 떨군다)
    flutter test test/pdf_page_repeat_test.dart

    # 2) 페이지 검증
    python3 scripts/verify_pdf_pages.py

## 판정 기준
  · 모든 문서가 2페이지 이상일 것 (페이지 나눔이 실제로 일어났는가)
  · **2페이지 이후에도** 열 헤더가 모두 그려질 것 (구분 메뉴 반복)
  · 페이지별 데이터 행 수가 0 이 아닐 것 (빈 페이지/잘림 방지)
"""
import glob
import os
import sys

try:
    import pypdf
except ImportError:
    print("pypdf 가 필요합니다:  pip install pypdf==6.19.0", file=sys.stderr)
    raise SystemExit(1)

HEADERS = ["인가번호", "이름", "연락처", "메일"]
MARKER = "홍길동"  # 데이터 행 표식

# (파일명, 기대 최소 페이지)
CASES = [
    ("roster60", 2),
    ("roster120", 3),
    ("portrait80", 2),
    ("offset", 3),
    ("rowlines1", 2),
    ("rowlines3", 3),
]


def main() -> int:
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    base = os.path.abspath(os.path.join(root, "build", "pdf_check"))
    if not os.path.isdir(base):
        print(f"먼저 테스트를 실행하세요 (없음: {base})", file=sys.stderr)
        return 1

    found = {os.path.splitext(os.path.basename(p))[0] for p in glob.glob(f"{base}/*.pdf")}
    failures = []

    for name, min_pages in CASES:
        if name not in found:
            failures.append(f"{name}: 파일 없음")
            continue
        path = os.path.join(base, f"{name}.pdf")
        try:
            reader = pypdf.PdfReader(path)
        except Exception as e:  # noqa: BLE001
            failures.append(f"{name}: 열기 실패 ({e})")
            continue

        n = len(reader.pages)
        print(f"\n=== {name}.pdf  pages={n}  size={os.path.getsize(path)//1024}KB ===")
        if n < min_pages:
            failures.append(f"{name}: 페이지 {n} < 기대 {min_pages}")

        for i, page in enumerate(reader.pages):
            text = page.extract_text() or ""
            has_all = all(h in text for h in HEADERS)
            rows = text.count(MARKER)
            flag = "OK " if has_all else "★머리행없음"
            print(f"  p{i+1}: header={has_all!s:5} rows={rows:3d} len={len(text):4d} {flag}")
            if not has_all:
                failures.append(f"{name} p{i+1}: 머리행 누락 ({HEADERS})")
            if rows == 0:
                failures.append(f"{name} p{i+1}: 데이터 행 0개 (빈 페이지)")

    print()
    if failures:
        print("❌ 실패:")
        for f in failures:
            print("   -", f)
        return 1
    print(f"✅ 전체 통과 — {len(CASES)}개 문서 모두 2페이지 이후에도 머리행이 반복된다")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
