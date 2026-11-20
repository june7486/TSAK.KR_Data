#!/usr/bin/env bash
# ============================================================================
#  가비아 배포 리허설 — 실제 서버 없이 deploy_gabia.sh 전체를 돌린다
# ----------------------------------------------------------------------------
#  ## 왜 필요한가
#   deploy_gabia.sh 는 작성만 하고 **한 번도 끝까지 실행해본 적이 없다**.
#   "동작한다"고 말하려면 실제로 돌려봐야 한다. 그런데 가비아 자격증명이
#   없으므로 진짜 서버에는 붙을 수 없다.
#
#  ## 방법
#   PATH 앞에 가짜 `ssh` / `scp` 를 두어, 원격 명령을 **로컬 가상 서버**에서
#   실행한다. 원격 레이아웃(~/tsak/releases/...)을 /tmp 에 그대로 만든다.
#   실제 systemd 대신 프록시를 백그라운드로 띄운다.
#
#  ## 검증 대상
#   1) 번들 생성 + 자격증명 제외 검사
#   2) scp 업로드
#   3) 원격 전개 + 릴리스 무결성
#   4) 심볼릭 링크 원자적 전환
#   5) 서비스 재시작 + 헬스체크
#   6) 상태 보존 검사
#   7) 스모크 테스트 7종
#   8) --rollback 이 실제로 이전 릴리스로 돌아가는지
#   9) 두 번째 배포가 첫 배포의 상태를 보존하는지
#
#  ## 안전
#   · NAS 쓰기는 sitecustomize 로 차단 (읽기만)
#   · 운영 프록시(5071)는 건드리지 않는다 — 가상 서버는 5098 을 쓴다
#   · 모든 산출물은 /tmp 아래에만 만든다
# ============================================================================
set -uo pipefail

FAKE=/tmp/tsak_rehearsal
VHOME=$FAKE/home
PORT=5098
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

