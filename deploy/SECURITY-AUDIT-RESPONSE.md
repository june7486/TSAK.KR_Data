# TSAK 보안 감사 대응 (v3 · 2026-09-26)

> 감사 보고서 `TSAK_보안감사_긴급조치_v3.pdf` 의 지적 항목에 대한 **서버·클라이언트 수정 내역**입니다.
> 개인정보·재무정보 무인증 노출(치명) 항목을 우선 차단하고, 심층 방어를 추가했습니다.

## 1. 조치 요약 (재현 → 차단)

| 항목 | 감사 지적 | 조치 | 검증 결과 |
|------|-----------|------|-----------|
| **F01** 회원 API 무인증 응답 | Cookie/Authorization 없이 회원 JSON 반환 | 서버측 세션토큰 인증 도입. 세션 없으면 `401` | `GET /api/members` → **401** |
| **F02** 재무 API 무인증 + 다른 출처 읽기 | 무인증 재무 JSON + `ACAO:*` | 재무는 **관리자·마스터 전용**, CORS 허용목록화(**정적 서빙 경로 포함** `*` 전량 제거) | `GET /api/finance` → **401**, evil Origin → ACAO 없음(정적 index.html 도 동일) |
| **F03** 정적 배포 회원자료 | `assets/.../members_seed.json` 공개 | 정적 경로 **차단(404)** + 시드 데이터 **가상데이터로 교체** | `GET .../members_seed.json` → **404** |
| **F04** 백업 목록 무인증 | 백업 이름·크기 반환 | 관리자·마스터 전용 | `GET /api/backups` → **401** |
| **F05/F06** 방어 헤더 부재 | CSP/HSTS/XCTO 등 없음 | CSP·X-Frame-Options·nosniff·Referrer-Policy 추가 | 응답 헤더 확인 |

## 2. 핵심 구현

### 2.1 서버측 세션 인증 (`proxy_server.py`)
- 로그인 성공 시 **1회용 세션토큰**(`secrets.token_urlsafe(32)`) 발급, 8시간 TTL.
- 웹은 **SameSite=Strict 쿠키**(`tsak_sid`)로 자동 전송, 비웹은 `X-TSAK-Session` 헤더.
- `GET/POST /api/*` 전 경로에 인증 게이트. 로그인·세션발급·health 만 예외.
- 관리자 전용(`/api/admin/*`, `/api/backup*`, `/api/restore`, `/api/finance*`, `/api/files`)은 tier 추가 검사.

### 2.2 역할별 최소 항목 (데이터 스코핑)
- **관리자/마스터**: 전체.
- **개인/비인가자**: `number`·`loginId`·`phone` 로 본인 **1건만** 반환 + `personalPassword`·`memo`·`address`·`photoPath` **제거**.
- **재무**: 관리자·마스터 외에는 빈 구조(`restricted:true`).

### 2.3 정적 회원자료 제거 (F03)
- 실명 2,186건·전화 1,332건이 담긴 `members_seed.json` 을 **가상 인명으로 전면 교체**( PII 0건 ).
- 프록시가 `*_seed.json`·`members.json` 등 정적 요청을 **404 차단**.

### 2.4 클라이언트 (`nas_api.dart` · `app_state.dart`)
- 모든 요청에 세션토큰 헤더 자동 첨부.
- 로그인 응답의 `sid` 저장, 세션 복원 시 토큰 복원/재발급.
- 로그아웃 시 서버 세션 폐기(`/api/logout`) + 토큰 삭제.
- 로컬 검증(예: 개인 `415!@@`)으로 세션이 비는 통합 갭 보완 → 로그인 후 세션 미보유 시 자동 발급.

### 2.5 권한 상승 차단
- `/api/session/grant` 에서 **master 등급은 마스터 비번 확인값 없이는 발급 불가**.
- 개인 QR(`?access=personal`)는 서버에 **personal** 로만 세션 발급(영구마스터라도 권한 상승 불가).

## 3. 수정 후 통과 기준 대조 (감사 3단계)

| 시험 | 기대 | 결과 |
|------|------|------|
| 로그인 없는 회원·재무 요청 | 401/403 | ✅ 401 |
| 다른 출처 민감 API 읽기 | 출처 차단 + 서버 인증 유지 | ✅ evil Origin → ACAO 없음 |
| 개인 A가 B 자료 요청 | 서버가 거부 | ✅ 개인 세션 → 본인 1건만 |
| 정적 회원자료 | 민감자료 없음 | ✅ 404 + 가상데이터 |
| 백업 목록 | 승인 역할 한정 | ✅ 401 |

## 4. 남은 과제 (운영자 판단 필요)

