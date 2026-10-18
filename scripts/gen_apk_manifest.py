#!/usr/bin/env python3
"""APK 원격 업데이트용 매니페스트(`apk.json`)를 생성한다.

빌드된 APK 의 메타데이터(버전·크기·SHA-256)를 읽어, 정적 서빙 폴더
(`build/web`)에 `apk.json` 과 함께 APK 사본을 배치한다.

앱(안드로이드)은 실행 시 `<서버주소>/apk.json` 을 조회해
  · build > 현재 kBuildNumber 이면  → 새 APK 다운로드·설치 안내
  · sha256 로 다운로드 무결성 검증
한다.

사용:
  python3 scripts/gen_apk_manifest.py                 # build/web 에 배치(기본)
  python3 scripts/gen_apk_manifest.py /경로           # 정적폴더 지정
  APK_NAME=TSAK.KR.apk python3 scripts/gen_apk_manifest.py
"""
import hashlib
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


def read_build_info():
    """build_info.g.dart 에서 빌드 넘버·버전·커밋을 읽는다."""
    gi = os.path.join(ROOT, "lib", "services", "build_info.g.dart")
    txt = open(gi, encoding="utf-8").read()
    m = re.search(r"kBuildNumber\s*=\s*(\d+)", txt)
    build = int(m.group(1)) if m else 0
    c = re.search(r"kCommit\s*=\s*'([^']*)'", txt)
    commit = c.group(1) if c else ""
    # 앱 버전(1.0.0) — app_config.dart
    ac = os.path.join(ROOT, "lib", "services", "app_config.dart")
    ver = "1.0.0"
    try:
        t = open(ac, encoding="utf-8").read()
        mv = re.search(r"appVersion\s*=\s*'([^']*)'", t)
        if mv:
            ver = mv.group(1)
    except Exception:
        pass
    return build, ver, commit


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    static_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, "build", "web"
    )
    apk_src = os.path.join(
        ROOT, "build", "app", "outputs", "flutter-apk", "app-release.apk"
    )
    if not os.path.isfile(apk_src):
        raise SystemExit(f"APK 를 찾을 수 없습니다: {apk_src}\n"
                         f"먼저 'flutter build apk --release' 를 실행하세요.")
    os.makedirs(static_dir, exist_ok=True)

    apk_name = os.environ.get("APK_NAME", "TSAK.KR_Fold7.apk")
    apk_dst = os.path.join(static_dir, apk_name)
    shutil.copyfile(apk_src, apk_dst)

    build, ver, commit = read_build_info()
    size = os.path.getsize(apk_dst)
    digest = sha256_of(apk_dst)

    notes = os.environ.get("APK_NOTES", "")
    manifest = {
        "build": build,
        "build_number": build,
        "version": f"{ver}+{build}",
        "url": apk_name,          # 상대경로 → 앱이 서버주소 기준으로 절대화
        "sha256": digest,
        "size": size,
        "commit": commit,
        "notes": notes,
    }
    out = os.path.join(static_dir, "apk.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print(f"✓ apk.json 생성: {out}")
    print(f"   build={build}  version={manifest['version']}  "
          f"size={size:,}  sha256={digest[:16]}…")
    print(f"   apk  사본: {apk_dst}")


if __name__ == "__main__":
    main()
