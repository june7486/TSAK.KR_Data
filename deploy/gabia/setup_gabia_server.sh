#!/usr/bin/env bash
# ============================================================================
#  TSAK 가비아 서버 최초 세팅 — 한 번만 실행
# ----------------------------------------------------------------------------
#  전제: deploy_gabia.sh 로 첫 릴리스가 이미 올라가 있어야 한다.
#    ~/<REMOTE>/current -> releases/<stamp>/   (심볼릭 링크)
#
#  이 스크립트가 하는 일
#    1) 파이썬 확인 (표준 라이브러리만 쓰므로 pip 불필요)
#    2) systemd 유닛 등록 — 릴리스 전환을 따라가도록 current 경로를 참조
#    3) nginx 리버스프록시 (80/443 → 127.0.0.1:5071)
#    4) 로그 로테이션
#
#  ## 핵심 1: systemd 가 releases/<stamp> 를 직접 가리키면 안 된다
#   롤백은 심볼릭 링크만 바꾸는 방식이므로, 유닛이 `current` 를 참조해야
#   링크 교체 + restart 만으로 이전 릴리스로 돌아간다.
#   (stamp 경로를 박으면 롤백 때 유닛을 고쳐야 한다 = 롤백이 느리고 위험해진다)
#
#  ## 핵심 2: 코드 경로와 상태 경로를 **반드시 분리**한다
#     TSAK_APP_ROOT  = $APP_LINK/api        (릴리스마다 바뀐다)
#     TSAK_STATE_DIR = $REMOTE_ROOT/shared/state  (릴리스와 무관하게 영속)
#
#   분리하지 않으면 세션·업로드 이미지·캐시가 릴리스 폴더 안에 갇힌다.
#   그러면 **롤백이 곧 데이터 손실**이 된다.
#   (시험: deploy/tests/test_release_switch.sh — A→B→A 전환 후에도 생존 확인)
#
#  사용 (서버에서)
#    TSAK_REMOTE=tsak TSAK_PORT=5071 sudo -E bash setup_gabia_server.sh
#
#  옵션
#    --dry-run     systemd/nginx 에 **아무것도 쓰지 않는다**. 점검만.
#                  (샌드박스에서 실수로 유닛을 등록하는 사고를 막는다)
# ============================================================================
set -uo pipefail

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $a"; exit 2 ;;
  esac
done

REMOTE_DIR="${TSAK_REMOTE:-tsak}"
PORT="${TSAK_PORT:-5071}"
SVC_USER="${TSAK_USER:-$(id -un)}"
SVC_NAME="${TSAK_SERVICE:-tsak-proxy}"
HOME_DIR="${HOME}"
REMOTE_ROOT="$HOME_DIR/$REMOTE_DIR"
APP_LINK="$REMOTE_ROOT/current"
STATIC="$APP_LINK/web"
APIDIR="$APP_LINK/api"
STATE="$REMOTE_ROOT/shared/state"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ── 드라이런: 시스템 변경을 **실행하지 않고 보여주기만** 한다 ─────────
#  ## 왜 함수 오버라이드가 아니라 래퍼인가
#   이 스크립트는 `$SUDO systemctl ...` 처럼 sudo 를 거쳐 호출한다.
#   sudo 는 **바이너리를 PATH 에서 찾으므로** 셸 함수 오버라이드가 통하지
#   않는다. 그래서 호출 지점을 전부 run()/write_file() 로 바꿨다.
#   (샌드박스에서 실수로 유닛을 등록한 사고가 있어 확실한 방식으로 바꿈)
run() {  # 시스템 변경 명령
  if [ "$DRY" = "1" ]; then
    echo "      [dry] $*"
    return 0
  fi
  $SUDO "$@"
}
run_nosudo() {  # sudo 없이 실행하는 명령(systemctl is-active 등)
  if [ "$DRY" = "1" ]; then
    echo "      [dry] $*"
    return 0
  fi
  "$@"
}
write_file() {  # $1=경로, stdin=내용
  if [ "$DRY" = "1" ]; then
    echo "      [dry] 파일 작성: $1"
    cat >/dev/null
    return 0
  fi
  $SUDO tee "$1" >/dev/null
}

