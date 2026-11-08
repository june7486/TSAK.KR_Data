// 하단 바로가기 3분할 — Homepage / Naver Cafe / 노경하 추모관 (build #630).
//
// ## 요구 1 (2026-11-04, 원문)
//  "노경하 추모관 위치를 메인화면 하단을 3분할 하여
//   Homepage/Naver Cafe/노경하추모관 이렇게 구분하고 바로가기 링크를 넣어줘"
// ## 요구 2 (이어서)
//  "추모관 → 노경하 추모관"  (버튼 이름 변경)
//
// ## 배경 — 주소를 하드코딩하면 안 되는 이유
//  추모관은 외부 도메인이 아니라 **이 앱과 같은 웹서버의 `memorial.html`** 이다.
//  (빌드 마지막 단계에서 `web_custom_backup/` → `build/web/` 로 복사된다.)
//  운영 주소가 둘 이상이므로(novita 샌드박스 / gabia 실서버),
//  웹에서는 **현재 접속 origin** 에 `/memorial.html` 을 붙여야 어디서 열어도 맞는다.
//  네이티브(APK)에는 그 파일이 앱 안에 없으므로 NAS 공개 주소로 폴백한다.
//
// ## 배경 — 레이아웃
//  '노경하 추모관' 은 6자다. 3분할 폭(좁은 폰 약 95px)에 아이콘을 **가로로**
//  붙이면 반드시 잘린다. 그래서 아이콘을 위로 올린 Column + FittedBox 로
//  폭에 맞춰 자동 축소한다. (OutlinedButton.icon 은 아이콘이 항상 앞이라 불가)
//
// 위젯 테스트(pump)는 이 샌드박스에서 멈추므로 소스 계약 테스트로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 주석을 제거한 실제 코드만 남긴다 (주석 문구로 거짓 통과하는 것을 막는다).
String stripComments(String src) => src
    .split('\n')
    .map((ln) => ln.replaceFirst(RegExp(r'^\s*//.*$'), ''))
    .join('\n');

/// `위젯이름(` 부터 중괄호 균형으로 끝까지 뽑는다.
///
/// 주의: 시그니처에 named parameter 의 `{` 가 있으므로, **본문 시작 브레이스를
/// 먼저 찾아야** 한다. `) {` 또는 `) async {` 패턴이 본문 시작이다.
String fnBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThan(-1), reason: '$signature 를 찾지 못했습니다');
  // 시그니처 뒤 첫 ')' 다음의 '{' 가 본문 시작.
  final closeParen = src.indexOf(')', src.indexOf('(', start));
  expect(closeParen, greaterThan(-1));
  final bodyOpen = src.indexOf('{', closeParen);
  expect(bodyOpen, greaterThan(-1));
  var i = bodyOpen;
  var depth = 0;
  final buf = StringBuffer();
  for (; i < src.length; i++) {
    final ch = src[i];
    buf.write(ch);
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return stripComments(buf.toString());
}

