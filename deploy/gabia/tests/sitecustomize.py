"""NAS 쓰기 차단 가드 — 시험 전용.

## 왜 필요한가
릴리스 전환 시험은 프록시를 **실제로 기동**한다. 그런데 `_boot()` 안에는
"DB 파일이 없으면 기본값을 만들어 NAS 에 쓴다"는 경로가 있다. 운영 NAS 는
이미 파일이 있으므로 평소에는 실행되지 않지만, 시험에서 그 경로가 타면
운영 데이터를 건드릴 수 있다.

## 하는 일
`nas_lib.NasClient` 의 쓰기 계열 메서드를 예외로 바꾼다.
읽기(list/read/exists)는 그대로 둔다.

## 쓰는 법
    PYTHONPATH=/home/user/deploy/tests python3 -u proxy_server.py
`sitecustomize` 라는 이름이므로 인터프리터가 자동으로 import 한다.
운영에서는 PYTHONPATH 에 이 디렉터리를 넣지 않으므로 영향이 없다.
"""
import os
import sys

if os.environ.get("TSAK_TEST_NAS_READONLY") == "1":
    def _install():
        try:
            import nas_lib
        except Exception:
            return
        cls = getattr(nas_lib, "NasClient", None)
        if cls is None:
            return

        def _blocked(name):
            def _f(*a, **k):
                raise PermissionError(
                    "[test-guard] NAS 쓰기 차단: NasClient.%s — "
                    "시험은 읽기만 허용합니다" % name)
            return _f

        for name in ("write", "rename", "delete", "upload", "move",
                     "copy", "mkdir", "save"):
            if hasattr(cls, name):
                setattr(cls, name, _blocked(name))
        print("[test-guard] NAS 쓰기 차단 활성 (읽기 전용)",
              file=sys.stderr, flush=True)

    _install()