SUDO=""
[ "$(id -u)" != "0" ] && SUDO="sudo"

step "▶ 0) 전제 확인"
[ -L "$APP_LINK" ] || { err "$APP_LINK 심볼릭 링크가 없습니다. deploy_gabia.sh 를 먼저 실행하세요."; exit 1; }
ok "current -> $(readlink -f "$APP_LINK")"
[ -f "$APIDIR/proxy_server.py" ] || { err "proxy_server.py 없음"; exit 1; }
ok "프록시 파일 존재"
[ -d "$STATIC" ] || { err "web 디렉터리 없음"; exit 1; }
ok "web 파일 $(find "$STATIC" -type f | wc -l)개"
echo "  python3: $(python3 -V 2>&1)"

# ── 상태 디렉터리 (코드와 분리) ────────────────────────────────────────
step "▶ 0-b) 영속 상태 디렉터리"
mkdir -p "$STATE" || { err "상태 디렉터리 생성 실패: $STATE"; exit 1; }
chmod 700 "$STATE" 2>/dev/null || true
# 실제로 쓸 수 있는지 (서비스 계정 권한으로)
if [ "$(id -un)" != "$SVC_USER" ]; then
  if sudo -u "$SVC_USER" test -w "$STATE" 2>/dev/null; then
    ok "쓰기 가능 ($SVC_USER)"
  else
    warn "$SVC_USER 가 $STATE 에 쓸 수 없습니다 — 권한 조정 필요"
    echo "      sudo chown -R $SVC_USER:$SVC_USER $(dirname "$STATE")"
  fi
else
  [ -w "$STATE" ] && ok "쓰기 가능" || warn "쓰기 불가"
fi
ok "상태 루트: $STATE"
echo "  (릴리스와 분리 → 릴리스 교체·롤백에도 세션/업로드/캐시 보존)"

step "▶ 1) systemd 유닛 등록 ($SVC_NAME)"
write_file /etc/systemd/system/$SVC_NAME.service <<EOF
[Unit]
Description=TSAK 인가자 관리 (Flutter web + API)
Documentation=https://tsak.kr
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SVC_USER
WorkingDirectory=$APIDIR
# ── 릴리스 전환을 따라간다 ──────────────────────────────────────────
#  current 는 심볼릭 링크다. 롤백 = 링크 교체 + restart.
Environment=TSAK_APP_ROOT=$APIDIR
Environment=TSAK_STATIC_DIR=$STATIC
Environment=TSAK_PORT=$PORT
# ── ★ 상태는 릴리스 밖에 둔다 ★ ────────────────────────────────────
#  이 줄이 없으면 세션·업로드 이미지·캐시가 releases/<stamp>/api 안에
#  갇혀서, 릴리스를 바꾸는 순간(또는 롤백하는 순간) 전부 사라진다.
Environment=TSAK_STATE_DIR=$STATE
# 로컬 DB 모드를 쓰려면 아래 주석을 해제 (DB JSON 을 가비아 디스크에서 처리)
#Environment=TSAK_LOCAL_DB=1
#Environment=TSAK_LOCAL_DB_DIR=$STATE/local_db_store
ExecStart=/usr/bin/env python3 -u proxy_server.py
Restart=always
RestartSec=3
StandardOutput=append:$REMOTE_ROOT/shared/app.log
StandardError=append:$REMOTE_ROOT/shared/app.log

# 보안 강화
NoNewPrivileges=true
PrivateTmp=true
# 상태 디렉터리만 쓰기 허용 (나머지 파일시스템은 읽기 전용)
ReadWritePaths=$STATE $REMOTE_ROOT/shared
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF
ok "유닛 작성"

run systemctl daemon-reload
run systemctl enable "$SVC_NAME" >/dev/null 2>&1
ok "자동 시작 등록"

