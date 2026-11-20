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
        #  ## ★ 조용히 실패하던 지점 (2026-11-20)
        #   sitecustomize 는 인터프리터 부팅 시점에 실행된다. 그런데 그 시점에는
        #   `python3 -c`/스크립트의 **cwd 가 아직 sys.path 에 없어서**
        #   `import nas_lib` 가 ModuleNotFoundError 로 실패했다.
        #   아래 `except Exception: return` 이 그 오류를 **말없이 삼켰기 때문에**
        #   "가드가 켜진 줄 알았는데 실제로는 꺼져 있는" 상태가 됐다.
        #   실측: TSAK_TEST_NAS_READONLY=1 인데 NasClient 가 정상 생성되어
        #        실제 NAS 로 로그인을 시도했다 (400 응답까지 받음).
        #   → 프록시는 자기가 있는 디렉터리에서 실행되므로 그 경로를 먼저 넣는다.
        for _p in (os.getcwd(), os.path.dirname(os.path.abspath(__file__))):
            if _p and _p not in sys.path:
                sys.path.append(_p)
        try:
            import nas_lib
        except Exception as e:
            #  ## 이제는 조용히 넘어가지 않는다
            #   가드가 없으면 시험이 운영 NAS 를 건드릴 수 있다. 그건 시험의
            #   실패가 아니라 **사고**다. 소리내어 알리고 시험을 세운다.
            print("[test-guard] ✗✗ NAS 가드를 설치하지 못했습니다: %r" % (e,),
                  file=sys.stderr, flush=True)
            print("[test-guard]    TSAK_TEST_NAS_READONLY=1 인데 가드가 없습니다. "
                  "운영 NAS 보호를 위해 중단합니다.", file=sys.stderr, flush=True)
            raise SystemExit(9)
        cls = getattr(nas_lib, "NasClient", None)
        if cls is None:
            print("[test-guard] ✗✗ nas_lib.NasClient 를 찾지 못했습니다 — 중단",
                  file=sys.stderr, flush=True)
            raise SystemExit(9)

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

        #  ## ★ 차단이 새지 않던 구멍 (2026-11-20 발견)
        #   위 목록만 막으면 `NasClient(...)` 를 **만들기만 해도** 막히지 않는다.
        #   실측: TSAK_TEST_NAS_READONLY=1 인데도 `c.write(...)` 가 차단되지 않고
        #        `_login()` 까지 들어가 실제 NAS 에 로그인을 시도했다
        #        (자격증명이 틀리면 400, 맞으면 세션 생성 → 불필요한 NAS 접촉).
        #   원인: `NasClient.__init__` 이 차단 대상이 아니었기 때문.
        #   시험이 실수로 클라이언트를 만들면 그 순간 NAS 로 향한다.
        #   → 생성 자체를 막되, **읽기 전용 클라이언트**가 정말 필요할 때를 위해
        #     `allow_build=True` 우회로를 남긴다(이때도 쓰기는 여전히 차단).
        _orig_init = cls.__init__

        def _guarded_init(self, *a, **k):
            if k.pop("allow_build", False) or os.environ.get("TSAK_TEST_ALLOW_BUILD") == "1":
                return _orig_init(self, *a, **k)
            raise PermissionError(
                "[test-guard] NasClient 생성 차단 — 시험은 NAS 접촉 금지입니다 "
                "(읽기가 필요하면 TSAK_TEST_ALLOW_BUILD=1, 쓰기는 여전히 차단)")

        cls.__init__ = _guarded_init
        #  읽기 전용으로 만들어야 하는 시험을 위해 원본 생성자를 남겨둔다
        cls._tsak_orig_init = staticmethod(_orig_init)

        print("[test-guard] NAS 쓰기 차단 활성 (읽기 전용)",
              file=sys.stderr, flush=True)

    _install()
