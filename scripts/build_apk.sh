#!/usr/bin/env bash
# TSAK 안드로이드 릴리즈 APK 빌드.
#
# ⚠️ 중요: 안드로이드에서는 상대경로 API 호출이 불가하므로
#    반드시 SERVER_BASE(절대 URL) 를 주입해야 데이터를 불러올 수 있다.
#
# 사용:
#   bash scripts/build_apk.sh                                   # 테스트(샌드박스 주소)
#   SERVER_BASE=https://tsak.kr bash scripts/build_apk.sh       # 운영(가비아 도메인)
set -e
cd "$(dirname "$0")/.."

SB="${SERVER_BASE:-https://5071-i0wgdg3il1ohzxyvietj8-0e616f0a.sandbox.novita.ai}"
echo "▶ 서버 주소(SERVER_BASE): $SB"
[ -z "$SB" ] && { echo "❌ SERVER_BASE 가 비어 있습니다. 절대 URL 을 지정하세요."; exit 1; }

python3 scripts/gen_build_info.py || true

echo "▶ flutter build apk (release)..."
flutter build apk --release --dart-define=SERVER_BASE="$SB"

echo "✓ APK: build/app/outputs/flutter-apk/app-release.apk"
