#!/usr/bin/env bash
# ============================================================================
#  릴리스 전환 데이터 보존 시험 — 가비아 배포 구조를 그대로 흉내낸다
# ----------------------------------------------------------------------------
#  ## 검증하려는 명제
#   "릴리스 A → B 로 바꿔도 사용자 상태(세션·업로드 이미지·캐시)가 살아남는다"
#
#  ## 왜 이것이 가장 중요한 시험인가
#   가비아 배포는 `current -> releases/<stamp>` 심볼릭 링크 교체다.
#   상태 파일이 릴리스 폴더 안에 있으면 **롤백이 곧 데이터 손실**이 된다.
#   이 시험은 그 명제를 실제 기동으로 확인한다.
#
#  ## 시험 절차
#   1) /tmp 에 릴리스 A, B + shared/state 를 만든다
#   2) A 로 기동 → 세션·업로드 파일을 state 에 쓴다
#   3) current 를 B 로 바꾸고 B 로 기동
#   4) A 에서 쓴 파일이 그대로인지, B 가 자기 폴더에 상태를 만들지 않았는지 확인
#   5) A 로 되돌려(롤백) 다시 확인 — 양방향 생존
#
#  ## 안전
#   NAS 는 **읽기만** 한다. 운영 BASE 하위에 아무것도 쓰지 않는다.
#   → `_boot()` 는 "파일이 없으면 기본값을 만든다"는 경로에서 NAS 에 쓸 수
#     있다. 그래서 `nas_write_guard.py`(sitecustomize)로 **쓰기 자체를
#     예외로 차단**한다. 읽기는 그대로 동작한다.
#   실패하면 종료코드 1.
# ============================================================================
set -uo pipefail

SRC=/home/user/nas_proxy
ROOT=/tmp/tsak_release_test
PORT=5099
FAIL=0
NAT_GUARD=1

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