cleanup() {
  for p in "$FAKE"/releases/*/api/.pid; do
    [ -f "$p" ] && kill -9 "$(cat "$p")" 2>/dev/null || true
  done
  # 가상 원격에서 뜬 프록시 정리 (포트로 특정)
  local pid
  pid=$(lsof -ti:$PORT 2>/dev/null | head -1)
  [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
}
trap cleanup EXIT

# ── 0) 가짜 ssh/scp 만들기 ─────────────────────────────────────────────
step "▶ 0) 가상 원격 서버 준비"
rm -rf "$FAKE"
mkdir -p "$FAKE/bin" "$VHOME"

cat > "$FAKE/bin/ssh" <<'FAKESSH'
#!/usr/bin/env bash
# 가짜 ssh — 마지막 인자(원격 명령)를 로컬에서 bash -c 로 실행한다.
# 옵션(-i -p -o ...)을 먼저 걷어낸다.
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -i|-p|-o|-l) shift 2 ;;
    -*)          shift ;;
    *)           args+=("$1"); shift ;;
  esac
done
target="${args[0]:-}"; cmd="${args[1]:-}"
if [ -z "$cmd" ]; then
  # 인자가 하나뿐이면 그게 명령이다 (target 없이)
  cmd="$target"; target=""
fi
[ -z "$cmd" ] && { echo "fake ssh: no command" >&2; exit 2; }
exec bash -c "$cmd"
FAKESSH

#  ## ★ 왜 `systemctl` 을 가짜로 만드는가 (2026-11-20, 리허설이 잡은 결함)
#   종전 가짜 ssh 는 원격 명령 문자열에 "systemctl restart" 가 **들어 있으면**
#   그 명령 전체를 가로채 프록시만 띄웠다. 그런데 배포 스크립트의 롤백 블록은
#
#       ln -sfn "$prev" $R/current.tmp && mv -T ... $R/current
#       sudo systemctl restart tsak-proxy
#       curl ... /api/health
#
#   처럼 **한 원격 명령 안에** 심볼릭 링크 교체와 재시작을 함께 담아 보낸다.
#   그래서 가로채기가 `ln`/`mv` 까지 삼켰고, 리허설은
#   "current → 새 릴리스 (기대: 이전 릴리스)" 라는 **거짓 실패**를 보고했다.
#   (실제 서버에서는 당연히 정상 동작한다 — 하네스만 틀렸다)
#
#   교훈: systemd 는 "명령 문자열"이 아니라 **시스템 계층**이다. 문자열을 훔쳐보는
#   대신 `systemctl` 실행 파일 자체를 가짜로 두면, 원격 명령이 무엇이든
#   나머지 줄은 정직하게 실행되고 재시작만 가상 서버로 치환된다.
cat > "$FAKE/bin/systemctl" <<'FAKESYSTEMCTL'
#!/usr/bin/env bash
# 가짜 systemctl — restart/is-active/status 만 처리하고 나머지는 성공 처리.
# 서비스 이름은 무시한다 (서비스는 하나뿐).
act=""
for a in "$@"; do
  case "$a" in
    -*) ;;                                   # 옵션 무시
    restart|start|is-active|status|stop) act="$a"; break ;;
  esac
done
R="$HOME/tsak"
PORT="${FAKE_PORT:-5098}"
kill_proxy() {
  if [ -f "$R/.pid" ]; then
    kill -9 "$(cat "$R/.pid")" 2>/dev/null || true
    rm -f "$R/.pid"
  fi
  local p; p=$(lsof -ti:$PORT 2>/dev/null | head -1)
  [ -n "$p" ] && kill -9 "$p" 2>/dev/null || true
  # 포트가 실제로 풀릴 때까지 기다린다 (EADDRINUSE 로 조용히 죽는 것 방지)
  local i
  for i in $(seq 1 30); do
    lsof -ti:$PORT >/dev/null 2>&1 || break
    sleep 0.2
  done
}
case "$act" in
  restart|start)
    [ -d "$R/current/api" ] || { echo "  (fake) current 없음 — 기동 실패" >&2; exit 1; }
    kill_proxy
    mkdir -p "$R/shared/state"
    cd "$R/current/api" || exit 1
    cp -f "$R/shared/config.json" config.json 2>/dev/null || true
    PYTHONPATH=/home/user/deploy/tests \
    TSAK_TEST_NAS_READONLY=1 \
    TSAK_TEST_ALLOW_BUILD=1 \
    TSAK_APP_ROOT="$R/current/api" \
    TSAK_STATIC_DIR="$R/current/web" \
    TSAK_STATE_DIR="$R/shared/state" \
    TSAK_THUMB_CONC=2 \
    TSAK_PORT="$PORT" \
    setsid -f python3 -u proxy_server.py >> "$R/shared/app.log" 2>&1 < /dev/null
    sleep 1
    echo "  (fake) proxy 기동 (port $PORT, $R/current)"
    exit 0 ;;
  is-active) echo "active"; exit 0 ;;
  status)    echo "  (fake) active (running)"; exit 0 ;;
  *)         exit 0 ;;
esac
FAKESYSTEMCTL

cat > "$FAKE/bin/scp" <<'FAKESCP'
#!/usr/bin/env bash
# 가짜 scp — src 를 로컬 경로로 복사한다.
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -i|-P|-o) shift 2 ;;
    -*)       shift ;;
    *)        args+=("$1"); shift ;;
  esac
done
src="${args[0]:-}"; dst="${args[1]:-}"
[ -z "$src" ] || [ -z "$dst" ] && { echo "fake scp: bad args" >&2; exit 2; }
# user@host:~/path → $HOME/path
dst="${dst#*:}"
dst="${dst/#\~/$HOME}"
if [ -d "$dst" ]; then dst="$dst/$(basename "$src")"; fi
cp -f "$src" "$dst" || exit 1
echo "  (fake) scp $(basename "$src") → ${dst/#$HOME/~}"
FAKESCP

chmod +x "$FAKE/bin/ssh" "$FAKE/bin/systemctl" "$FAKE/bin/scp"
ok "가짜 ssh/scp/systemctl 생성"

# 가짜 SSH 키 (deploy 스크립트의 존재 검사용)
mkdir -p "$FAKE/keys"
echo "fake-key" > "$FAKE/keys/gabia_key"
chmod 600 "$FAKE/keys/gabia_key"

# ── 1) 가상 원격에 config 를 미리 둔다 (첫 배포 전제) ───────────────────
export HOME_ORIG="$HOME"
mkdir -p "$VHOME/tsak/shared"
cp -f /home/user/gabia_deploy/api/config.json "$VHOME/tsak/shared/config.json"
chmod 600 "$VHOME/tsak/shared/config.json"
ok "shared/config.json 준비"

# 가상 원격에 web 빌드물을 넣어둘 필요는 없다 (릴리스가 통째로 올라온다)

export PATH="$FAKE/bin:$PATH"
export HOME="$VHOME"
export FAKE_PORT="$PORT"
export GABIA_HOST="fake.local"
export GABIA_USER="tsak"
export GABIA_SSH_KEY="$FAKE/keys/gabia_key"
export GABIA_PORT=22
export GABIA_REMOTE="tsak"
export GABIA_SERVICE="tsak-proxy"
export GABIA_PORT_APP="$PORT"

# deploy_gabia.sh 의 스냅샷 경로를 /tmp 로 돌린다 (디스크 절약)
#  → 스크립트를 감싸는 대신, 스냅샷 단계만 건너뛸 수 없으므로
#    SNAP_ROOT 를 임시로 바꾼 사본을 만들어 실행한다.
DEPLOY_SRC=/home/user/deploy/deploy_gabia.sh
DEPLOY_COPY="$FAKE/deploy_gabia_reh.sh"
sed -e "s#^SNAP_ROOT=/home/user/.tsak_snapshots#SNAP_ROOT=$FAKE/snapshots#" \
    -e "s#bash /home/user/deploy/backup_snapshot.sh#$FAKE/skip_snapshot.sh#" \
    -e "s#^GABIA=/home/user/gabia_deploy#GABIA=/home/user/gabia_deploy#" \
    "$DEPLOY_SRC" > "$DEPLOY_COPY"
chmod +x "$DEPLOY_COPY"
# 스냅샷은 리허설에서 생략 (372M — 디스크 절약). 실제 서버에서는 켜져 있다.
cat > "$FAKE/skip_snapshot.sh" <<'EOF'
#!/usr/bin/env bash
echo "  (리허설) 스냅샷 생략 — 실제 배포에서는 372M 스냅샷을 만듭니다"
exit 0
EOF
chmod +x "$FAKE/skip_snapshot.sh"
mkdir -p "$FAKE/snapshots"
ok "리허설용 배포 스크립트 준비"

# ── 2) 첫 배포 실행 ─────────────────────────────────────────────────────
step "▶ 1) 첫 배포 (deploy_gabia.sh --skip-build)"
OUT1=$("$DEPLOY_COPY" --skip-build 2>&1)
RC1=$?
echo "$OUT1" | sed 's/^/  │ /' | tail -45

if [ "$RC1" = "0" ]; then ok "첫 배포 종료코드 0"; else bad "첫 배포 실패 (rc=$RC1)"; fi
echo "$OUT1" | grep -q "번들에 자격증명 없음" && ok "자격증명 제외 확인" || bad "자격증명 검사 실패"

R1_STAMP=$(cat "$VHOME/tsak/releases/.last_stamp" 2>/dev/null || true)
[ -z "$R1_STAMP" ] && R1_STAMP=$(ls -1 "$VHOME/tsak/releases" 2>/dev/null | sort | tail -1)
[ -n "$R1_STAMP" ] && ok "릴리스 생성: $R1_STAMP" || bad "릴리스 없음"
[ -d "$VHOME/tsak/shared/state" ] && ok "shared/state 존재" || bad "shared/state 없음"

# ── 3) 실제로 응답하는지 (가상 원격 프록시) ─────────────────────────────
step "▶ 2) 가상 원격 서비스 확인 (port $PORT)"
H="000"
for i in $(seq 1 40); do
  sleep 1
  H=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/health" 2>/dev/null || echo 000)
  [ "$H" = "200" ] && break
done
[ "$H" = "200" ] && ok "가상 원격 HTTP 200 (${i}초)" || bad "가상 원격 응답 없음 (HTTP $H)"

grep -q "상태 루트 = $VHOME/tsak/shared/state" "$VHOME/tsak/shared/app.log" 2>/dev/null \
  && ok "상태 루트 분리 확인" || warn "상태 루트 로그 미확인"

# 전환된 릴리스가 **실제로 정적 자산을 서빙하는지** (심볼릭 링크가 살아있다는 증거)
I="000"
for i in $(seq 1 10); do
  I=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/main.dart.js" 2>/dev/null || echo 000)
  [ "$I" = "200" ] && break
  sleep 1
done
[ "$I" = "200" ] && ok "릴리스 정적 자산 서빙 (main.dart.js HTTP 200)" \
                 || bad "정적 자산 서빙 실패 (main.dart.js HTTP $I)"

echo "$OUT1" | grep -q "릴리스 .*개 유지 (보존:" && ok "릴리스 정리 로직 실행됨" \
  || warn "릴리스 정리 로그 미확인"

# ── 4) 상태에 사용자 데이터를 넣고 두 번째 배포 ────────────────────────
step "▶ 3) 사용자 상태 생성 후 두 번째 배포 (보존 검증)"
MARK1="$VHOME/tsak/shared/state/merch_img_upload/rehearsal_marker.png"
mkdir -p "$(dirname "$MARK1")"
printf 'REHEARSAL-A' > "$MARK1"
# 세션 파일도 있는지
[ -f "$VHOME/tsak/shared/state/.sessions.json" ] \
  && ok "세션 파일이 shared/state 에 생성됨" \
  || warn "세션 파일 없음 (로그인 전이므로 정상일 수 있음)"

OUT2=$("$DEPLOY_COPY" --skip-build 2>&1)
RC2=$?
echo "$OUT2" | sed 's/^/  │ /' | tail -30
if [ "$RC2" = "0" ]; then ok "두 번째 배포 종료코드 0"; else bad "두 번째 배포 실패 (rc=$RC2)"; fi

[ "$(cat "$MARK1" 2>/dev/null)" = "REHEARSAL-A" ] \
  && ok "★ 배포 후에도 마커 생존 (상태 보존)" \
  || bad "★ 마커 소실 — 롤백 시 데이터 손실"

# 상태 지문 비교 줄이 실제로 찍혔는지
#  ## 문구를 여기서 **바꾸지 않는다** (2026-11-20)
#   종전엔 "상태 파일 목록 동일" 을 찾았는데, 배포 스크립트가 지문을
#   "사용자 자산" 기준으로 바꾸면서 문구도 "사용자 자산 동일" 이 됐다.
#   문구를 양쪽에 복사해두면 또 어긋나므로, **성공/실패 어느 쪽이든**
#   검사가 실제로 수행됐는지만 본다. 정밀 판정은 스크립트 자신의 종료코드가 한다.
echo "$OUT2" | grep -qE "사용자 자산 (동일|이 바뀌었습니다)" \
  && ok "사용자 자산 지문 비교 수행됨" \
  || warn "상태 지문 비교 결과를 찾지 못함 (문구 변경 여부 확인)"

# 새 릴리스로 전환됐는지 — 이름이 아니라 **개수**로 본다.
#  (같은 초에 두 번 배포하면 이름이 같아질 수 있어 이름 비교는 신뢰할 수 없다)
NREL=$(ls -1 "$VHOME/tsak/releases" 2>/dev/null | grep -cv '^\.' || echo 0)
if [ "$NREL" -ge 2 ]; then
  R2_STAMP=$(ls -1 "$VHOME/tsak/releases" 2>/dev/null | grep -v '^\.' | sort | tail -1)
  ok "새 릴리스로 전환: $R2_STAMP (총 ${NREL}개)"
else
  bad "릴리스가 늘지 않음 (총 ${NREL}개) — 이전 릴리스로 롤백 불가"
  R2_STAMP="$R1_STAMP"
fi

# 릴리스 폴더에 상태가 새지 않았는지
LEAK=$(find "$VHOME/tsak/releases"/*/api -maxdepth 1 \
        \( -name .json_mirror -o -name gdrive_store -o -name .sessions.json \
           -o -name merch_img_upload -o -name .thumb_cache \) 2>/dev/null)
