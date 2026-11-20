# TSAK 가비아 이전 런북

최종 갱신: 2026-11-20
대상: TSAK.KR 인가자 관리 (Flutter web + Python 프록시)

---

## 0. 한눈에 보는 결론

| 항목 | 상태 |
|---|---|
| 경로 이식성 (하드코딩 제거) | ✅ 완료 · 이전 시험 통과 |
| 코드/상태 분리 (`TSAK_STATE_DIR`) | ✅ 완료 · A→B→A 전환 시험 통과 |
| 롤백 안전장치 (로컬 스냅샷) | ✅ 완료 · 실제 복원 검증 |
| 롤백 안전장치 (원격 릴리스) | ✅ 스크립트 완료 · **실서버 미검증** |
| 자동 업로드 파이프라인 | ✅ 완료 · 드라이런 통과 · **실서버 미검증** |
| 가비아 자격증명 | ❌ **없음 — 사용자 제공 필요** |
| 실서버 최종 검증 | ❌ **자격증명 확보 후 가능** |

> **정직하게:** 로컬에서 검증할 수 있는 것은 전부 검증했습니다.
> 다만 가비아 서버에 실제로 접속한 적은 없습니다. SSH·systemd·nginx·
> 인증서 경로는 **한 번도 실제로 돌려보지 않았습니다.**

---

## 1. 가장 중요한 설계 결정 — 코드와 상태를 분리한다

### 왜
가비아 배포는 **릴리스 단위**입니다.

```
~/tsak/releases/20261120_143000/{api,web}
~/tsak/current -> releases/20261120_143000     ← 이 링크만 바꾼다
~/tsak/shared/config.json                       ← 자격증명
~/tsak/shared/state/                            ← 세션·업로드·캐시
```

상태 파일이 릴리스 폴더 안에 있으면 릴리스를 바꾸는 순간 전부 사라집니다.
**롤백이 곧 데이터 손실**이 됩니다. 되돌리려고 만든 장치가 데이터를
잃는 장치가 되는 셈입니다.

### 어떻게
```
TSAK_APP_ROOT  = $REMOTE/current/api          (릴리스마다 바뀐다 — 읽기 전용)
TSAK_STATE_DIR = $REMOTE/shared/state         (릴리스와 무관 — 영속)
```

`proxy_server.py` 는 모든 상태 경로를 `STATE_ROOT` 기준으로 계산합니다.
`TSAK_STATE_DIR` 이 없으면 종전과 동일하게 코드 위치를 씁니다 →
**이 샌드박스 동작은 100% 그대로**입니다(회귀 없음, 실측 확인).

### 검증
```bash
bash /home/user/deploy/tests/test_release_switch.sh
```
A→B→A 전환을 실제 기동으로 반복하며 확인하는 것:
- A 에서 쓴 파일이 B 에서도 보인다
- B 에서 쓴 파일이 A 로 돌아가도 보인다 (양방향)
- **릴리스 폴더에 상태가 새지 않는다**
- 시험 중 NAS 쓰기는 `sitecustomize.py` 가 예외로 차단 (읽기만)
- 시험 전후 NAS `db/` 지문 동일 — 운영 데이터 무변경

---

## 2. 준비물 (사용자가 제공해야 하는 것)

```bash
export GABIA_HOST=...          # 서버 주소 (예: tsak.kr 또는 IP)
export GABIA_USER=...          # SSH 계정
export GABIA_SSH_KEY=~/.ssh/gabia_key
export GABIA_PORT=22           # 기본 22
export GABIA_REMOTE=tsak       # 홈 기준 배포 디렉터리
export GABIA_SERVICE=tsak-proxy
export GABIA_PORT_APP=5071
```

SSH 키 만들고 서버에 등록:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/gabia_key -N ''
ssh-copy-id -i ~/.ssh/gabia_key.pub $GABIA_USER@$GABIA_HOST
```

> ⚠️ 비밀번호를 스크립트·명령행·git 에 넣지 마세요. 키 인증만 씁니다.
> (`sshpass` 를 쓰던 옛 `gabia_deploy/deploy.sh` 는 폐기했습니다.)

---

## 3. 첫 배포 순서 (반드시 이 순서)

### 3-1. 서버에 자격증명 올리기
릴리스와 **분리된** 위치에 둡니다. 릴리스에 넣으면 다음 배포에서 사라집니다.

```bash
# 로컬에서 생성 (평문 master 제거, masterHash 만)
python3 /home/user/deploy/prepare_gabia_config.py

# 서버로 전송
ssh -i ~/.ssh/gabia_key $GABIA_USER@$GABIA_HOST 'mkdir -p ~/tsak/shared'
scp -i ~/.ssh/gabia_key /home/user/gabia_deploy/api/config.json \
    $GABIA_USER@$GABIA_HOST:~/tsak/shared/config.json