/// `get 이름 => expr;` / `get 이름 { ... }` 형태의 getter 본문을 뽑는다.
///
/// getter 는 파라미터 `()` 가 없으므로 [fnBody] 를 쓸 수 없다
/// (본문 안의 `replaceAll(` 같은 괄호를 시그니처로 오인한다).
String getterBody(String src, String name) {
  final start = src.indexOf('get $name');
  expect(start, greaterThan(-1), reason: 'getter $name 을 찾지 못했습니다');
  final brace = src.indexOf('{', start);
  final arrow = src.indexOf('=>', start);
  // 화살표 표기 — 첫 ';' 까지
  if (arrow > -1 && (brace < 0 || arrow < brace)) {
    final semi = src.indexOf(';', arrow);
    return stripComments(src.substring(arrow, semi + 1));
  }
  // 블록 표기 — 중괄호 균형
  expect(brace, greaterThan(-1), reason: 'getter $name 본문을 찾지 못했습니다');
  var depth = 0;
  final buf = StringBuffer();
  for (var i = brace; i < src.length; i++) {
    final ch = src[i];
    buf.write(ch);
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return stripComments(buf.toString());
}

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

  group('① 라벨 — "노경하 추모관"', () {
    test('lock_screen 버튼 이름이 노경하 추모관이다', () {
      expect(lock, contains("label: '노경하 추모관'"));
      // 짧은 '추모관' 만 남아 있으면 안 된다(두 라벨이 공존하면 혼란).
      expect(
        RegExp(r"label:\s*'추모관'").hasMatch(lock),
        isFalse,
        reason: '짧은 라벨이 남아 있습니다',
      );
    });

    test('home_screen 버튼 이름도 노경하 추모관이다', () {
      expect(home, contains("label: '노경하 추모관'"));
      expect(
        RegExp(r"label:\s*'추모관'").hasMatch(home),
        isFalse,
        reason: '짧은 라벨이 남아 있습니다',
      );
    });

    test('앱 메뉴의 정식 명칭과 일치한다 (故 노경하 선배님 추모관)', () {
      // 메뉴에는 '故 노경하 선배님 추모관' 이 이미 있다.
      // 하단 버튼은 짧은 형태지만 같은 사람을 가리켜야 한다.
      expect(home, contains('노경하'));
    });
  });

  group('② 로그인 화면(lock_screen) — 3분할', () {
    test('세 개의 바로가기가 모두 있다', () {
      expect(lock, contains("label: 'Homepage'"));
      expect(lock, contains("label: 'Naver Cafe'"));
      expect(lock, contains("label: '노경하 추모관'"));
    });

    test('추모관 아이콘은 꽃(local_florist) 이다', () {
      final idx = lock.indexOf("label: '노경하 추모관'");
      expect(idx, greaterThan(-1));
      final before = lock.substring(idx - 260 < 0 ? 0 : idx - 260, idx);
      expect(before, contains('Icons.local_florist'));
    });

    test('추모관은 외부 도메인이 아니라 같은 서버의 memorial.html 이다', () {
      expect(lock, contains('/memorial.html'));
      expect(lock, isNot(contains('memorial.tigerscout')));
    });

    test('웹에서는 현재 origin 을 쓴다 (webOrigin)', () {
      final seg = getterBody(lock, '_memorialUrl');
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
      final start = lock.indexOf("label: '노경하 추모관'");
      final rowStart = lock.lastIndexOf('Row(', start);
      final seg = lock.substring(rowStart, start);
      expect(seg, contains('SizedBox(width: 6)'));
      expect(seg, isNot(contains('SizedBox(width: 10)')));
    });
  });

  group('③ 레이아웃 — 6자 라벨이 잘리지 않게', () {
    test('아이콘을 위로 올린 Column 구조다 (가로 배치 아님)', () {
      final seg = fnBody(lock, 'Widget _shortcutBtn(');
      expect(seg, contains('Column('), reason: '아이콘+6자를 가로로 두면 잘린다');
      expect(seg, contains('Icon(icon'));
      // OutlinedButton.icon 은 아이콘이 항상 앞 → 6자 라벨에 부적합
      expect(seg, isNot(contains('OutlinedButton.icon')));
    });

    test('FittedBox 로 폭에 맞춰 자동 축소한다', () {
      final seg = fnBody(lock, 'Widget _shortcutBtn(');
      expect(seg, contains('FittedBox'));
      expect(seg, contains('BoxFit.scaleDown'));
      expect(seg, contains('softWrap: false'));
    });

    test('home_screen 버튼도 같은 Column + FittedBox 규칙을 따른다', () {
      final seg = fnBody(home, 'Widget _homeShortcutButton(');
      expect(seg, contains('Column('));
      expect(seg, contains('FittedBox'));
      expect(seg, contains('BoxFit.scaleDown'));
      expect(seg, isNot(contains('OutlinedButton.icon')));
    });

    test('최소 높이 52 로 두 줄(아이콘+글자)이 들어간다', () {
      expect(fnBody(lock, 'Widget _shortcutBtn('),
          contains('minimumSize: const Size(0, 52)'));
      expect(fnBody(home, 'Widget _homeShortcutButton('),
          contains('minimumSize: const Size(0, 52)'));
    });

    test('_shortcutBtn 은 _openExternal 로 새창/브라우저에서 연다', () {
      final seg = fnBody(lock, 'Widget _shortcutBtn(');
      expect(seg, contains('_openExternal(url)'));
    });

    test('_homeShortcutButton 은 openUrlInNewTab 으로 연다', () {
      final seg = fnBody(home, 'Widget _homeShortcutButton(');
      expect(seg, contains('openUrlInNewTab(url)'));
    });
  });

  group('④ 메인화면(home_screen) — 같은 3분할', () {
    test('세 개의 바로가기가 모두 있다', () {
      expect(home, contains("label: 'Homepage'"));
      expect(home, contains("label: 'Naver Cafe'"));
      expect(home, contains("label: '노경하 추모관'"));
    });

    test('추모관 주소 getter 가 있다', () {
      final seg = getterBody(home, '_memorialShortcutUrl');
      expect(seg, contains('webOrigin()'));
      expect(seg, contains('/memorial.html'));
    });

    test('네이티브 폴백 주소가 lock_screen 과 동일하다', () {
      String fallback(String src) {
        final m = RegExp(r"_memorialFallbackUrl\s*=\s*\n?\s*'([^']+)'")
            .firstMatch(src);
        return m?.group(1) ?? '';
      }

      final a = fallback(lockRaw);
      final b = fallback(homeRaw);
      expect(a, isNotEmpty, reason: 'lock_screen 폴백 주소를 찾지 못했습니다');
      expect(b, isNotEmpty, reason: 'home_screen 폴백 주소를 찾지 못했습니다');
      expect(a, equals(b), reason: '두 화면의 폴백 주소가 다르면 한쪽만 깨진다');
    });
  });

  group('⑤ 배포 산출물 — memorial.html 이 실제로 서빙되는 위치', () {
    test('웹 커스텀 백업에 memorial.html 이 있다', () {
      final f = File('/home/user/web_custom_backup/memorial.html');
      expect(f.existsSync(), isTrue,
          reason: '이 파일이 없으면 추모관 링크가 404 가 된다');
      expect(f.lengthSync(), greaterThan(1000));
    });
  });
}
