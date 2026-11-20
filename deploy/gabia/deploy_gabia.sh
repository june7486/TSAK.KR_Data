#!/usr/bin/env bash
# ============================================================================
#  TSAK 가비아 자동 배포 — 빌드 → 검증 → 원자적 전환 → 자동 롤백
# ----------------------------------------------------------------------------
#  ## 요구 (사용자)
#   "프로그램은 업데이트시 자동으로 너가 가비아에 업로드 가능하도록 설계해줘"
#   "만약을 위해 다시 롤백할 수 있도록 백업 안전장치 두는 것을 잊지 말고"
#
#  ## 설계 원칙 (실패를 전제로 만든다)
#   1) **되돌릴 지점을 먼저 만든다** — 업로드 전에 스냅샷.
#   2) **한 번에 하나씩 바꾼다** — web 교체와 api 교체를 분리.
#   3) **원자적 전환** — 원격에서도 `ln -sfn` 로 심볼릭 링크만 바꾼다.
#      (파일을 덮어쓰면 그 사이 반쯤 섞인 상태가 사용자에게 노출된다)
#   4) **검증 실패 시 자동 롤백** — 헬스체크가 실패하면 이전 릴리스로 되돌린다.
#   5) **전체 번들 전송** — 원격 증분 삭제는 "빌드에 없는 파일"을 지운다.
#      build/web 는 gzip 15MB 라 전체 전송이 현실적이다. 안전이 우선.
#   6) **자격증명은 환경변수만** — 스크립트·명령행·git 에 절대 남기지 않는다.
#
#  ## 원격 레이아웃 (릴리스 단위)
#     $REMOTE/releases/<stamp>/api/
#     $REMOTE/releases/<stamp>/web/
#     $REMOTE/current -> releases/<stamp>     ← 이 링크만 바꾼다
#     $REMOTE/shared/config.json              ← 릴리스와 분리(자격증명 보존)
#     $REMOTE/shared/state/                   ← 릴리스와 분리(★사용자 상태★)
#
#  ## ★ 왜 shared/state 가 반드시 필요한가
#   상태(세션·업로드 이미지·캐시)가 릴리스 폴더 안에 있으면 릴리스를 바꾸는
#   순간 전부 사라진다. **롤백이 곧 데이터 손실**이 된다.
#   그래서 유닛은 TSAK_STATE_DIR=shared/state 를 쓰고, 이 스크립트는
#   전환 전후로 상태가 그대로인지 검사한다.
#   (근거 시험: deploy/tests/test_release_switch.sh)
#
#  ## 사용
#     export GABIA_HOST=... GABIA_USER=... GABIA_SSH_KEY=~/.ssh/gabia_key
#     bash deploy/deploy_gabia.sh              # 전체 (빌드 포함)
#     bash deploy/deploy_gabia.sh --skip-build # 빌드 산출물 재사용
#     bash deploy/deploy_gabia.sh --dry-run    # 업로드 없이 점검만
#     bash deploy/deploy_gabia.sh --rollback   # 원격을 직전 릴리스로 되돌림
# ============================================================================
set -uo pipefail

# ── 설정 ────────────────────────────────────────────────────────────────
APP=/home/user/flutter_app
GABIA=/home/user/gabia_deploy
PROXY=/home/user/nas_proxy
SNAP_ROOT=/home/user/.tsak_snapshots

GABIA_HOST="${GABIA_HOST:-}"
GABIA_USER="${GABIA_USER:-}"
GABIA_PORT="${GABIA_PORT:-22}"
GABIA_SSH_KEY="${GABIA_SSH_KEY:-$HOME/.ssh/gabia_key}"
GABIA_REMOTE="${GABIA_REMOTE:-tsak}"          # 홈 기준 상대경로
GABIA_SERVICE="${GABIA_SERVICE:-tsak-proxy}"  # systemd 유닛 이름
GABIA_PORT_APP="${GABIA_PORT_APP:-5071}"      # 앱이 듣는 포트

SKIP_BUILD=0; DRY=0; DO_ROLLBACK=0
for a in "$@"; do
  case "$a" in
    --skip-build) SKIP_BUILD=1 ;;
    --dry-run)    DRY=1 ;;
    --rollback)   DO_ROLLBACK=1 ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $a"; exit 2 ;;
  esac
