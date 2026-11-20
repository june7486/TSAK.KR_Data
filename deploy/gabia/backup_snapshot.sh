#!/usr/bin/env bash
# ============================================================================
#  TSAK 배포 스냅샷 — 되돌릴 수 있는 지점을 만든다
# ----------------------------------------------------------------------------
#  ## 왜 필요한가
#   "언제든지 다시 돌아올 수 있어" 라는 요구는 **되돌릴 지점이 실제로 있고,
#   그 지점이 온전한지 검증됐을 때만** 성립한다. 스냅샷을 만들었다고
#   끝내면 안 되고, 만들 때마다 복원 가능성을 검사해야 한다.
#
#  ## 스냅샷에 담는 것
#   1) gabia_deploy 전체 (git 이력 포함 → 커밋 해시로 정확히 복원 가능)
#   2) 프록시 실행 파일 (proxy_server.py, nas_lib.py, img_pipeline.py, start.sh)
#   3) 가비아용 config.json (gitignore 대상이라 git 에 없다 → 따로 담는다)
#   4) 실행 중이던 프록시의 SHA-256 + git 상태 (증거)
#
#  ## 저장 위치
#   /home/user/.tsak_snapshots/<타임스탬프>/
#   최근 KEEP 개만 남긴다(기본 12). 오래된 것부터 지운다.
#
#  ## 사용
#   bash /home/user/deploy/backup_snapshot.sh            # 스냅샷 생성
#   bash /home/user/deploy/backup_snapshot.sh --list     # 목록
# ============================================================================
set -uo pipefail

SNAP_ROOT="/home/user/.tsak_snapshots"
KEEP="${TSAK_SNAP_KEEP:-12}"
GABIA="/home/user/gabia_deploy"
PROXY_SRC="/home/user/nas_proxy"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

