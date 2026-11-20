#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""가비아 배포용 config.json 을 **현재 스키마에 맞게** 재생성한다.

## 왜 필요한가
`gabia_deploy/api/config.json` 은 2026-10-17 에 만들어졌고, 당시 형식은
`auth.master` **평문**이었다. 그 뒤 turn69 에서 `auth.masterHash`
(PBKDF2-SHA256) 방식으로 바뀌었지만 가비아 파일은 갱신되지 않았다.

그 상태로 가비아에 올리면:
  · 평문 마스터 비밀번호가 배포 번들에 들어간다(유출 시 즉시 위험)
  · NAS 정본(db/config.json)의 해시와 로컬 config 해시가 달라
    NAS 장애 폴백(②) 이 동작하지 않는다 → NAS 고장 = 마스터 로그인 불가

## 이 스크립트가 하는 일
  · 정본(nas_proxy/config.json)에서 **해시만** 가져온다. 평문은 만들지 않는다.
  · 경로 값(service_account, oauth_token)을 가비아 환경에 맞게 비운다.
  · mode 필드를 추가해 **어떤 저장소를 주 저장소로 쓸지** 명시한다.
  · 원본은 .bak 으로 보존한다.

## 사용
  python3 deploy/prepare_gabia_config.py --mode nas
  python3 deploy/prepare_gabia_config.py --mode gdrive   # gdrive 전환 시
"""
import argparse
import json
import os
import shutil
import sys
import time

SRC = "/home/user/nas_proxy/config.json"
DST = "/home/user/gabia_deploy/api/config.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["nas", "gdrive"], default="nas",
                    help="가비아에서 쓸 주 저장소 (기본 nas = 하이브리드)")
    ap.add_argument("--local-db", action="store_true",
                    help="DB JSON 을 가비아 로컬 디스크에서 읽고 쓰게 한다(TSAK_LOCAL_DB)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(SRC):
        sys.exit("정본 config 없음: %s" % SRC)

    src = json.load(open(SRC, encoding="utf-8"))
    src_auth = src.get("auth") or {}

    # 정본에서 해시 확보 (평문은 절대 만들지 않는다)
    mh = str(src_auth.get("masterHash") or "")
    if not mh.startswith("pbkdf2_sha256$"):
        sys.exit("정본에 auth.masterHash 가 없습니다. 먼저 마스터 비밀번호를 "
                 "해시 방식으로 설정하세요(앱에서 비밀번호 변경).")

    app_pw = str(src_auth.get("app") or "")
    if not app_pw:
        sys.exit("정본에 auth.app 이 없습니다.")

    nas = src.get("nas") or {}
    gd = src.get("gdrive") or {}

    cfg = {
        "port": int(src.get("port") or 5071),
        "backend": "nas" if a.mode == "nas" else "gdrive",
        # ── 저장소 ──────────────────────────────────────────────
        "nas": {
            "base": nas.get("base", ""),
            "user": nas.get("user", ""),
            "pw": nas.get("pw", ""),
            "base_path": nas.get("base_path", ""),
        },
        "gdrive": {
            "root_id": gd.get("root_id", ""),
            # 경로는 가비아 환경 기준으로 비운다 → 코드가 APP_ROOT 로 해석
            "base_path": gd.get("base_path", ""),
            "service_account": ("" if a.mode != "gdrive"
                                else (os.environ.get("TSAK_GDRIVE_SA") or "")),
            "client_secret": "",
            "oauth_token": "",
        },
        "auth": {
            # 평문 master 는 **쓰지 않는다**. 해시만.
            "masterHash": mh,
            "masterChangedAt": src_auth.get("masterChangedAt", ""),
            "app": app_pw,
        },
        # 메타: 이 파일이 어디서 언제 만들어졌는지 (운영 추적용)
        "_generated": {
            "by": "deploy/prepare_gabia_config.py",
            "at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "mode": a.mode,
            "source": SRC,
        },
    }

    print("== 생성 내용 (민감값 마스킹) ==")
    show = json.loads(json.dumps(cfg))
    for path in (("nas", "pw"), ("auth", "app"), ("auth", "masterHash")):
        v = show[path[0]][path[1]]
        show[path[0]][path[1]] = (v[:12] + "…(" + str(len(v)) + "자)") if v else ""
    print(json.dumps(show, ensure_ascii=False, indent=1))

    # 검증: 평문 master 가 없어야 한다
    if "master" in cfg["auth"]:
        sys.exit("내부 오류: 평문 master 가 포함됐습니다. 중단.")
    print("\n✓ 평문 master 없음 (해시만)")
    print("✓ masterHash 길이 %d자" % len(mh))
    print("✓ app 비밀번호 설정됨")

    if a.dry_run:
        print("\n(--dry-run: 파일을 쓰지 않았습니다)")
        return

    if os.path.exists(DST):
        bak = DST + ".bak_" + time.strftime("%Y%m%d_%H%M%S")
        shutil.copy2(DST, bak)
        os.chmod(bak, 0o600)
        print("\n원본 보존: %s" % bak)

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    tmp = DST + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, DST)
    print("기록: %s (chmod 600)" % DST)

    if a.local_db:
        print("\n※ TSAK_LOCAL_DB=1 로 실행하면 DB JSON 이 가비아 로컬에서 처리됩니다.")
        print("   start.sh 에 넣거나 systemd Environment 로 지정하세요.")


if __name__ == "__main__":
    main()