done

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { err "$*"; exit 1; }

# ── 0) 자격증명 확인 ────────────────────────────────────────────────────
step "▶ 0) 자격증명 확인"
MISSING=""
[ -z "$GABIA_HOST" ] && MISSING="$MISSING GABIA_HOST"
[ -z "$GABIA_USER" ] && MISSING="$MISSING GABIA_USER"
[ ! -f "$GABIA_SSH_KEY" ] && MISSING="$MISSING GABIA_SSH_KEY($GABIA_SSH_KEY)"

if [ -n "$MISSING" ]; then
  err "다음이 없습니다:$MISSING"
  cat <<'EOF'

  가비아 서버 접속 정보를 환경변수로 지정하세요:

    export GABIA_HOST=tsak.example.com     # 서버 주소
    export GABIA_USER=tsakuser             # SSH 계정
    export GABIA_SSH_KEY=~/.ssh/gabia_key  # 개인키 (권장)

  SSH 키가 없다면 만들어 서버에 등록하세요:
    ssh-keygen -t ed25519 -f ~/.ssh/gabia_key -N ''
    ssh-copy-id -i ~/.ssh/gabia_key.pub $GABIA_USER@$GABIA_HOST

  ⚠️ 비밀번호를 스크립트에 넣지 마세요. 키 인증을 쓰세요.
EOF
  exit 1
fi
ok "HOST=$GABIA_HOST USER=$GABIA_USER KEY=$(basename "$GABIA_SSH_KEY")"

SSH=(ssh -i "$GABIA_SSH_KEY" -p "$GABIA_PORT" -o StrictHostKeyChecking=accept-new \
     -o ConnectTimeout=20 -o BatchMode=yes "$GABIA_USER@$GABIA_HOST")
SCP=(scp -i "$GABIA_SSH_KEY" -P "$GABIA_PORT" -o StrictHostKeyChecking=accept-new \
     -o ConnectTimeout=20 -o BatchMode=yes)
R() { "${SSH[@]}" "$@"; }

step "▶ 0-b) 연결 확인"
if [ "$DRY" = "1" ]; then
  warn "--dry-run: SSH 접속 확인 생략 (로컬 단계만 점검)"
else
  if ! R "echo ok" >/dev/null 2>&1; then
    die "SSH 접속 실패. 키 권한(600)·서버 방화벽·계정을 확인하세요."
  fi
  ok "SSH 접속 OK"
  R "python3 -V 2>&1 | sed 's/^/    /'; echo \"    home=\$HOME\"" || true
fi

