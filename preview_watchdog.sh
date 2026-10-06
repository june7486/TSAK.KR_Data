#!/bin/bash
# TSAK 프리뷰 서버(5060/8899) watchdog
#  · 30초마다 두 포트를 확인하고, 죽어 있으면 자동 재기동
#  · build/web 는 빌드 스크립트가 갱신 → 서버는 항상 최신 정적파일 서빙
#  · setsid 로 분리 실행(셸 종료와 무관)
cd "$(dirname "$0")" || exit 1
LOG=preview_watchdog.log
start() {
  local port="$1"
  (lsof -ti:$port | xargs -r kill -9) 2>/dev/null
  sleep 1
  setsid nohup python3 preview_server.py "$port" >"/tmp/preview$port.log" 2>&1 </dev/null &
  disown 2>/dev/null
  echo "[$(date '+%F %T')] preview $port 재기동 pid=$!" >>"$LOG"
}
echo "[$(date '+%F %T')] preview watchdog 시작(30s)" >>"$LOG"
while true; do
  sleep 30
  for port in 5060 8899; do
    if ! (lsof -ti:$port >/dev/null 2>&1); then
      start "$port"
    fi
  done
done
