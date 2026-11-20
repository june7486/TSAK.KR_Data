#!/usr/bin/env bash
# ============================================================================
#  TSAK 배포 복원 — 스냅샷 지점으로 되돌린다
# ----------------------------------------------------------------------------
#  ## 원칙
#   · 복원도 파괴적 작업이다. 복원 전에 **현재 상태를 먼저 스냅샷**한다
#     (`--no-safety` 로 끌 수 있지만 권장하지 않는다).
#   · 복원 후 반드시 검증한다: 파일 수, 해시, git 커밋, 정적 자산 무결성.
#   · 프록시 재시작은 **선택**이다(`--restart`). 기본은 파일만 되돌린다.
#
#  ## 사용
#   bash /home/user/deploy/restore_snapshot.sh --list
#   bash /home/user/deploy/restore_snapshot.sh 20261120_074500
#   bash /home/user/deploy/restore_snapshot.sh 20261120_074500 --restart
#   bash /home/user/deploy/restore_snapshot.sh --latest --restart
# ============================================================================
set -uo pipefail

SNAP_ROOT="/home/user/.tsak_snapshots"
GABIA="/home/user/gabia_deploy"
PROXY_SRC="/home/user/nas_proxy"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

SNAP=""; DO_RESTART=0; SAFETY=1
for a in "$@"; do
  case "$a" in
    --list)
      echo "스냅샷 목록: $SNAP_ROOT"
      [ -d "$SNAP_ROOT" ] || { echo "  (없음)"; exit 0; }
      for d in "$SNAP_ROOT"/*/; do
        [ -d "$d" ] || continue
        nm=$(basename "$d"); sz=$(du -sh "$d" 2>/dev/null | cut -f1)
        c=$(grep -m1 '^commit' "$d/SNAPSHOT_INFO.txt" 2>/dev/null | cut -d= -f2)
        printf '  %s  %6s  commit=%s\n' "$nm" "$sz" "${c:-?}"
      done
      exit 0 ;;
    --restart)  DO_RESTART=1 ;;
    --no-safety) SAFETY=0 ;;
    --latest)
      SNAP=$(ls -1dt "$SNAP_ROOT"/*/ 2>/dev/null | head -1 | xargs -r basename) ;;
    -*)  err "알 수 없는 옵션: $a"; exit 2 ;;
    *)   SNAP="$a" ;;
  esac
done

if [ -z "$SNAP" ]; then
  err "스냅샷 타임스탬프를 지정하세요."
  echo "   bash $0 --list    # 목록 보기"
  exit 2
fi

DEST="$SNAP_ROOT/$SNAP"
[ -d "$DEST" ] || { err "스냅샷이 없습니다: $DEST"; exit 1; }
[ -f "$DEST/gabia_deploy.tar.gz" ] || { err "압축 파일 없음: $DEST/gabia_deploy.tar.gz"; exit 1; }

step "▶ 복원 대상: $SNAP"
[ -f "$DEST/SNAPSHOT_INFO.txt" ] && sed 's/^/   /' "$DEST/SNAPSHOT_INFO.txt"

# ── 1) 압축 무결성 먼저 ──────────────────────────────────────────────────
step "▶ 1) 압축 무결성 사전 검사"
if ! tar -tzf "$DEST/gabia_deploy.tar.gz" >/dev/null 2>&1; then
  err "압축이 손상됐습니다. 복원 중단."; exit 1
fi
ok "tar OK ($(tar -tzf "$DEST/gabia_deploy.tar.gz" | wc -l) 항목)"