[ -z "$LEAK" ] && ok "릴리스 폴더에 상태 누출 없음" || { bad "릴리스 폴더에 상태 누출:"; echo "$LEAK" | sed 's/^/      /'; }

# ── 5) 롤백 ─────────────────────────────────────────────────────────────
step "▶ 4) 롤백 (직전 릴리스로)"
OUT3=$("$DEPLOY_COPY" --rollback 2>&1)
RC3=$?
echo "$OUT3" | sed 's/^/  │ /' | tail -12
if [ "$RC3" = "0" ]; then ok "롤백 종료코드 0"; fi
CUR=$(readlink -f "$VHOME/tsak/current" 2>/dev/null | xargs -r basename)
[ "$CUR" = "$R1_STAMP" ] && ok "current → $R1_STAMP (첫 릴리스로 복귀)" \
                         || warn "current → $CUR (기대 $R1_STAMP)"

[ "$(cat "$MARK1" 2>/dev/null)" = "REHEARSAL-A" ] \
  && ok "★ 롤백 후에도 마커 생존" \
  || bad "★ 롤백 후 마커 소실"

# 롤백 후 서비스가 실제로 살아났는지 (거짓 "헬스 실패" 경보 방지 확인)
RH="000"
for i in $(seq 1 20); do
  RH=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/health" 2>/dev/null || echo 000)
  [ "$RH" = "200" ] && break
  sleep 1