ssh -i ~/.ssh/gabia_key $GABIA_USER@$GABIA_HOST 'chmod 600 ~/tsak/shared/config.json'
```

### 3-2. 첫 릴리스 업로드
```bash
bash /home/user/deploy/deploy_gabia.sh
```
하는 일: 스냅샷 → 빌드 → 후처리 검증 → 미러 동기화 → 번들(15MB) →
업로드 → `shared/config.json` 복사 → 릴리스 무결성 → **심볼릭 링크만 교체**.

이 시점에는 아직 systemd 유닛이 없으므로 서비스는 뜨지 않습니다(정상).

### 3-3. 서버 세팅 (한 번만)
```bash
# 먼저 점검 (아무것도 쓰지 않음)
scp -i ~/.ssh/gabia_key /home/user/deploy/setup_gabia_server.sh \
    $GABIA_USER@$GABIA_HOST:~/
ssh -i ~/.ssh/gabia_key $GABIA_USER@$GABIA_HOST \
    'TSAK_REMOTE=tsak TSAK_PORT=5071 bash setup_gabia_server.sh --dry-run'

# 실제 적용
ssh -i ~/.ssh/gabia_key $GABIA_USER@$GABIA_HOST \
    'sudo -E TSAK_REMOTE=tsak TSAK_PORT=5071 bash setup_gabia_server.sh'