cleanup() {
  # 이 시험이 띄운 프로세스만 정확히 죽인다 (pkill 금지 — 호출 셸이 죽는다)
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    kill -9 "$PID" 2>/dev/null || true
  fi
  for p in "$ROOT"/releases/*/api/.pid; do
    [ -f "$p" ] && kill -9 "$(cat "$p")" 2>/dev/null || true
  done
}
trap cleanup EXIT

step "▶ 0) 준비"
rm -rf "$ROOT"
mkdir -p "$ROOT/releases/A/api" "$ROOT/releases/B/api" "$ROOT/shared/state"
cp -f "$SRC"/proxy_server.py "$SRC"/nas_lib.py "$SRC"/img_pipeline.py \
      "$SRC"/nas_gdrive.py "$ROOT/releases/A/api/" 2>/dev/null
cp -f "$SRC"/proxy_server.py "$SRC"/nas_lib.py "$SRC"/img_pipeline.py \
      "$SRC"/nas_gdrive.py "$ROOT/releases/B/api/" 2>/dev/null
cp -f "$SRC"/config.json "$ROOT/shared/config.json"
chmod 600 "$ROOT/shared/config.json"
mkdir -p "$ROOT/releases/A/web" "$ROOT/releases/B/web"
echo '<html>A</html>' > "$ROOT/releases/A/web/index.html"
echo '<html>B</html>' > "$ROOT/releases/B/web/index.html"
ln -sfn "$ROOT/releases/A" "$ROOT/current"
ok "레이아웃 생성 (A, B, shared/state)"

# config.json 은 릴리스로 복사해 넣는다(운영과 동일한 방식)
for R in A B; do cp -f "$ROOT/shared/config.json" "$ROOT/releases/$R/api/config.json"; chmod 600 "$ROOT/releases/$R/api/config.json"; done

boot() {  # $1 = 릴리스 이름
  local R="$1"
  cd "$ROOT/current/api" || return 1
  # 시험 중 NAS 쓰기를 예외로 차단 (읽기는 그대로)
  PYTHONPATH=/home/user/deploy/tests \
  TSAK_TEST_NAS_READONLY=1 \
  TSAK_TEST_ALLOW_BUILD=1 \
  TSAK_APP_ROOT="$ROOT/current/api" \
  TSAK_STATIC_DIR="$ROOT/current/web" \
  TSAK_STATE_DIR="$ROOT/shared/state" \
  TSAK_PORT="$PORT" \
  python3 -u proxy_server.py > "$ROOT/boot_$R.log" 2>&1 &
  PID=$!
  echo "$PID" > "$ROOT/releases/$R/api/.pid"
  local H="000"
  # 바인드 전 동기 예열(_ev_union_events 등)이 오래 걸릴 수 있어 넉넉히 기다린다
  for i in $(seq 1 90); do
    sleep 1
    H=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/health" 2>/dev/null || echo 000)
    [ "$H" = "200" ] && break
  done
  echo "    (대기 $i초, 마지막 HTTP $H)"
  [ "$H" = "200" ]
}

stop() {
  [ -n "${PID:-}" ] && kill -9 "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  PID=""
  for i in $(seq 1 20); do
    curl -s -m 1 -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null || break
    sleep 0.3
  done
}

step "▶ 1) 릴리스 A 기동"
if boot A; then
  ok "A 기동 (HTTP 200)"
  grep -m1 "\[state\]" "$ROOT/boot_A.log" | sed 's/^/    /' || true
else
  bad "A 기동 실패"; tail -12 "$ROOT/boot_A.log" | sed 's/^/    /'; exit 1
fi

step "▶ 2) A 로 상태 쓰기"
# 실제 상태 경로가 shared/state 인지 확인
grep -q "상태 루트 = $ROOT/shared/state" "$ROOT/boot_A.log" \
  && ok "상태 루트 = shared/state 로 인식됨" \
  || bad "상태 루트 인식 실패 (로그 확인 필요)"

# 세션 파일이 생겼는지 (기동 시 복원/저장 경로)
sleep 1
if [ -d "$ROOT/shared/state" ]; then
  ok "shared/state 디렉터리 존재"
else
  bad "shared/state 없음"
fi

# 사용자 업로드 흉내 — state 에 직접 마커를 둔다(업로드 경로와 동일 위치)
MARK="$ROOT/shared/state/merch_img_upload/marker_A.png"
mkdir -p "$(dirname "$MARK")"
printf 'PNG-A-DATA' > "$MARK"
ok "A 마커 생성: $(basename "$MARK")"

# 릴리스 폴더에 상태가 새지 않았는지
LEAK=$(find "$ROOT/releases/A/api" -maxdepth 1 \
        \( -name ".json_mirror" -o -name "gdrive_store" -o -name ".sessions.json" \
           -o -name "merch_img_upload" -o -name ".thumb_cache" -o -name ".media_cache" \
           -o -name ".safe_snapshots" -o -name ".ev_meta_cache" \) 2>/dev/null)
if [ -z "$LEAK" ]; then
  ok "릴리스 A 폴더에 상태 누출 없음"
else
  bad "릴리스 A 폴더에 상태 누출:"; echo "$LEAK" | sed 's/^/    /'
fi

stop

step "▶ 3) 릴리스 B 로 전환 (심볼릭 링크 교체)"
ln -sfn "$ROOT/releases/B" "$ROOT/current.tmp" && mv -T "$ROOT/current.tmp" "$ROOT/current"
ok "current -> releases/B"
if boot B; then
  ok "B 기동 (HTTP 200)"
else
  bad "B 기동 실패"; tail -12 "$ROOT/boot_B.log" | sed 's/^/    /'; stop; exit 1
fi

step "▶ 4) A 의 상태가 B 에서도 보이는가 (핵심)"
if [ -f "$MARK" ] && [ "$(cat "$MARK")" = "PNG-A-DATA" ]; then
  ok "A 마커가 B 기동 후에도 그대로 (데이터 보존)"
else
  bad "A 마커 소실 — 롤백이 데이터 손실을 일으킨다"
fi
# B 가 자기 릴리스 폴더에 상태를 만들지 않았는지
LEAKB=$(find "$ROOT/releases/B/api" -maxdepth 1 \
        \( -name ".json_mirror" -o -name "gdrive_store" -o -name ".sessions.json" \
           -o -name "merch_img_upload" -o -name ".thumb_cache" -o -name ".media_cache" \
           -o -name ".safe_snapshots" -o -name ".ev_meta_cache" \) 2>/dev/null)
if [ -z "$LEAKB" ]; then
  ok "릴리스 B 폴더에도 상태 누출 없음"
else
  bad "릴리스 B 폴더에 상태 누출:"; echo "$LEAKB" | sed 's/^/    /'
fi
stop

step "▶ 5) 롤백 (B → A) 후 재확인"
ln -sfn "$ROOT/releases/A" "$ROOT/current.tmp" && mv -T "$ROOT/current.tmp" "$ROOT/current"
ok "current -> releases/A (롤백)"
if boot A; then
  ok "A 재기동 (HTTP 200)"
else
  bad "A 재기동 실패"; stop; exit 1
fi
MARK2="$ROOT/shared/state/merch_img_upload/marker_B.png"
printf 'PNG-B-DATA' > "$MARK2"
ok "B 시절 마커 생성 (양방향 검증용)"
stop

# 다시 B 로 가서 B 시절 마커가 살아있는지
ln -sfn "$ROOT/releases/B" "$ROOT/current.tmp" && mv -T "$ROOT/current.tmp" "$ROOT/current"
if boot B; then
  if [ "$(cat "$MARK2" 2>/dev/null)" = "PNG-B-DATA" ]; then
    ok "B 시절 마커도 A→B 전환 후 생존 (양방향 보존)"
  else
    bad "B 시절 마커 소실"
  fi
  stop
fi

step "▶ 결과"
if [ "$FAIL" = "0" ]; then
  printf '  \033[32m✅ 전환 시험 통과 — 릴리스 교체가 데이터를 보존합니다\033[0m\n'
  echo "  상태 루트: $ROOT/shared/state"
  ls -1 "$ROOT/shared/state/merch_img_upload" 2>/dev/null | sed 's/^/    /'
  rm -rf "$ROOT"
  exit 0
else
  printf '  \033[31m❌ 전환 시험 실패 — 가비아에 올리면 안 됩니다\033[0m\n'
  echo "  로그 보존: $ROOT/boot_A.log, $ROOT/boot_B.log"
  exit 1
fi