# ── 원격 롤백 모드 ──────────────────────────────────────────────────────
if [ "$DO_ROLLBACK" = "1" ]; then
  step "▶ 원격 롤백"
  R "set -e
     #  ## ★ 롤백이 **한 번도 동작한 적이 없었다** (2026-11-20, 리허설이 잡음)
     #   종전 코드:  R='[달러]HOME/$GABIA_REMOTE'
     #     single quote 안에서는 역슬래시-달러가 확장되지 않아 R 에 **글자 그대로**
     #     '$HOME/tsak' 이 들어간다. 그래서 readlink '$HOME/tsak/current' 가
     #     빈 값을 돌려주고, ls 도 실패해 '이전 릴리스가 없습니다' 로 끝났다.
     #     즉 장애 시 롤백을 눌러도 **아무 일도 일어나지 않았다.**
     #     같은 파일의 다른 4곳은 큰따옴표+역슬래시 형태라 올바르다. 한 곳만 달랐다.
     #   ⚠ 이 주석을 원격으로 보낼 때 **백틱을 쓰면 명령 치환으로 실행된다**
     #     (리허설에서 'Is a directory' 오류로 확인). 주석에서도 백틱 금지.
     R=\$HOME/$GABIA_REMOTE
     cur=\$(readlink -f \$R/current 2>/dev/null || true)
     echo \"  현재: \$cur\"
     prev=\$(ls -1dt \$R/releases/*/ 2>/dev/null | sed -n 2p)
     [ -z \"\$prev\" ] && { echo '  ✗ 이전 릴리스가 없습니다'; exit 1; }
     prev=\${prev%/}
     echo \"  되돌릴 대상: \$prev\"
     ln -sfn \"\$prev\" \$R/current.tmp && mv -T \$R/current.tmp \$R/current
     echo \"  current -> \${prev##*/}\"
     sudo systemctl restart $GABIA_SERVICE 2>/dev/null || systemctl --user restart $GABIA_SERVICE 2>/dev/null || true
     #  ## 헬스체크를 3초 만에 포기하면 안 된다 (2026-11-20)
     #   프록시는 기동에 9~22초가 걸린다(캐시 prewarm). 종전 롤백은 sleep 3 뒤
     #   curl 한 번뿐이라 **정상 기동 중인데도 '헬스 실패'를 찍었다.**
     #   장애 대응 중에 거짓 경보를 보면 사람이 더 큰 실수를 한다.
     #   본 배포 경로와 같은 재시도 루프를 쓴다.
     H=000
     for i in \$(seq 1 15); do
       sleep 2
       H=\$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:$GABIA_PORT_APP/api/health 2>/dev/null || echo 000)
       [ \"\$H\" = '200' ] && break
     done
     echo \"  헬스: HTTP \$H\"
     [ \"\$H\" = '200' ] || echo '  ⚠ 롤백 후 헬스 실패 — 수동 확인 필요: journalctl -u $GABIA_SERVICE -n 50'
     echo '  ✅ 롤백 완료'"
  exit $?
fi

# ── 1) 사전 스냅샷 (롤백 안전장치) ──────────────────────────────────────
step "▶ 1) 사전 스냅샷"
if [ "$DRY" = "1" ]; then
  warn "--dry-run: 스냅샷 생략"
else
  bash /home/user/deploy/backup_snapshot.sh 2>&1 | tail -4 | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" = "0" ] || die "스냅샷 실패 — 업로드 중단(안전 우선)"
  SNAP=$(ls -1dt "$SNAP_ROOT"/*/ 2>/dev/null | head -1 | xargs -r basename)
  ok "스냅샷: $SNAP"
fi

# ── 2) 빌드 ────────────────────────────────────────────────────────────
if [ "$SKIP_BUILD" = "1" ]; then
  step "▶ 2) 빌드 건너뜀 (--skip-build)"
  [ -d "$APP/build/web" ] || die "$APP/build/web 없음. 빌드 먼저 필요."
else
  step "▶ 2) Flutter 릴리스 빌드"
  cd "$APP" || die "flutter_app 없음"
  python3 scripts/gen_build_info.py 2>&1 | tail -3 | sed 's/^/  /'
  echo "  flutter build web --release ..."
  if ! flutter build web --release \
        --dart-define=flutter.inspector.structuredErrors=false \
        --dart-define=debugShowCheckedModeBanner=false > /tmp/tsak_build.log 2>&1; then
    err "빌드 실패 — 로그: /tmp/tsak_build.log"
    tail -20 /tmp/tsak_build.log | sed 's/^/    /'
    die "배포 중단"
  fi
  ok "빌드 완료"
fi

# ── 3) 빌드 후처리 (커스텀 자산 복원 + 무결성) ──────────────────────────
step "▶ 3) 빌드 후처리"
cd "$APP" || die "flutter_app 없음"
python3 scripts/gen_version_json.py 2>&1 | tail -2 | sed 's/^/  /' || warn "version.json 생성 실패"

# ⚠️ 이 단계가 build/web/qr.html 을 덮어쓴다. 반드시 md5 재확인.
if [ -d /home/user/web_custom_backup ]; then
  cp -f /home/user/web_custom_backup/* "$APP/build/web/" 2>/dev/null || true
  ok "커스텀 자산 복사"
fi
rm -f "$APP/build/web/qr.html.bak_turn"* 2>/dev/null || true

QR_MD5=$(md5sum "$APP/build/web/qr.html" 2>/dev/null | cut -d' ' -f1)
if [ "$QR_MD5" = "0c427cad7274397f17721f70aa3227f6" ]; then
  ok "qr.html md5 일치"
else
  warn "qr.html md5=$QR_MD5 (기대 0c427cad...) — 배포 전 확인 권장"
fi

# 서비스워커 무력화 확인(낡은 JS 서빙 차단)
#  ⚠️ 실제 방어선은 SW 파일 크기가 아니라 **index.html 의 register 오버라이드**다.
#     - flutter_service_worker.js 는 빌드되면 수 KB 로 존재한다(정상).
#     - index.html 이 navigator.serviceWorker.register 를 빈 함수로 덮어쓰고
#       기존 등록까지 해제하므로, SW 는 등록되지 않는다.
#     → 검사는 index.html 쪽에서 해야 의미가 있다.
if grep -q 'navigator.serviceWorker.register = function' "$APP/build/web/index.html" 2>/dev/null; then
  ok "index.html 서비스워커 오버라이드 존재 (낡은 JS 차단)"
else
  warn "index.html 서비스워커 오버라이드 없음 — 낡은 JS 캐싱 가능성"
fi
if [ -f "$APP/build/web/flutter_service_worker.js" ]; then
  SZ=$(stat -c%s "$APP/build/web/flutter_service_worker.js")
  echo "  (참고) flutter_service_worker.js ${SZ}바이트 — 오버라이드로 미등록"
fi

# ── 4) gabia_deploy 미러 동기화 ─────────────────────────────────────────
step "▶ 4) 배포 번들 동기화"
# 프록시 바이트 동일성 (미러 규칙)
cp -f "$PROXY/proxy_server.py" "$GABIA/api/proxy_server.py"
cp -f "$PROXY/nas_lib.py"     "$GABIA/api/nas_lib.py"
[ -f "$PROXY/img_pipeline.py" ] && cp -f "$PROXY/img_pipeline.py" "$GABIA/api/img_pipeline.py"
if diff -q "$PROXY/proxy_server.py" "$GABIA/api/proxy_server.py" >/dev/null; then
  ok "proxy_server.py 미러 일치"
else
  die "프록시 미러 불일치"
fi

# web 미러 — build/web 과 정확히 같게 (전체 교체)
rm -rf "$GABIA/web"
cp -r "$APP/build/web" "$GABIA/web"
ok "web 미러 교체 ($(find "$GABIA/web" -type f | wc -l) 파일)"

# ── 5) 업로드 (릴리스 디렉터리 + 원자적 전환) ───────────────────────────
STAMP=$(date +%Y%m%d_%H%M%S)
#  ## 1초 이내 재배포 = 같은 릴리스 (2026-11-20, 리허설에서 발견)
#   스탬프 해상도가 1초라, 짧은 시간에 두 번 배포하면 **같은 디렉터리**를
#   덮어쓴다. 그러면 "새 릴리스"가 없으니 롤백 대상도 사라진다.
#   게다가 재전개가 `mv` 로 기존 디렉터리 위에 얹히면서 반쯤 섞인다.
#   → 같은 초에 이미 릴리스가 있으면 접미사를 붙여 **반드시 새 디렉터리**를 만든다.
BASE_STAMP="$STAMP"
_n=2
if [ "$DRY" != "1" ]; then
  while R "test -d \$HOME/$GABIA_REMOTE/releases/$STAMP" >/dev/null 2>&1; do
    STAMP="${BASE_STAMP}_${_n}"; _n=$((_n+1))
    [ "$_n" -gt 10 ] && die "릴리스 스탬프 충돌을 풀 수 없습니다 ($BASE_STAMP)"
  done
fi
[ "$STAMP" != "$BASE_STAMP" ] && warn "같은 초에 재배포 → 스탬프 조정: $STAMP"
step "▶ 5) 업로드 (릴리스 $STAMP)"

# 5-a) 번들 만들기 (gzip 15MB)
#
#  ## ⚠️ api/config.json 은 **번들에서 제외**한다
#   이 샌드박스의 config.json 에는 평문 `auth.master`·`nas.pw`·`auth.app` 이
#   들어 있다. 그대로 번들에 넣으면 (1) 업로드 트래픽에 평문 비밀번호가 실리고
#   (2) 원격 릴리스 폴더에 평문이 남는다.
#   운영 서버는 `shared/config.json`(masterHash 만)을 따로 쓴다.
#   → --exclude 로 빼고, 원격에서 shared/config.json 을 복사한다.
BUNDLE=/tmp/tsak_release_$STAMP.tar.gz
echo "  번들 생성 중... (자격증명 파일 제외)"
tar -czf "$BUNDLE" -C "$GABIA" \
    --exclude='api/config.json' \
    --exclude='api/config.json.*' \
    --exclude='api/gdrive_sa.json' \
    --exclude='api/.gdrive_token.json' \
    --exclude='api/.sessions.json' \
    --exclude='api/__pycache__' \
    api web 2>/dev/null || die "번들 생성 실패"
BSZ=$(du -h "$BUNDLE" | cut -f1)
ok "번들 $BSZ"

# 번들에 자격증명이 섞이지 않았는지 **실제로 확인**한다 (조용한 유출 방지)
BUNDLE_LEAK=$(tar -tzf "$BUNDLE" 2>/dev/null | grep -E '^api/(config\.json|gdrive_sa\.json|\.gdrive_token\.json|\.sessions\.json)' || true)
if [ -z "$BUNDLE_LEAK" ]; then
  ok "번들에 자격증명 없음"
else
  err "번들에 자격증명이 들어갔습니다 — 업로드 중단:"
  echo "$BUNDLE_LEAK" | sed 's/^/      /'
  rm -f "$BUNDLE"
  die "안전을 위해 중단합니다"
fi

if [ "$DRY" = "1" ]; then
  warn "--dry-run: 업로드 생략 (번들만 생성: $BUNDLE)"
  exit 0
fi

# 5-b) 원격 릴리스 디렉터리 준비
#  ## 죽은 코드 제거 (2026-11-20)
#   종전에는 아래처럼 `\$R_STAMP` 를 쓴 블록이 먼저 있었다. 그런데 R_STAMP 는
#   **원격에 존재하지 않는 변수**라 `mkdir -p \$R/releases/` 만 실행됐다.
#   (실패해도 `|| true` 로 묻혀서 아무도 몰랐다) 바로 아래 줄이 제대로 만들기
#   때문에 결과는 맞았지만, 읽는 사람을 속이는 코드라 삭제한다.
R "mkdir -p \$HOME/$GABIA_REMOTE/releases/$STAMP \$HOME/$GABIA_REMOTE/shared" \
  || die "원격 디렉터리 생성 실패"
ok "원격 releases/$STAMP"

# 5-c) 업로드
"${SCP[@]}" "$BUNDLE" "$GABIA_USER@$GABIA_HOST:~/$(basename "$BUNDLE")" \
  || die "업로드 실패"
ok "업로드 완료"

# 5-d) 원격 전개 + 원자적 전환
step "▶ 6) 원격 전개 및 전환"

# 전환 **전에** 상태 디렉터리 지문을 떠 둔다 (전환 후 비교용)
#
#  ## 왜 디렉터리 전체가 아니라 "사용자 자산"만 세는가 — 리허설에서 잡은 오탐
#   처음에는 `shared/state` **전체** 파일 목록을 지문으로 썼다. 그런데 서비스가
#   재시작되면 프록시가 스스로 만드는 파일(.json_mirror, gdrive_store,
#   .thumb_cache, .static_compress_cache 등)이 수십 개 생긴다. 그 결과
#   **정상 배포인데도 "데이터 유실 가능성"으로 빨갛게** 표시됐다.
#   늑대 소리를 하면 진짜 경보를 무시하게 되므로, 지문을 둘로 나눈다.
#     critical : 절대 사라지면 안 되는 사용자 자산 (세션·업로드)
#     cache    : 없어도 다시 만들어지는 것 (참고용으로만 표시)
STATE_DIR="$GABIA_REMOTE/shared/state"
#  ## find 식은 **한 겹 더 조심해야 한다** (2026-11-20, 리허설에서 두 번째 오탐)
#   처음엔 이렇게 썼다:
#       find $S -maxdepth 1 -name .sessions.json -o -maxdepth 2 -path */merch_img_upload/*
#   두 가지 이유로 틀렸다.
#     1) `-maxdepth` 는 **전역 옵션**인데 OR 갈래 안에 넣었다. 실측해보니
#        merch_img_upload/sub/y.png 같은 **하위 폴더 업로드가 지문에서 빠졌다.**
#        (업로드가 하위 폴더로 늘면 "자산 동일"이라고 거짓 보고를 한다)
#     2) `-a` 가 `-o` 보다 우선순위가 높아, 괄호 없이는 의도가 우연히 맞을 뿐이다.
#   그래서 OR 없이 **find 두 개를 묶는** 형태로 바꾼다. 글롭 확장 위험도 없다.
#   single quote 로 감싸 두었으므로 $S 는 **원격에서** 확장된다.
CRIT_FIND='{ find "$S" -maxdepth 1 -type f -name ".sessions.json" 2>/dev/null; find "$S/merch_img_upload" -type f 2>/dev/null; }'
PRE_STATE=$(R "set -e
  S=\$HOME/$STATE_DIR
  mkdir -p \$S
  chmod 700 \$S 2>/dev/null || true
  echo \"files=\$(find \$S -type f 2>/dev/null | wc -l)\"
  echo \"bytes=\$(du -sb \$S 2>/dev/null | cut -f1)\"
  echo \"crit=\$($CRIT_FIND | sort | sha1sum | cut -d' ' -f1)\"
  echo \"critn=\$($CRIT_FIND | wc -l)\"" 2>/dev/null)
echo "$PRE_STATE" | sed 's/^/    전환 전 /'
PRE_LIST=$(echo "$PRE_STATE" | sed -n 's/^crit=//p')
PRE_CRITN=$(echo "$PRE_STATE" | sed -n 's/^critn=//p')

R "set -e
   R=\$HOME/$GABIA_REMOTE
   cd \$R/releases/$STAMP
   tar -xzf \$HOME/$(basename "$BUNDLE")
   rm -f \$HOME/$(basename "$BUNDLE")

   # 자격증명은 shared 에서 가져온다(릴리스에 넣지 않는다)
   if [ -f \$R/shared/config.json ]; then
     cp -f \$R/shared/config.json api/config.json
     chmod 600 api/config.json
     echo '  config: shared 에서 복사'
   else
     echo '  ⚠ shared/config.json 없음 — 첫 배포면 지금 올려야 합니다'
   fi

   # 릴리스 무결성
   for f in api/proxy_server.py api/nas_lib.py api/img_pipeline.py web/index.html; do
     [ -e \"\$f\" ] || { echo \"  ✗ 누락: \$f\"; exit 1; }
   done
   echo '  릴리스 무결성 OK'

   # 상태 디렉터리는 릴리스 밖에 있어야 한다
   mkdir -p \$R/shared/state
   chmod 700 \$R/shared/state 2>/dev/null || true

   # 원자적 전환: 심볼릭 링크만 교체
   ln -sfn \$R/releases/$STAMP \$R/current.tmp
   mv -T \$R/current.tmp \$R/current
   echo '  current -> releases/$STAMP'
" 2>&1 | sed 's/^/  /'
[ "${PIPESTATUS[0]}" = "0" ] || die "원격 전개 실패 — 이전 릴리스 유지됨(서비스 영향 없음)"
ok "전환 완료"

# 5-e) 릴리스 정리 (최근 5개 유지)
#  ## ★ 롤백 불가 사고 예방 (2026-11-20)
#   종전: `ls -1dt releases/*/ | tail -n +6 | xargs rm -rf`
#     결과가 **최신순**이므로 정확히 **방금 만든 릴리스**를 지웠다.
#     (6번째 배포에서 current 가 허공을 가리킨다 → 재시작 실패 → 서비스 다운)
#     게다가 `-d` 로 정렬하면 디렉터리 mtime 이 자식 생성에도 갱신되어
#     "최신"의 의미가 흔들린다.
#   이제: 방금 만든 $STAMP 와 current 가 가리키는 릴리스는 **무조건 보존**하고,
#         나머지 중 오래된 것만 지운다. 세는 것도 `-d` 대신 `-1t` 로 통일.
R "R=\$HOME/$GABIA_REMOTE
   KEEP='$STAMP'
   CUR=\$(readlink -f \$R/current 2>/dev/null || true); CUR=\${CUR##*/}
   n=0
   for d in \$(ls -1t \$R/releases 2>/dev/null); do
     n=\$((n+1))
     [ \$n -le 5 ] && continue
     [ \"\$d\" = \"\$KEEP\" ] && continue
     [ \"\$d\" = \"\$CUR\" ] && continue
     rm -rf \"\$R/releases/\$d\"
   done
   echo \"  릴리스 \$(ls -1 \$R/releases 2>/dev/null | wc -l)개 유지 (보존: \$KEEP)\"" 2>&1 | sed 's/^/  /'

# ── 7) 재시작 + 헬스체크 ────────────────────────────────────────────────
step "▶ 7) 서비스 재시작"
R "sudo systemctl restart $GABIA_SERVICE 2>/dev/null \
   || systemctl --user restart $GABIA_SERVICE 2>/dev/null \
   || echo '  ⚠ systemd 재시작 실패 — 수동 확인 필요'" 2>&1 | sed 's/^/  /'

echo "  헬스체크 대기..."
HEALTH="000"
for i in $(seq 1 15); do
  sleep 2
  HEALTH=$(R "curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:$GABIA_PORT_APP/api/health" 2>/dev/null || echo "000")
  [ "$HEALTH" = "200" ] && break
  printf '    재시도 %d/15 (HTTP %s)\n' "$i" "$HEALTH"
done

if [ "$HEALTH" = "200" ]; then
  ok "헬스체크 HTTP 200"
  R "curl -s -m 5 http://127.0.0.1:$GABIA_PORT_APP/api/health" 2>/dev/null | head -c 200 | sed 's/^/    /'
  echo
else
  err "헬스체크 실패 (HTTP $HEALTH) — 자동 롤백합니다"
  R "set -e
     R=\$HOME/$GABIA_REMOTE
     prev=\$(ls -1dt \$R/releases/*/ | sed -n 2p)
     if [ -n \"\$prev\" ]; then
       ln -sfn \"\${prev%/}\" \$R/current.tmp && mv -T \$R/current.tmp \$R/current
       sudo systemctl restart $GABIA_SERVICE 2>/dev/null || true
       echo '  이전 릴리스로 되돌림'
     else
       echo '  ✗ 이전 릴리스 없음 — 수동 복구 필요'
     fi" 2>&1 | sed 's/^/  /'
  die "배포 실패 — 롤백 시도 완료. 로그: ssh ... journalctl -u $GABIA_SERVICE -n 50"
fi

# ── 8) 상태 보존 검사 (★롤백이 데이터를 잃지 않는지 실측) ───────────────
step "▶ 8) 상태 보존 검사 (사용자 자산)"
POST_STATE=$(R "set -e
  S=\$HOME/$STATE_DIR
  echo \"files=\$(find \$S -type f 2>/dev/null | wc -l)\"
  echo \"bytes=\$(du -sb \$S 2>/dev/null | cut -f1)\"
  echo \"crit=\$($CRIT_FIND | sort | sha1sum | cut -d' ' -f1)\"
  echo \"critn=\$($CRIT_FIND | wc -l)\"" 2>/dev/null)
echo "$POST_STATE" | sed 's/^/    전환 후 /'
POST_LIST=$(echo "$POST_STATE" | sed -n 's/^crit=//p')
POST_CRITN=$(echo "$POST_STATE" | sed -n 's/^critn=//p')

if [ -z "$PRE_LIST" ] || [ -z "$POST_LIST" ]; then
  warn "상태 지문을 읽지 못했습니다 — 수동 확인 필요"
elif [ "$PRE_LIST" = "$POST_LIST" ]; then
  ok "사용자 자산 동일 (세션·업로드 ${POST_CRITN}개 파일, 지문 일치)"
else
  err "사용자 자산이 바뀌었습니다 — 데이터 유실 가능성"
  echo "      전: $PRE_LIST (${PRE_CRITN}개)"
  echo "      후: $POST_LIST (${POST_CRITN}개)"
  err "즉시 확인하세요: ssh ... 'ls -la ~/$STATE_DIR'"
fi

# 상태가 릴리스 폴더로 새지 않았는지 (새는 순간 다음 롤백에서 잃는다)
LEAK=$(R "find \$HOME/$GABIA_REMOTE/releases/$STAMP/api -maxdepth 1 \
  \( -name .json_mirror -o -name gdrive_store -o -name .sessions.json \
     -o -name merch_img_upload -o -name .thumb_cache -o -name .media_cache \
     -o -name .safe_snapshots -o -name .ev_meta_cache \) 2>/dev/null" 2>/dev/null)
if [ -z "$LEAK" ]; then
  ok "릴리스 폴더에 상태 누출 없음"
else
  warn "릴리스 폴더에 상태가 생성되고 있습니다:"
  echo "$LEAK" | sed 's/^/      /'
  echo "      → TSAK_STATE_DIR 가 유닛에 없는지 확인하세요"
fi

# ── 9) 스모크 테스트 (사용자가 실제로 여는 경로) ─────────────────────────
step "▶ 9) 스모크 테스트"
SMOKE_FAIL=0
smoke() {  # $1=설명 $2=경로 $3=기대코드(기본 200)
  local d="$1" p="$2" want="${3:-200}"
  local got
  got=$(R "curl -s -m 15 -o /dev/null -w '%{http_code}' http://127.0.0.1:$GABIA_PORT_APP$p" 2>/dev/null || echo 000)
  if [ "$got" = "$want" ]; then
    printf '  \033[32m✓\033[0m %-34s HTTP %s\n' "$d" "$got"
  else
    printf '  \033[31m✗\033[0m %-34s HTTP %s (기대 %s)\n' "$d" "$got" "$want"
    SMOKE_FAIL=1
  fi
}
smoke "홈 (index.html)"        "/"
smoke "QR 페이지"              "/qr.html"
smoke "추모관"                 "/memorial.html"
smoke "Scout's Own"           "/scoutsown.html"
smoke "버전 정보"              "/version.json"
smoke "헬스 (공개 API)"        "/api/health"
# 인증이 걸린 API 는 401/403 이 정상이다 — "살아 있다"만 확인한다
smoke "설정 API (인증 필요)"   "/api/config" "401"

# 정적 자산이 실제로 서빙되는지 (빌드 산출물 누락 조기 발견)
MAINJS=$(R "curl -s -m 15 -o /dev/null -w '%{http_code}' http://127.0.0.1:$GABIA_PORT_APP/main.dart.js" 2>/dev/null || echo 000)
[ "$MAINJS" = "200" ] && ok "main.dart.js 서빙" || { err "main.dart.js HTTP $MAINJS"; SMOKE_FAIL=1; }

# 낡은 JS 캐싱 차단 확인 — 실제 배포물 기준
SWOV=$(R "grep -c 'navigator.serviceWorker.register = function' \$HOME/$GABIA_REMOTE/current/web/index.html" 2>/dev/null || echo 0)
[ "${SWOV:-0}" -ge 1 ] && ok "서비스워커 오버라이드 (배포물)" || { warn "배포물에 SW 오버라이드 없음"; }

if [ "$SMOKE_FAIL" = "1" ]; then
  err "스모크 테스트 실패 — 자동 롤백합니다"
  R "set -e
     R=\$HOME/$GABIA_REMOTE
     prev=\$(ls -1dt \$R/releases/*/ | sed -n 2p)
     if [ -n \"\$prev\" ]; then
       ln -sfn \"\${prev%/}\" \$R/current.tmp && mv -T \$R/current.tmp \$R/current
       sudo systemctl restart $GABIA_SERVICE 2>/dev/null || true
       echo '  이전 릴리스로 되돌림'
     fi" 2>&1 | sed 's/^/  /'
  die "배포 실패(스모크) — 롤백 완료"
fi
ok "스모크 테스트 전부 통과"

echo
echo "✅ 배포 완료: $STAMP"
echo "   로컬 스냅샷: $SNAP_ROOT/${SNAP:-(dry-run)}"
echo "   되돌리기  : bash $0 --rollback"
echo "   로그 확인 : ssh -i $GABIA_SSH_KEY $GABIA_USER@$GABIA_HOST 'journalctl -u $GABIA_SERVICE -n 50'"