if [ "$DRY" = "1" ]; then
  # 드라이런에서는 서비스를 띄우지 않으므로 헬스체크도 하지 않는다.
  #  (띄우지 않았는데 포트를 찔러 보면, 그 포트에서 이미 도는 **다른**
  #   프로세스가 200 을 돌려줘 "성공"으로 오판한다 — 실제로 겪음)
  warn "DRY-RUN: 서비스 기동/헬스체크 생략 (실제 서버에서 실행하세요)"
  echo "      기대 유닛 설정:"
  echo "        TSAK_APP_ROOT=$APIDIR"
  echo "        TSAK_STATIC_DIR=$STATIC"
  echo "        TSAK_STATE_DIR=$STATE"
  echo "        TSAK_PORT=$PORT"
else
  run systemctl restart "$SVC_NAME"
  sleep 3
  if run_nosudo systemctl is-active --quiet "$SVC_NAME"; then
    ok "서비스 실행 중"
  else
    err "서비스 실패 — 로그:"
    run_nosudo journalctl -u "$SVC_NAME" -n 25 --no-pager | sed 's/^/    /'
    exit 1
  fi

  # 상태 분리가 실제로 적용됐는지 **로그로 확인**한다.
  #  (조용히 릴리스 폴더에 상태를 만들면 나중에 롤백할 때 데이터를 잃는다)
  if run_nosudo journalctl -u "$SVC_NAME" -n 80 --no-pager 2>/dev/null \
       | grep -q "상태 루트 = $STATE"; then
    ok "상태 루트 분리 확인 ($STATE)"
  else
    warn "상태 루트 분리 로그를 찾지 못했습니다 — journalctl 로 확인하세요"
    echo "      sudo journalctl -u $SVC_NAME -n 80 | grep '\\[state\\]'"
  fi
fi

step "▶ 2) 로컬 헬스체크"
if [ "$DRY" = "1" ]; then
  warn "DRY-RUN: 헬스체크 생략 (포트 $PORT 에서 도는 다른 프로세스를 오인하지 않도록)"
else
  H="000"
  for i in $(seq 1 10); do
    sleep 2
    H=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/health" 2>/dev/null || echo 000)
    [ "$H" = "200" ] && break
  done
  if [ "$H" = "200" ]; then
    ok "HTTP 200"
    curl -s -m 5 "http://127.0.0.1:$PORT/api/health" | head -c 200 | sed 's/^/    /'; echo
  else
    err "헬스체크 실패 (HTTP $H)"; exit 1
  fi
fi

step "▶ 3) nginx 리버스프록시"
if ! command -v nginx >/dev/null 2>&1; then
  warn "nginx 없음 — 설치: sudo apt-get install -y nginx"
else
  write_file /etc/nginx/sites-available/tsak <<EOF
server {
    listen 80;
    server_name _;

    # 업로드 상한 (추모관 영상 500MB)
    client_max_body_size 512M;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering off;          # 영상 스트리밍(Range) 지연 방지
    }
}
EOF
  run ln -sf /etc/nginx/sites-available/tsak /etc/nginx/sites-enabled/tsak
  [ -e /etc/nginx/sites-enabled/default ] && run rm -f /etc/nginx/sites-enabled/default
  if $SUDO nginx -t 2>&1 | grep -q "successful" || [ "$DRY" = "1" ]; then
    run systemctl reload nginx
    ok "nginx 적용 (80 → 127.0.0.1:$PORT)"
    echo "  다음: 도메인 연결 후 certbot 으로 443 활성화"
    echo "        sudo apt-get install -y certbot python3-certbot-nginx"
    echo "        sudo certbot --nginx -d tsak.kr -d www.tsak.kr"
  else
    err "nginx 설정 오류:"
    $SUDO nginx -t 2>&1 | sed 's/^/    /'
  fi
fi

step "▶ 4) 로그 로테이션"
write_file /etc/logrotate.d/tsak <<EOF
$HOME_DIR/$REMOTE_DIR/shared/app.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    copytruncate
}
EOF
ok "일별 14개 보관"

echo
echo "✅ 서버 세팅 완료"
echo "   상태 : sudo systemctl status $SVC_NAME"
echo "   로그 : sudo journalctl -u $SVC_NAME -f"
echo "   파일 : $HOME_DIR/$REMOTE_DIR/shared/app.log"
echo "   롤백 : 로컬에서  bash deploy/deploy_gabia.sh --rollback"