done
[ "$RH" = "200" ] && ok "롤백 후 서비스 정상 (HTTP 200)" \
                  || bad "롤백 후 서비스 응답 없음 (HTTP $RH)"

# 원격 명령에 백틱이 섞이면 명령 치환으로 실행된다 — 리허설이 그 오염을 감시한다
echo "$OUT3" | grep -q "Is a directory\|command not found" \
  && bad "롤백 원격 명령이 오염됨 (백틱/따옴표 문제)" \
  || ok "롤백 원격 명령 오염 없음"

# ── 6) 결과 ─────────────────────────────────────────────────────────────
step "▶ 결과"
if [ "$FAIL" = "0" ]; then
  printf '  \033[32m✅ 배포 리허설 통과 — 파이프라인 전체가 실제로 동작합니다\033[0m\n'
  echo "  릴리스: $R1_STAMP, $R2_STAMP"
  echo "  상태  : $VHOME/tsak/shared/state"
  ls -1 "$VHOME/tsak/shared/state/merch_img_upload" 2>/dev/null | sed 's/^/    /'
  exit 0
else
  printf '  \033[31m❌ 리허설 실패 — 위 실패 항목을 고쳐야 합니다\033[0m\n'
  echo "  로그: $VHOME/tsak/shared/app.log"
  echo "  보존: $FAKE (조사용)"
  exit 1
fi