```
등록되는 것: systemd 유닛(`current` 참조 + `TSAK_STATE_DIR`), nginx
리버스프록시(80→5071, 512M 업로드, Range 스트리밍), logrotate(일 14개).

### 3-4. TLS
```bash
ssh -i ~/.ssh/gabia_key $GABIA_USER@$GABIA_HOST
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d tsak.kr -d www.tsak.kr
```

### 3-5. 확인
```bash
curl -I https://tsak.kr/                    # 200
curl -s https://tsak.kr/api/health          # {"ok":true,...}
curl -I https://tsak.kr/qr.html             # 200
```

---

## 4. 일상 배포 (자동 업로드)

```bash
bash /home/user/deploy/deploy_gabia.sh
```

자동으로 하는 검사:
1. 사전 스냅샷 (실패하면 **업로드 중단** — 안전 우선)
2. 빌드 후 `qr.html` md5 + 서비스워커 오버라이드 확인
3. 전환 **전** 상태 디렉터리 지문 기록
4. 원자적 전환 (`ln -sfn` + `mv -T` — 반쯤 섞인 상태 노출 없음)
5. 헬스체크 15회 → 실패 시 **직전 릴리스로 자동 롤백**
6. 전환 **후** 상태 지문 비교 → **사용자 자산**(세션·업로드)이 달라지면 경고
   (캐시 파일 증가는 정상이므로 무시 — 오탐으로 진짜 경보를 흐리지 않는다)
7. 릴리스 폴더에 상태 누출 검사
8. 릴리스 정리 (최근 5개 유지. **방금 만든 릴리스와 current 는 무조건 보존**)
9. 스모크 테스트 7종 (`/`, `/qr.html`, `/memorial.html`,
   `/scoutsown.html`, `/version.json`, `/api/health`, `/api/config`=401)
   + `main.dart.js` 서빙 + 배포물의 SW 오버라이드 → 실패 시 자동 롤백

---

## 5. 롤백 — 두 가지 경로

### 5-1. 원격 롤백 (직전 릴리스로)
```bash
bash /home/user/deploy/deploy_gabia.sh --rollback
```
`current` 심볼릭 링크를 `releases/` 의 두 번째로 최신으로 되돌리고 재시작.
**상태(`shared/state`)는 건드리지 않으므로 세션·업로드가 그대로 살아 있습니다.**
헬스체크는 최대 30초 재시도합니다(프록시 기동에 9~22초 소요).

> **⚠️ 이 경로는 2026-11-20 까지 한 번도 동작한 적이 없었습니다.**
> 롤백 블록만 변수 대입이 `R='\$HOME/...'` (single quote) 라 `$HOME` 이
> 글자 그대로 남았고, `readlink`·`ls` 가 실패해 항상
> `✗ 이전 릴리스가 없습니다` 로 끝났습니다. **장애 때 눌러도 아무 일이
> 일어나지 않는 상태**였습니다. 현재는 `R=\$HOME/...` 로 고쳐졌고,
> 리허설(`tests/rehearse_deploy.sh`)이 A→B→A 전환을 실측합니다.

### 5-2. 로컬 스냅샷 복원 (더 과거로)
```bash
bash /home/user/deploy/restore_snapshot.sh --list
bash /home/user/deploy/restore_snapshot.sh --latest
bash /home/user/deploy/restore_snapshot.sh 20261120_074224
```
스냅샷 위치: `/home/user/.tsak_snapshots/<stamp>/`
포함: `gabia_deploy.tar.gz`(372M), `proxy/`(5파일), `config_gabia.json`(600),
`gdrive_sa.json`, `SHA256SUMS.txt`. 12개 보관.

복원 절차: 무결성 검사 → **안전 스냅샷 먼저 생성** → 임시 디렉터리에 전개 →
필수 5파일 확인 → 교체 → 사후 검증(web 개수, git 커밋, qr.html md5, SHA-256).
`--no-safety` 로 안전 스냅샷을 건너뛸 수 있지만 **권장하지 않습니다.**

---

## 6. 절대 하지 말 것

| 금지 | 이유 |
|---|---|
| 상태 디렉터리를 릴리스 안에 두기 | 롤백 = 데이터 손실 |
| `TSAK_STATE_DIR` 없이 배포 | 위와 같음. 기동 로그에 경고가 뜬다 |
| `pkill -f proxy_server` 를 인라인 셸에서 | **호출한 셸이 같이 죽는다** → `clean_restart.sh` 사용 |
| 비밀번호를 스크립트/argv/git 에 | 유출 |
| `config.json` 을 git 에 커밋 | 평문 마스터 비밀번호 포함 (실제 사고 있었음) |
| 원격에서 `rsync --delete` 로 web 증분 | 빌드에 없는 파일을 지운다 → 전체 번들 사용 |
| `tar -tzf ... \| grep -q` + `pipefail` | SIGPIPE(141) 로 오탐 실패 → 목록을 파일로 먼지고 `grep -qxF` |

---

## 7. 알려진 미해결 위험

| 위험 | 내용 | 상태 |
|---|---|---|
| `nas.pw` == `auth.app` | 같은 비밀번호를 씀. 가비아→NAS 구간이 공인 인터넷을 지나는데 TLS 검증이 꺼져 있음(`CERT_NONE`) | **미수정 · 권고: 분리 + NAS IP 허용목록** |
| `_BackendClient.write` 거짓 성공 | 로컬·백엔드 예외를 모두 삼키고 `{"ok": True}` 반환 | 미수정 (소유자 결정 대기) |
| `_save_json` 반환값 무시 | 위 거짓 성공을 받아도 저장 성공으로 처리 | 미수정 |
| `_bwrite_bg` IndexError | `slot = [content_bytes]` 인데 `prev[1] = ...` → 조용히 유실. 현재 도달 불가 | 미수정 (1줄) |
| gdrive_store 62.6MB 여유 | 축출이 원본/백업 구분 없이 `st_atime` 기준 | 미수정 |
| NAS `backups/` 413개 무제한 | 평균 57.9MB/일 | 미수정 (보존정책 제안됨) |

### 7-1. 리허설이 잡아낸 결함 (2026-11-20)

실제 서버 자격증명이 없어 `tests/rehearse_deploy.sh` 로 **전 과정을 로컬에서
실행**해 본 결과, 문서만 읽어서는 절대 보이지 않던 결함 5건이 나왔습니다.
전부 수정·실측 완료입니다.

| # | 결함 | 증상 (고치기 전) |
|---|---|---|
| 1 | 롤백 블록의 single-quote 변수 | 롤백을 눌러도 `✗ 이전 릴리스가 없습니다` — **아무 일도 안 일어남** |
| 2 | `--rollback` 이 무의미한 3초 대기 후 1회 curl | 정상 기동 중인데도 `헬스 실패` 거짓 경보 |
| 3 | 릴리스 정리 `tail -n +6` | 최신순 정렬이라 **방금 만든 릴리스**를 삭제 → 6번째 배포에서 롤백 불가 |
| 4 | 상태 지문이 캐시 파일까지 셈 | 정상 배포인데 `데이터 유실 가능성` 경고 (늑대 소리) |
| 5 | 스탬프 1초 해상도 | 1초 내 재배포 시 같은 릴리스에 덮어써 롤백 대상 소멸 |

추가로 고친 것: `create` 단계의 죽은 코드(`\$R_STAMP` — 원격에 없는 변수),
지문 `find` 식의 우선순위/`-maxdepth` 오용(하위 폴더 업로드 누락).
원격 명령에 백틱을 쓰면 **명령 치환으로 실행**된다는 것도 이때 확인했습니다
(`Is a directory` 오류). 앞으로 원격 문자열에는 백틱 금지.

---

## 8. 파일 지도

| 파일 | 역할 |
|---|---|
| `deploy/deploy_gabia.sh` | 빌드→검증→업로드→원자적 전환→자동 롤백 |
| `deploy/setup_gabia_server.sh` | 서버 최초 세팅 (systemd/nginx/logrotate). `--dry-run` 지원 |
| `deploy/backup_snapshot.sh` | 로컬 스냅샷 생성 + 무결성 검증 |
| `deploy/restore_snapshot.sh` | 스냅샷 복원 (안전 스냅샷 선행) |
| `deploy/prepare_gabia_config.py` | 가비아용 config 생성 (masterHash만) |
| `deploy/tests/test_release_switch.sh` | **핵심 시험** — 릴리스 전환 데이터 보존 |
| `deploy/tests/rehearse_deploy.sh` | **배포 전체 리허설** — 가짜 ssh/scp/systemctl 로 로컬 가상 서버에 끝까지 돌린다 |
| `deploy/tests/sitecustomize.py` | 시험 중 NAS 쓰기 차단 |
| `nas_proxy/proxy_server.py` | 프록시 본체. `TSAK_STATE_DIR` 지원 |
| `nas_proxy/clean_restart.sh` | 안전한 재시작 (pkill 금지 대체) |
