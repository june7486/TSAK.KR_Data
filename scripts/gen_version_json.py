#!/usr/bin/env python3
"""빌드 후 `build/web/version.json` 에 **앱과 동일한** 빌드 스탬프를 기록한다.

용도: 버전 감지 정확도 향상.

- 앱은 `lib/services/build_info.g.dart` 의 `kBuildStampInt`(빌드 시작 시각)를 갖는다.
- 서버(프록시)가 `main.dart.js` 의 mtime 을 스탬프로 쓰면, 앱 스탬프와 약 75초
  차이가 나서 "같은 빌드"인데도 다르게 보일 수 있다(허용오차 필요).
- 여기서 앱과 **똑같은** 스탬프를 `build/web/version.json` 에 심으면, 프록시가
  그 값을 그대로 내려주어 앱↔서버 스탬프가 정확히 일치한다.
  → 다른 버전(다른 빌드)만 정확히 감지되어 무조건 캐시 재다운로드가 동작한다.

`flutter build web` **이후**에 실행한다(빌드가 build/web 를 갱신하므로).
"""
import json
import os
import re

here = os.path.dirname(os.path.abspath(__file__))
gi = os.path.abspath(os.path.join(here, "..", "lib", "services", "build_info.g.dart"))

txt = open(gi, encoding="utf-8").read()
m = re.search(r"kBuildStampInt\s*=\s*(\d+)", txt)
if not m:
    raise SystemExit("kBuildStampInt 를 build_info.g.dart 에서 찾지 못했습니다")
stamp = m.group(1)
stamp_int = int(stamp)

# 자동 증가 빌드 넘버(커밋 수) — 앱 표시 버전(v1.0.0+NNN)과 일치시킨다.
mb = re.search(r"kBuildNumber\s*=\s*(\d+)", txt)
build_number = mb.group(1) if mb else "0"
mc = re.search(r"kCommit\s*=\s*'([^']*)'", txt)
commit = mc.group(1) if mc else ""

out = os.path.abspath(os.path.join(here, "..", "build", "web", "version.json"))
prev = {}
try:
    prev = json.load(open(out, encoding="utf-8"))
except Exception:
    prev = {}

prev["build_id"] = stamp_int
prev["version"] = str(stamp_int)
prev["build_number"] = build_number
if commit:
    prev["commit"] = commit
prev.setdefault("app_name", "tsak_credential_manager")

os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(prev, f, ensure_ascii=False)
print("wrote", out, "->", stamp)
