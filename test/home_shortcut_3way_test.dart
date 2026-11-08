// 하단 바로가기 3분할 — Homepage / Naver Cafe / 故 노경하 추모관 (build #604).
//
// ## 요구 (2026-11-04, 사용자 원문)
//  "노경하 추모관 위치를 메인화면 하단을 3분할 하여
//   Homepage/Naver Cafe/노경하추모관 이렇게 구분하고 바로가기 링크를 넣어줘"
//
// ## 배경 — 추모관 주소를 하드코딩하면 안 되는 이유
//  추모관은 외부 도메인이 아니라 **이 앱과 같은 웹서버의 `memorial.html`** 이다.
//  (빌드 마지막 단계에서 `web_custom_backup/` → `build/web/` 로 복사된다.)
//  운영 주소가 둘 이상이므로(novita 샌드박스 / gabia 실서버),
//  웹에서는 **현재 접속 origin** 에 `/memorial.html` 을 붙여야 어디서 열어도 맞는다.
//  네이티브(APK)에는 그 파일이 앱 안에 없으므로 NAS 공개 주소로 폴백한다.
//
// 위젯 테스트(pump)는 이 샌드박스에서 멈추므로 소스 계약 테스트로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 주석을 제거한 실제 코드만 남긴다 (주석에 적힌 문구로 거짓 통과하는 것을 막는다).
String stripComments(String src) => src
    .split('\n')
    .map((ln) => ln.replaceFirst(RegExp(r'^\s*//.*$'), ''))
    .join('\n');

void main() {
  late String lockRaw;
  late String lock;
  late String homeRaw;
  late String home;

  setUpAll(() {
    lockRaw = File('lib/screens/lock_screen.dart').readAsStringSync();
    lock = stripComments(lockRaw);
    homeRaw = File('lib/screens/home_screen.dart').readAsStringSync();
    home = stripComments(homeRaw);
  });

  group('① 로그인 화면(lock_screen) — 3분할', () {
    test('세 개의 바로가기가 모두 있다', () {
      expect(lock, contains("label: 'Homepage'"));
      expect(lock, contains("label: 'Naver Cafe'"));
      expect(lock, contains("label: '추모관'"));
    });

    test('추모관 아이콘은 꽃(local_florist) 이다', () {
      final idx = lock.indexOf("label: '추모관'");
      expect(idx, greaterThan(-1));
      final before = lock.substring(idx - 220 < 0 ? 0 : idx - 220, idx);
      expect(before, contains('Icons.local_florist'));
    });

    test('추모관은 외부 도메인이 아니라 같은 서버의 memorial.html 이다', () {
      expect(lock, contains('/memorial.html'));
      // 하드코딩된 외부 추모관 도메인이 없어야 한다.
      expect(lock, isNot(contains('memorial.tigerscout')));
    });

    test('웹에서는 현재 origin 을 쓴다 (webOrigin)', () {
      final idx = lock.indexOf('String get _memorialUrl');
      expect(idx, greaterThan(-1));
      final seg = lock.substring(idx, idx + 400);
      expect(seg, contains('webOrigin()'));
      expect(seg, contains('/memorial.html'));
    });

    test('네이티브(APK) 폴백 주소가 있다', () {
      expect(lock, contains('_memorialFallbackUrl'));
      final idx = lock.indexOf('_memorialFallbackUrl =');
      expect(idx, greaterThan(-1));
      final seg = lock.substring(idx, idx + 160);
      expect(seg, contains('http'));
      expect(seg, contains('/memorial.html'));
    });

    test('버튼 사이 간격이 3분할에 맞게 좁아졌다 (6px)', () {
      final start = lock.indexOf("label: '추모관'");
      expect(start, greaterThan(-1));
      // 추모관 버튼을 감싸는 Row 구간을 본다.
      final rowStart = lock.lastIndexOf('Row(', start);
      expect(rowStart, greaterThan(-1));
      final seg = lock.substring(rowStart, start);
      expect(seg, contains('SizedBox(width: 6)'));
      expect(seg, isNot(contains('SizedBox(width: 10)')));
    });

    test('좁은 버튼에서 글자가 넘치지 않게 ellipsis 처리한다', () {
      expect(lock, contains('maxLines: 1'));
      expect(lock, contains('TextOverflow.ellipsis'));
      expect(lock, contains('horizontal: 4'));
    });

    test('_shortcutBtn 은 _openExternal 로 새창/브라우저에서 연다', () {
      final idx = lock.indexOf('Widget _shortcutBtn(');
      expect(idx, greaterThan(-1));
      final seg = lock.substring(idx, idx + 900);
      expect(seg, contains('_openExternal(url)'));
    });
  });

  group('② 메인화면(home_screen) — 같은 3분할', () {
    test('세 개의 바로가기가 모두 있다', () {
      expect(home, contains("label: 'Homepage'"));
      expect(home, contains("label: 'Naver Cafe'"));
      expect(home, contains("label: '추모관'"));
    });

    test('추모관 주소 getter 가 있다', () {
      expect(home, contains('_memorialShortcutUrl'));
      final idx = home.indexOf('String get _memorialShortcutUrl');
      expect(idx, greaterThan(-1));
      final seg = home.substring(idx, idx + 400);
      expect(seg, contains('webOrigin()'));
      expect(seg, contains('/memorial.html'));
    });

    test('네이티브 폴백 주소가 lock_screen 과 동일하다', () {
      String fallback(String src) {
        final m = RegExp(
          r"_memorial(?:FallbackUrl|FallbackUrl)\s*=\s*\n?\s*'([^']+)'",
        ).firstMatch(src);
        return m?.group(1) ?? '';
      }

      final a = fallback(lockRaw);
      final b = fallback(homeRaw);
      expect(a, isNotEmpty, reason: 'lock_screen 폴백 주소를 찾지 못했습니다');
      expect(b, isNotEmpty, reason: 'home_screen 폴백 주소를 찾지 못했습니다');
      expect(a, equals(b), reason: '두 화면의 폴백 주소가 다르면 한쪽만 깨진다');
    });

    test('버튼 간격·말줄임도 동일 규칙을 따른다', () {
      final idx = home.indexOf('Widget _homeShortcutButton(');
      expect(idx, greaterThan(-1));
      final seg = home.substring(idx, idx + 1100);
      expect(seg, contains('horizontal: 4'));
      expect(seg, contains('TextOverflow.ellipsis'));
      expect(seg, contains('openUrlInNewTab(url)'));
    });
  });

  group('③ 배포 산출물 — memorial.html 이 실제로 서빙되는 위치', () {
    test('웹 커스텀 백업에 memorial.html 이 있다', () {
      final f = File('/home/user/web_custom_backup/memorial.html');
      expect(f.existsSync(), isTrue,
          reason: '이 파일이 없으면 추모관 링크가 404 가 된다');
      expect(f.lengthSync(), greaterThan(1000));
    });
  });
}
