# 🔒 "안전하지 않음" 보안경고 — 원인과 해결책 (요구#4)

> 작성: 2026-09-29 · 대상: `tsak.kr` → 샌드박스 앱 포워딩 구조

## 1. 왜 뜨나? (원인 — 실측 확정)

**결론: 포워딩(가비아) 때문이 맞습니다.** 앱·서버 잘못이 아니라 **도메인 연결 방식**의 문제입니다.

| 시험 (실제 접속) | 결과 |
|---|---|
| `http://tsak.kr/` | ✅ **200 OK** (Server: Apache) — 평문 HTTP 로만 응답 |
| `https://tsak.kr/` | ❌ **SSL 오류** — `no alternative certificate subject name matches target hostname 'tsak.kr'` |
| `https://…sandbox.novita.ai` | ✅ 정상 (유효 인증서, HTTP/2) |

- `tsak.kr` 은 **가비아 "포워딩"** 으로 샌드박스 주소로 넘기고 있습니다.
- **가비아 공식 안내(고객센터 FAQ)**: *"가비아 도메인 부가서비스 중 **파킹·포워딩 서비스는 HTTPS 연결을 지원하지 않습니다**."*
  → 즉 `tsak.kr` 에는 **SSL 인증서가 아예 없어**, 브라우저는 `http://tsak.kr` 로 접속하고 주소창에 **"안전하지 않음"** 을 표시합니다.
- 최종 목적지(샌드박스)는 HTTPS 가 정상이지만, **사용자가 처음 보는 주소(tsak.kr)가 http** 라 경고가 뜹니다.

> 참고: 목적지가 HTTPS여도 **포워딩 도메인 자체에 인증서가 없으면** 경고는 사라지지 않습니다.
> (혼합콘텐츠·코드 문제 아님 — 앱 소스에는 http:// 하드코딩·혼합콘텐츠 **0건** 확인됨)

## 2. 해결책 (택 1 — 위에서부터 권장)

### ⭐ A) Cloudflare 로 네임서버 이전 (무료·가장 안정적 · 권장)
가비아 포워딩을 끄고, 도메인 DNS를 Cloudflare로 옮기면 **무료 SSL(Universal SSL)** 이 자동 발급되어 `https://tsak.kr` 이 바로 동작합니다. 쿼리스트링도 보존됩니다.

1. https://dash.cloudflare.com 가입 → **Add site** → `tsak.kr` 입력 → **Free 플랜** 선택
2. Cloudflare가 안내하는 **네임서버 2개**를 확인
3. 가비아: `My가비아 → 도메인 통합관리툴 → tsak.kr → 네임서버 변경` 에서 위 2개로 교체(적용 최대 수십 분~48시간)
4. Cloudflare **DNS → Records** 에 `tsak.kr`·`www` 를 **Proxied(주황 구름)** 로 추가
   - 목적지로 넘기는 방식은 택1:
     - **Redirect Rules(권장)**: `Rules → Redirect Rules → Create` 에서
       `https://tsak.kr/*` → `https://5071-i0wgdg3il1ohzxyvietj8-0e616f0a.sandbox.novita.ai/$1`
       (**Dynamic** 사용 시 쿼리·경로 100% 보존, **302** 권장)
     - 또는 무료 정적 호스팅(Cloudflare Pages)에 `deploy/tigerscout_redirect/index.html` 업로드
5. `https://tsak.kr/?access=personal&no=415` 로 테스트 → 자물쇠(🔒) + 정보수정 화면
6. **Always Use HTTPS** 켜기 (`SSL/TLS → Edge Certificates`) → http 접속도 자동 https 승격

### B) 가비아 유료 SSL + 웹호스팅
- 가비아 **공유호스팅은 외부(무료) SSL 설치 불가** → **가비아 유료 SSL** 구매 후 호스팅에 적용.
- 호스팅 루트에 `deploy/tigerscout_redirect/index.html` 업로드(포워딩 대신 호스팅이 직접 응답) → 쿼리 보존.
- 비용이 들고, 샌드박스 주소가 바뀌면 `APP_BASE` 수정 필요.

### C) 자체 서버 + Nginx + Let's Encrypt(Certbot)
- 도메인을 실제 서버 IP에 물리고 `certbot --nginx -d tsak.kr` 로 **무료 인증서 자동 갱신**.
- Nginx 에서 `location / { proxy_pass https://…; }` 로 앱 중계 + `return 301 https://$host$request_uri;` 로 http→https 강제.
- 운영 이전(샌드박스 졸업) 시 가장 깔끔.

## 3. 서버측 추가 조치 (이번에 반영)

- **`proxy_server.py`**: HTTPS 로 접속한 경우 응답에 **HSTS**(`Strict-Transport-Security: max-age=31536000`) 헤더 추가.
  → 한 번 https 로 접속되면 이후 http 접속을 브라우저가 자동 https 로 승격/차단하여 경고 재발 방지.
- **앱 소스 점검**: `web/index.html`·`build/web` 에 http 혼합콘텐츠 없음(카카오 우편번호는 `//` 프로토콜 상대 → https 자동). **추가 수정 불필요.**

## 4. 요약
- **원인**: `tsak.kr` = 가비아 **포워딩**(HTTPS 미지원) → http 접속 → "안전하지 않음". **포워딩이 원인 맞음.**
- **해결**: **Cloudflare 네임서버 이전(무료·권장)** 또는 가비아 유료 SSL, 또는 자체서버+Let's Encrypt.
- **즉시 확인 팁**: 주소창에 `https://tsak.kr` 를 **직접** 입력해 보세요. 지금은 인증서가 없어 열리지 않습니다(그게 근본 원인).