- **운영 계정 분리·관리자 추가인증(MFA)** 권고.
- **DB·백업 암호화**, 감사 로그 무결성.
- **대표 도메인(tsak.kr) 인증서 이름 불일치·HTTPS 리디렉션** 수정.
- **비밀번호 교체 및 세션 회수**(유출 가능성 대비).
- **AI 인식 기능의 외부 전송 정책** 확인(원본 명단·은행자료 외부 전송 여부).
- 과거 **외부 반출·침해 여부** 접속기록 대조 및 신고·통지 의무 검토.

> ⚠️ 이 문서는 조치 내역 기록이며, 보안 인증이나 법률 의견이 아닙니다.
> 민감 응답 원문·증거는 내부 담당자만 취급하십시오.

## 5. 최종 검증 로그 (2026-09-26, 배포본 기준)

| 시험 | 명령 | 결과 |
|------|------|------|
| 무인증 회원/재무/백업/관리/파일 | `GET /api/{members,finance,backups,admin/state,files}` | 전부 **401** |
| 정적 시드 차단(파일은 존재) | `GET /assets/assets/data/members_seed.json` (250KB 실존) | **404** |
| 정상 정적자산 대조군 | `/assets/AssetManifest.bin`, `/main.dart.js` | **200** |
| 정적 CORS 허용목록 | `index.html` + `Origin: https://evil.example.com` | ACAO **없음** |
| 정적 CORS 동일출처 | `index.html` + `Origin: http://localhost:5071` | ACAO **자기 Host만** |
| 정적 CORS 허용목록 | `index.html` + `Origin: https://tsak.kr` | ACAO **허용** |
| 마스터 세션 범위 | `X-TSAK-Session` → `/api/members` | **2,186건** / finance 200 |
| 개인 세션 범위 | 인가번호 개인 세션 → `/api/members` | **본인 1건** / finance **401** |
| 권한 상승 차단 | `POST /api/session/grant {tier:master}` (무비번) | **401** |
| 브라우저 전 구간 | Playwright 로그인→회원조회 | 로드 정상 · **JS 에러 0** · 실패요청 0 |

커밋: `01e5b17`(본조치) → `8e75814`(정적 CORS 와일드카드 제거·F02 완결)

## 6. 기능 검증 로그 (2026-09-26, 요청 K · QR 자동로그인)

| 시험 | 방법 | 결과 |
|------|------|------|
| 행사관리 통합목록(union) | `GET /api/event/list2?media=1` | events.json + 개인프로필 합집합, `defined`·`createdBy`·`memberCount`·`media` 포함 |
| 연도 필수(생성) | `POST /api/event/create` (연도 없음) | **400** 거부 / 연도 있으면 ok |
| 삭제 왕복(net-zero) | `event/create`→`event/delete` | members.json 해시 **BEFORE==AFTER**(회원 데이터 0변경), events.json 원복 |
| 개인프로필 캐스케이드 | 합성데이터 `_ev_remove_member_events` | 정확 일치만 제거(부분일치 오탐 0), True만 대상 |
| 게스트/개인 스코프 | `_scope_members`/`_redact_member`/`_scope_finance` | 본인 1건 · 민감필드 제거 · 재무 차단 |
| 티어 차단(HTTP) | 개인 세션 → `/api/{finance,backups,admin/state}` | 전부 **401** |
| 개인 QR 자동로그인 | `?access=personal&no=1` (Playwright) | session/grant 200 → `/api/members` **200(본인1건)** → 본인 편집화면 렌더, **JS 에러 0** |
| 관리자 회귀 | Playwright 로그인→회원조회 | 정상 · **JS 에러 0** |

커밋: `b1ea978`(요청 K) → `2b5c0e9`(QR 자동로그인/게스트 수정)

> ⚠️ **주의**: 본 검증은 운영 NAS(`TSAK_인가자관리`)에 연결된 상태에서 **읽기/무해**
> 방식으로만 수행했습니다. 회원 프로필을 변경하는 파괴적 테스트는 하지 않았고,
> events.json 왕복 테스트도 회원 데이터 무손상(net-zero)을 해시로 확인했습니다.


## 7. 성능 개선 로그 (2026-09-27, 초기 로딩 속도)

요청: "초기 로딩 속도 좀 올려줘"

**진단된 병목 2가지**
1. `main()` 이 첫 프레임 이전에 `repo.init()`(NAS 네트워크) 과 `finance.load()` 를 **동기 대기** → 흰 화면 지연
2. 프록시(`nas_lib`)가 요청마다 **새 TLS 연결**을 열어 요청당 ~1.25–2.0s 고정 오버헤드

