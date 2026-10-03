#!/usr/bin/env python3
"""빌드 시점 정보를 lib/services/build_info.g.dart 로 기록한다.

용도: 버전 비교(캐시/업데이트 감지) + **표시용 버전 이름 자동 갱신**.

  python3 scripts/gen_build_info.py

기록 항목:
- kBuildStamp/kBuildStampInt : 로컬 시각(Asia/Seoul) 기반 정수 스탬프(YYYYMMDDHHMMSS).
  서버 build/web/version.json 값과 비교해 "다른 빌드"를 감지한다.
- kBuildNumber : **자동 증가 빌드 넘버** = git 커밋 수(rev-list --count HEAD).
  커밋할 때마다 저절로 1씩 늘어난다 → 손으로 올릴 필요 없이 버전 이름이 바뀐다.
- kCommit : 현재 커밋 해시(짧은 7자리). 화면에 변경 여부를 눈으로 확인하는 보조 표식.

(요구) "버전 이름이 변경되지 않는데, 혹시 버그야?"
  → 기존에는 AppConfig.appVersion('1.0.0') 이 상수라 재빌드해도 절대 안 바뀌었다.
    이제 버전 이름 = appVersion + '+' + 빌드넘버(커밋 수) 로 만들어, 커밋만 하면
    화면 버전이 v1.0.0+34 처럼 **자동으로 바뀐다**.
"""
import datetime
import os
import subprocess

try:
    from zoneinfo import ZoneInfo

    now = datetime.datetime.now(ZoneInfo("Asia/Seoul"))
except Exception:  # tzdata 없을 때 폴백
    now = datetime.datetime.now()

stamp = now.strftime("%Y%m%d%H%M%S")
stamp_int = int(stamp)
display = now.strftime("%Y-%m-%d %H:%M")
short = now.strftime("%m-%d %H:%M")

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, ".."))


def _git(*args):
    try:
        return (
            subprocess.check_output(
                ["git", *args], stderr=subprocess.DEVNULL, cwd=root
            )
            .decode()
            .strip()
        )
    except Exception:
        return ""


# 빌드 넘버 = 커밋 수(+1: 현재 작업 포함). 커밋마다 자동 증가한다.
commit_count = _git("rev-list", "--count", "HEAD")
try:
    build_number = int(commit_count) + 1
except Exception:
    build_number = 0

commit_hash = _git("rev-parse", "--short=7", "HEAD") or "local"

out = (
    "// 자동 생성 파일 — scripts/gen_build_info.py 가 빌드 시 갱신합니다.\n"
    "// 직접 수정하지 마세요.\n"
    "const String kBuildStamp = '%s';\n"
    "const int kBuildStampInt = %d;\n"
    "const String kBuildStampKey = 'tsak_build_v';\n"
    "const String kBuildDisplay = '%s';\n"
    "const String kBuildShort = '%s';\n"
    "/// 자동 증가 빌드 넘버(git 커밋 수 + 1) — 커밋마다 1씩 늘어난다.\n"
    "const int kBuildNumber = %d;\n"
    "/// 현재 커밋 해시(짧은 7자리) — 변경 확인용.\n"
    "const String kCommit = '%s';\n"
) % (stamp, stamp_int, display, short, build_number, commit_hash)

path = os.path.abspath(os.path.join(here, "..", "lib", "services", "build_info.g.dart"))
with open(path, "w", encoding="utf-8") as f:
    f.write(out)
print("wrote", path, "->", stamp, "build#", build_number, "commit", commit_hash)
