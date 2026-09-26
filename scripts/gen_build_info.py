#!/usr/bin/env python3
"""빌드 시점을 lib/services/build_info.g.dart 로 기록한다.

용도: 버전 비교(캐시/업데이트 감지). `flutter build` 직전에 실행한다.
  python3 scripts/gen_build_info.py

- 로컬 시각(Asia/Seoul) 기준.
- 정수형 스탬프(YYYYMMDDHHMMSS)는 서버 /version.json 의 값과 비교한다.
"""
import datetime
import os

try:
    from zoneinfo import ZoneInfo

    now = datetime.datetime.now(ZoneInfo("Asia/Seoul"))
except Exception:  # tzdata 없을 때 폴백
    now = datetime.datetime.now()

stamp = now.strftime("%Y%m%d%H%M%S")
stamp_int = int(stamp)
display = now.strftime("%Y-%m-%d %H:%M")
short = now.strftime("%m-%d %H:%M")

out = (
    "// 자동 생성 파일 — scripts/gen_build_info.py 가 빌드 시 갱신합니다.\n"
    "// 직접 수정하지 마세요.\n"
    "const String kBuildStamp = '%s';\n"
    "const int kBuildStampInt = %d;\n"
    "const String kBuildStampKey = 'tsak_build_v';\n"
    "const String kBuildDisplay = '%s';\n"
    "const String kBuildShort = '%s';\n"
) % (stamp, stamp_int, display, short)

here = os.path.dirname(os.path.abspath(__file__))
path = os.path.abspath(os.path.join(here, "..", "lib", "services", "build_info.g.dart"))
with open(path, "w", encoding="utf-8") as f:
    f.write(out)
print("wrote", path, "->", stamp)
