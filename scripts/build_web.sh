#!/usr/bin/env bash
# TSAK 웹 릴리즈 빌드 — 빌드 버전 자동 기록 + 서비스워커 캐싱 비활성.
#   사용: bash scripts/build_web.sh
#
# 성능 최적화 옵션(--optimization-level 4 / --no-web-resources-cdn):
#   - 최적화 레벨 4: dart2js 추가 최적화로 main.dart.js 번들 축소
#   - CDN 비활성: canvaskit.wasm 을 외부 gstatic 대신 로컬 /canvaskit/ 에서 서빙
#     (외부 왕복 제거 → 첫 프레임 단축, 오프라인/방화벽 취약성 해소)
set -e
cd "$(dirname "$0")/.."

echo "▶ 빌드 버전 기록..."
python3 scripts/gen_build_info.py

echo "▶ flutter build web (release, sw off, opt4)..."
flutter build web --release --pwa-strategy none \
  --optimization-level 4 \
  --no-wasm-dry-run \
  --no-tree-shake-icons \
  --dart-define=flutter.inspector.structuredErrors=false \
  --dart-define=debugShowCheckedModeBanner=false

echo "✓ 빌드 완료: build/web"
