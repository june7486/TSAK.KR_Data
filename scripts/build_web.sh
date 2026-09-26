#!/usr/bin/env bash
# TSAK 웹 릴리즈 빌드 — 빌드 버전 자동 기록 + 서비스워커 캐싱 비활성.
#   사용: bash scripts/build_web.sh
set -e
cd "$(dirname "$0")/.."

echo "▶ 빌드 버전 기록..."
python3 scripts/gen_build_info.py

echo "▶ flutter build web (release, service worker off)..."
flutter build web --release --pwa-strategy none \
  --dart-define=flutter.inspector.structuredErrors=false \
  --dart-define=debugShowCheckedModeBanner=false

echo "✓ 빌드 완료: build/web"