# ── 2) 안전 스냅샷 (복원도 파괴적이므로) ─────────────────────────────────
if [ "$SAFETY" = "1" ]; then
  step "▶ 2) 복원 전 현재 상태 스냅샷"
  if bash /home/user/deploy/backup_snapshot.sh >/tmp/tsak_presafety.log 2>&1; then
    PRE=$(ls -1dt "$SNAP_ROOT"/*/ | head -1 | xargs -r basename)
    ok "현재 상태 저장됨: $PRE (문제 시 여기로 되돌릴 수 있음)"
  else
    err "안전 스냅샷 실패. --no-safety 로 강행하거나 원인 해결 후 재시도."
    tail -5 /tmp/tsak_presafety.log | sed 's/^/   /'
    exit 1
  fi
else
  warn "--no-safety: 현재 상태를 저장하지 않고 진행"
fi

# ── 3) 교체 (임시 위치에 풀고 검증 후 바꿔치기) ──────────────────────────
step "▶ 3) 임시 위치에 전개 후 검증"
WORK=$(mktemp -d /home/user/.tsak_restore_XXXXXX)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if ! tar -C "$WORK" -xzf "$DEST/gabia_deploy.tar.gz"; then
  err "전개 실패"; exit 1
fi
[ -d "$WORK/gabia_deploy" ] || { err "전개 결과에 gabia_deploy 없음"; exit 1; }
ok "전개 완료"

# 전개본 필수 파일 검사 — 여기서 걸러야 반쯤 망가진 배포를 안 만든다
FAIL=0
for f in api/proxy_server.py api/nas_lib.py api/start.sh web/index.html .git/HEAD; do
  if [ -e "$WORK/gabia_deploy/$f" ]; then ok "존재: $f"; else err "누락: $f"; FAIL=1; fi
done
[ "$FAIL" = "1" ] && { err "전개본 불완전 — 복원 중단(현재 상태 그대로 유지)"; exit 1; }

# config 복원 (git 에 없는 파일)
if [ -f "$DEST/config_gabia.json" ]; then
  cp -a "$DEST/config_gabia.json" "$WORK/gabia_deploy/api/config.json"
  chmod 600 "$WORK/gabia_deploy/api/config.json"
  ok "config.json 복원 (chmod 600)"
fi
[ -f "$DEST/gdrive_sa.json" ] && {
  cp -a "$DEST/gdrive_sa.json" "$WORK/gabia_deploy/api/gdrive_sa.json"
  chmod 600 "$WORK/gabia_deploy/api/gdrive_sa.json"
}

# ── 4) 교체 ──────────────────────────────────────────────────────────────
step "▶ 4) gabia_deploy 교체"
OLD="/home/user/.gabia_deploy_old_$$"
mv "$GABIA" "$OLD" || { err "기존 디렉터리 이동 실패"; exit 1; }
if mv "$WORK/gabia_deploy" "$GABIA"; then
  ok "교체 완료"
  rm -rf "$OLD"
else
  err "교체 실패 — 되돌립니다"
  mv "$OLD" "$GABIA"
  exit 1
fi

# ── 5) 검증 ──────────────────────────────────────────────────────────────
step "▶ 5) 복원 후 검증"
FAIL=0
CNT=$(find "$GABIA/web" -type f 2>/dev/null | wc -l)
echo "   web 파일 수: $CNT"
[ "$CNT" -ge 60 ] && ok "web 파일 수 정상" || { err "web 파일 부족"; FAIL=1; }

NEWCOMMIT=$(cd "$GABIA" && git rev-parse HEAD 2>/dev/null || echo "unknown")
WANT=$(grep -m1 '^commit' "$DEST/SNAPSHOT_INFO.txt" 2>/dev/null | cut -d= -f2)
if [ "$NEWCOMMIT" = "$WANT" ]; then ok "git 커밋 일치: ${NEWCOMMIT:0:8}"
else warn "커밋 불일치 (기대 ${WANT:0:8} / 실제 ${NEWCOMMIT:0:8})"; fi

DIRTY=$(cd "$GABIA" && git status --porcelain 2>/dev/null | wc -l)
echo "   worktree 변경: $DIRTY 파일"

# qr.html 무결성 (배포 함정: build/web 덮어쓰기)
if [ -f "$GABIA/web/qr.html" ]; then
  QMD5=$(md5sum "$GABIA/web/qr.html" | cut -d' ' -f1)
  if [ "$QMD5" = "0c427cad7274397f17721f70aa3227f6" ]; then
    ok "qr.html md5 일치"
  else
    warn "qr.html md5 $QMD5 (기대 0c427cad...)"
  fi
fi

# 프록시 파일 해시 비교
if [ -f "$DEST/SHA256SUMS.txt" ]; then
  while read -r want_hash want_path; do
    case "$want_hash" in \#*|"") continue ;; esac
    bn=$(basename "$want_path")
    if [ -f "$GABIA/api/$bn" ]; then
      got=$(sha256sum "$GABIA/api/$bn" | cut -d' ' -f1)
      [ "$got" = "$want_hash" ] && ok "sha256 일치: $bn" || warn "sha256 불일치: $bn"
    fi
  done < "$DEST/SHA256SUMS.txt"
fi

if [ "$FAIL" = "1" ]; then
  err "검증 실패 — 위 항목 확인 필요"
  exit 1
fi

# ── 6) 선택: 프록시 재시작 ───────────────────────────────────────────────
if [ "$DO_RESTART" = "1" ]; then
  step "▶ 6) 프록시 재시작"
  if [ -x /home/user/nas_proxy/clean_restart.sh ]; then
    bash /home/user/nas_proxy/clean_restart.sh
    ok "재시작 스크립트 실행됨"
  else
    warn "clean_restart.sh 없음 — 수동 재시작 필요"
  fi
else
  echo
  warn "프록시는 재시작하지 않았습니다 (파일만 복원). 반영하려면 --restart 또는 clean_restart.sh"
fi

echo
echo "✅ 복원 완료: $SNAP"
