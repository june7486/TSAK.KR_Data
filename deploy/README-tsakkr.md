# tsak.kr → TSAK 앱 포워딩 (QR 딥링크 필수)

## 문제
tsak.kr(가비아)이 앱을 **frameset(마스킹 포워딩)** 으로 감싸면
`?access=personal&no=415` 같은 **쿼리스트링이 전달되지 않는다.**
→ QR 스캔 시 정보수정 페이지로 못 가고 로그인 화면만 뜬다.

## 해결 (2가지 중 하나)

### 방법 A (권장) — 일반(리다이렉트)
1. 가비아 포워딩을 **"일반(리다이렉트)"** 로 변경 (URL: 실제 앱 주소)
2. 웹 호스팅 루트의 index.html을 이 폴더의 `index.html` 로 교체
   (location.search + location.hash 를 100% 보존)

### 방법 B — frameset 유지 시
frameset은 정적 HTML로는 쿼리 전달이 불가하므로 **PHP** 필요:
```php
<?php
$q = $_SERVER['QUERY_STRING'] ?? '';
header('Location: https://실제앱주소/'.($q ? "?$q" : ''));
```
정적 호스팅이면 방법 A를 쓰는 것이 가장 안전하다.

## 확인
- `https://tsak.kr/?access=personal&no=415` 접속 → 바로 "인가자 편집" 페이지가 떠야 함
- 앱: 설정 → "QR 공개 주소" = `https://tsak.kr` 로 저장되어 있어야 함
