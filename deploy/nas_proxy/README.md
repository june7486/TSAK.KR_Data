# nas_proxy (NAS 프록시 서버 사본)

이 폴더는 `/home/user/nas_proxy` 에서 실행되는 NAS 프록시의 **핵심 서버 코드 사본**입니다.
(버전관리 목적: 서버 코드가 git 밖에 있어 변경 이력이 남지 않던 문제를 보완)

- `proxy_server.py` — HTTP 프록시 서버 (정적 서빙 + `/api/*`)
- `nas_lib.py` — Synology DSM FileStation 클라이언트

## ⚠️ 중요 — 파일 업로드 손상 버그 (2026-09-26 수정)
`nas_lib.write_stream()` 의 본문 생성기(`_Body.read`)가 **EOF 를 알리지 못하고
boundary tail(`------TSAKSTREAM9f13--`)을 무한 반복 반환**하던 버그가 있었습니다.
그 결과 이 경로로 업로드된 파일이 multipart 경계 문자열로 **오염 저장**되었습니다.
→ `_finished` 플래그를 추가해 본문 끝에서 스트림을 정상 종료하도록 수정.

서버에서 재현/검증:
```python
nas.write_stream(dest, chunks, size=N)  # 이제 정상 바이트 왕복 확인됨
```

## 서버 설정 (config.json)
`config.json` 은 **비밀번호가 포함**되어 이 저장소에 포함하지 않습니다.
서버에는 `/home/user/nas_proxy/config.json` 로 별도 배치하세요.
