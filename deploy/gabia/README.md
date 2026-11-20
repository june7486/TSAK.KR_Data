# 가비아 이전 배포 스크립트 (사본)

이 폴더는 `/home/user/deploy/` 에 있는 배포 도구의 **버전관리용 사본**입니다.

## 왜 사본을 두는가

실제 작업 위치는 `/home/user/deploy/` 인데, 그 경로는 **git 저장소 밖**입니다.
서버 이전 스크립트가 샌드박스 디스크 한 곳에만 존재하면, 디스크가 초기화되는
순간 "가비아로 옮기는 방법" 자체가 사라집니다. 그래서 원격 저장소가 붙어 있는
이 저장소에 사본을 둡니다.

## ⚠️ 사본은 조용히 낡는다

`deploy/nas_proxy/` 가 정확히 그 사고를 겪었습니다. 2026-10-02 사본이 그대로
남아 실제 코드(1,450KB)보다 2.5배 작은 585KB 프록시가 커밋되어 있었습니다.
재해 복구 때 이걸 믿고 되돌리면 **1년 전 서버가 살아납니다.**

같은 일을 반복하지 않으려면, 배포 스크립트를 고친 직후 아래로 동기화하세요.

```bash
cd /home/user
cp -f deploy/deploy_gabia.sh        flutter_app/deploy/gabia/
cp -f deploy/setup_gabia_server.sh  flutter_app/deploy/gabia/
cp -f deploy/backup_snapshot.sh     flutter_app/deploy/gabia/
cp -f deploy/restore_snapshot.sh    flutter_app/deploy/gabia/
cp -f deploy/prepare_gabia_config.py flutter_app/deploy/gabia/
cp -f deploy/RUNBOOK_가비아이전.md    flutter_app/deploy/gabia/
cp -f deploy/tests/*.sh deploy/tests/*.py flutter_app/deploy/gabia/tests/
```

동기화 후 차이를 확인합니다 (출력이 없어야 정상):

```bash
for f in deploy_gabia.sh setup_gabia_server.sh backup_snapshot.sh restore_snapshot.sh; do
  diff -q /home/user/deploy/$f /home/user/flutter_app/deploy/gabia/$f
done
```

## 파일

| 파일 | 역할 |
|---|---|
| `deploy_gabia.sh` | 빌드→검증→업로드→원자적 전환→자동 롤백 |
| `setup_gabia_server.sh` | 서버 최초 세팅 (systemd/nginx/logrotate). `--dry-run` 지원 |
| `backup_snapshot.sh` | 로컬 스냅샷 생성 + 무결성 검증 |
| `restore_snapshot.sh` | 스냅샷 복원 (안전 스냅샷 선행) |
| `prepare_gabia_config.py` | 가비아용 config 생성 (평문 대신 masterHash 만) |
| `RUNBOOK_가비아이전.md` | **먼저 읽을 것.** 순서·롤백·금지사항·알려진 위험 |
| `tests/rehearse_deploy.sh` | 자격증명 없이 전 과정을 로컬 가상 서버에서 실행 |
| `tests/test_release_switch.sh` | 릴리스 교체가 데이터를 보존하는지 실측 |
| `tests/sitecustomize.py` | 시험 중 NAS 쓰기 차단 |

## 자격증명이 없다면

`tests/rehearse_deploy.sh` 를 돌리세요. 가짜 `ssh`/`scp`/`systemctl` 을 세워
`/tmp` 아래 가상 서버에서 배포·전환·롤백을 **실제로 실행**합니다.
운영 프록시(5071)는 건드리지 않습니다(가상 서버는 5098).

```bash
bash tests/rehearse_deploy.sh
```

이 스크립트는 "문서상 맞는 것"이 아니라 "실제로 도는 것"을 확인합니다.
2026-11-20 에 이 리허설로 **롤백이 한 번도 동작한 적 없던 결함**을 잡았습니다.