if [ "${1:-}" = "--list" ]; then
  echo "스냅샷 목록: $SNAP_ROOT"
  [ -d "$SNAP_ROOT" ] || { echo "  (없음)"; exit 0; }
  for d in "$SNAP_ROOT"/*/; do
    [ -d "$d" ] || continue
    nm=$(basename "$d")
    sz=$(du -sh "$d" 2>/dev/null | cut -f1)
    meta="$d/SNAPSHOT_INFO.txt"
    head1=$(grep -m1 '^commit' "$meta" 2>/dev/null | cut -d= -f2)
    printf '  %s  %6s  commit=%s\n' "$nm" "$sz" "${head1:-?}"
  done
  exit 0
fi

step "▶ TSAK 배포 스냅샷 생성"

STAMP=$(date +%Y%m%d_%H%M%S)
DEST="$SNAP_ROOT/$STAMP"
mkdir -p "$DEST" || { err "스냅샷 디렉터리 생성 실패"; exit 1; }
ok "위치: $DEST"

# ── 1) 용량 사전 확인 ────────────────────────────────────────────────────
NEED_MB=$(du -sm "$GABIA" 2>/dev/null | cut -f1)
FREE_MB=$(df -m /home/user | tail -1 | awk '{print $4}')
echo "  필요 ≈ ${NEED_MB}MB / 여유 ${FREE_MB}MB"
if [ "$FREE_MB" -lt $((NEED_MB + 200)) ]; then
  err "여유 공간 부족 (최소 $((NEED_MB + 200))MB 필요). 디스크 정리 후 재실행."
  exit 1
fi

# ── 2) gabia_deploy 통째 복사 (git 이력 포함) ────────────────────────────
step "▶ gabia_deploy 복사 (git 이력 포함)"
if tar -C /home/user -czf "$DEST/gabia_deploy.tar.gz" gabia_deploy 2>/dev/null; then
  SZ=$(du -h "$DEST/gabia_deploy.tar.gz" | cut -f1)
  ok "gabia_deploy.tar.gz ($SZ)"
else
  err "gabia_deploy 압축 실패"; exit 1
fi

# ── 3) 프록시 실행 파일 ──────────────────────────────────────────────────
step "▶ 프록시 실행 파일"
mkdir -p "$DEST/proxy"
COPIED=0
for f in proxy_server.py nas_lib.py img_pipeline.py sync_web_mirror.sh clean_restart.sh; do
  if [ -f "$PROXY_SRC/$f" ]; then
    cp -a "$PROXY_SRC/$f" "$DEST/proxy/"
    COPIED=$((COPIED + 1))
  fi
done
ok "프록시 파일 ${COPIED}개"

# ── 4) 가비아용 config (gitignore 대상) ──────────────────────────────────
step "▶ 가비아 config.json (민감 — 별도 보관)"
if [ -f "$GABIA/api/config.json" ]; then
  cp -a "$GABIA/api/config.json" "$DEST/config_gabia.json"
  chmod 600 "$DEST/config_gabia.json"
  ok "config_gabia.json (chmod 600)"
else
  warn "gabia_deploy/api/config.json 없음 — 건너뜀"
fi
if [ -f "$GABIA/api/gdrive_sa.json" ]; then
  cp -a "$GABIA/api/gdrive_sa.json" "$DEST/gdrive_sa.json"
  chmod 600 "$DEST/gdrive_sa.json"
  ok "gdrive_sa.json (chmod 600)"
fi

# ── 5) 증거 기록 ─────────────────────────────────────────────────────────
step "▶ 증거 기록"
COMMIT=$(cd "$GABIA" && git rev-parse HEAD 2>/dev/null || echo "unknown")
DIRTY=$(cd "$GABIA" && git status --porcelain 2>/dev/null | wc -l)
BRANCH=$(cd "$GABIA" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

cat > "$DEST/SNAPSHOT_INFO.txt" <<EOF
# TSAK 배포 스냅샷
stamp=$STAMP
created=$(date '+%Y-%m-%d %H:%M:%S %Z')
commit=$COMMIT
branch=$BRANCH
dirty_files=$DIRTY
host=$(hostname)
python=$(python3 -V 2>&1)
disk_free_mb=$FREE_MB
EOF

# 실행 파일 해시
{
  echo "# 실행 파일 SHA-256 (복원 후 동일성 검증에 사용)"
  for f in proxy_server.py nas_lib.py img_pipeline.py; do
    [ -f "$PROXY_SRC/$f" ] && sha256sum "$PROXY_SRC/$f"
  done
} > "$DEST/SHA256SUMS.txt"
ok "SNAPSHOT_INFO.txt / SHA256SUMS.txt"

# ── 6) 복원 가능성 검증 (가장 중요) ──────────────────────────────────────
step "▶ 복원 가능성 검증 (압축 무결성)"
FAIL=0
# ⚠️ `tar -tzf ... | grep -q` 를 쓰면 안 된다:
#    `grep -q` 가 첫 일치에서 종료 → tar 가 SIGPIPE(141) → `set -o pipefail`
#    때문에 **일치했는데도 파이프라인이 실패**한다. 게다가 372MB tar 를
#    항목마다 다시 푸는 것은 낭비다. 한 번만 풀어 목록 파일로 만든다.
LIST="$DEST/.tar_list.txt"
if tar -tzf "$DEST/gabia_deploy.tar.gz" > "$LIST" 2>/dev/null; then
  N=$(wc -l < "$LIST")
  ok "tar 무결성 OK (${N} 항목)"
else
  err "tar 손상 — 이 스냅샷은 쓸 수 없습니다"; FAIL=1
fi

# 필수 파일이 압축 안에 있는지 (목록 파일에서 검사)
for need in gabia_deploy/api/proxy_server.py gabia_deploy/api/nas_lib.py \
            gabia_deploy/web/index.html gabia_deploy/.git/HEAD; do
  if grep -qxF "$need" "$LIST" 2>/dev/null; then
    ok "포함: $need"
  else
    err "누락: $need"; FAIL=1
  fi
done
rm -f "$LIST"

if [ "$FAIL" = "1" ]; then
  err "검증 실패 — 스냅샷을 신뢰할 수 없습니다: $DEST"
  exit 1
fi

# ── 7) 오래된 스냅샷 정리 ────────────────────────────────────────────────
step "▶ 오래된 스냅샷 정리 (최근 ${KEEP}개 유지)"
CNT=$(ls -1d "$SNAP_ROOT"/*/ 2>/dev/null | wc -l)
if [ "$CNT" -gt "$KEEP" ]; then
  ls -1dt "$SNAP_ROOT"/*/ | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -rf "$old" && echo "   삭제: $(basename "$old")"
  done
fi
ok "현재 스냅샷 $(ls -1d "$SNAP_ROOT"/*/ 2>/dev/null | wc -l)개"

echo
echo "✅ 스냅샷 완료: $DEST"
echo "   복원: bash /home/user/deploy/restore_snapshot.sh $STAMP"