**조치**
| 위치 | 변경 | 효과 |
|------|------|------|
| `lib/main.dart` | `unawaited(repo.init())`, `unawaited(finance.load())` — UI 먼저 렌더 | 첫 프레임 조기 표시 |
| `nas_proxy/nas_lib.py` | 전역 keep-alive `HTTPSConnection` 풀(`_CONN`, `_CONN_TTL=100s`, `_conn_post`) 도입. `call`/`read_bytes`/`_login`/`_post` 가 연결 재사용, 끊김 시 1회 재시도. **업로드(`write`/`write_stream`)는 대용량 안정성 위해 기존 urllib 유지** | 요청 지연 2.05s→0.43s |

**측정 (헤드리스 크로미움, viewport 430×932)**
| 지표 | 이전 | 이후 |
|------|------|------|
| 콜드 첫 프레임 | 8.2s | **6.2s** (−24%) |
| 웜 첫 프레임 | 4.6s | **2.66s** (−42%) |
| `/api/health` | 1.29s | **0.49s** |
| `/api/members` | 2.85s | **0.81–1.98s** |
| members.json read (bench) | 2.05s | **0.43s** |

**무결성**: Playwright 스모크 `hasCanvas=true, loggedIn=true, jsErrors=0, failedReq=0`. `flutter analyze lib/main.dart` 무이슈. `build/web` 재빌드 성공(70.6s).

> ⚠️ keep-alive 는 연결 풀 **TTL 100초** 후 자동 교체되며, 프록시는 스레드 기반이라 공유 커넥션 접근을 락(`_CONN_LOCK`)으로 보호합니다. 실패 시 기존 경로로 자연 폴백합니다.

## 8. 성능 개선 로그 — 2차 "최대한 더 줄여줘" (2026-09-27)

정밀 진단(리소스 워터폴 + 서버 지연 분해)으로 2차 최적화를 수행했다.

**발견한 병목**
1. **앱 테마가 폰트패밀리를 미지정** → 웹에서 기본 Roboto 사용 → 한글 글리프 부재로 Flutter 가 런타임에 **Google Fonts(Noto Sans KR) 9회 추가 다운로드**(~130KB, 외부 왕복) ← 최대 병목
2. 스플래시 CSS 가 `'Noto Sans KR'` 참조 → 불필요 외부 요청 유발 가능성
3. 폰트(685KB)·main.dart.js(1.27MB) 가 **첫 프레임 직전에야 요청**되어 임계경로에 직렬로 놓임
4. 스플래시 로고가 원본 124KB PNG 를 사용
5. 프록시가 요청마다 5MB JS 를 **실시간 압축**(CPU 경쟁)

**조치**
| 위치 | 변경 |
|------|------|
| `lib/theme/app_theme.dart` | 기본 `fontFamily: 'NanumGothic'` + 폴백 지정 → **외부 폰트 요청 0회** |
| `web/index.html` | NanumGothic×2·MaterialIcons **폰트 프리로드**, 스플래시 CSS 시스템폰트화, gstatic preconnect, 경량 스플래시 로고 |
| `web/tsak_emblem_splash.png` | 신규(216px, 41KB) — 원본 124KB 대체 |
| `nas_proxy/proxy_server.py` | **압축 결과 디스크/메모리 캐시**(`_get_compressed`) + **부팅 시 사전압축**(`_precompress_static`, 18파일) + `TCP_NODELAY` |
| `nas_proxy/nas_lib.py` | `warm()` — 부팅 시 NAS 연결/로그인 프리워밍 |

> ⚠️ `--no-web-resources-cdn`(canvaskit 로컬 서빙)은 **시도 후 되돌림**: 로컬은 시간당제한이던 CDN 대비 실측 더 느렸음(전송량 3.7→6.5MB, 콜드 6.1→7.6s). CDN 유지가 정답.

**측정 (헤드리스 크로미움 430×932)**
| 지표 | 1차 후 | 2차 후 |
|------|--------|--------|
| 콜드 첫 프레임 | 6.21s | **5.96s** |
| 웜 첫 프레임 | 2.35s | **2.24s** |
| 총 요청 수 | 28 | **21 (−25%)** |
| 외부 Google 폰트 요청 | 9 | **0** |
| 폰트 완료 시각 | ~5.6s | **~2.9s** |

**무결성**: 스모크 `hasCanvas/ loggedIn=true / jsErrors=0 / failedReq=0`. analyze 무이슈.

**미해결(잔여)**: 프록시 요청당 **~0.47s TTFB** 가 존재(최소 HTTP 서버는 8ms). 환경 문제가 아니라 프록시 고유 현상이며 `TCP_NODELAY` 로 해소되지 않음(드문 `Connection: close` 요청에 한함). 추가 규명 필요 — 단, 실제 앱은 HTTP/1.1 keep-alive 로 여러 요청을 묶어 보내므로 실사용 영향은 제한적.
