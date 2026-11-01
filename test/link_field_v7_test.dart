// 2026-10-31 7차 요구 — 멘토/페런츠 인가 폼 3가지 변경 검증.
//
// ## 사용자 요구 (원문)
//  ① "인가일, atas 인가번호 기입란은 삭제"
//  ② "범스카우트 인가자일 경우 이름 또는 번호를 조회하면 현재 활동중인 정보가
//      조회되도록 하는 시스템을 넣음"
//  ③ "자동생성계정 → 멘토, 페런츠 추가시 전화번호 입력시 멘토 및 페런츠의 계정은
//      전화번호로 자동 생성됨"
//
// ## 왜 소스 계약 테스트인가
//  이 화면은 `AlertDialog` 안에서 상태를 갱신하는 구조라 위젯 테스트로 폼 전체를
//  띄우려면 AppState(서버·NAS)까지 필요하다. 대신 **소스가 지켜야 할 계약**을
//  직접 검증한다 — 누군가 실수로 되돌리면 즉시 실패한다.
//
//  조회 로직 자체는 아래에서 **순수 함수로 재현**해 규칙을 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/widgets/link_code_field.dart');
    expect(f.existsSync(), isTrue, reason: '대상 파일이 필요하다');
    src = f.readAsStringSync();
  });

  group('① 인가일 · ATAS 인가번호 입력란 삭제', () {
    test('화면에 "인가일" 라벨이 더 이상 없다', () {
      // labelText: '인가일' 형태로 남아 있으면 안 된다.
      expect(
        RegExp(r"labelText:\s*'인가일'").hasMatch(src),
        isFalse,
        reason: '인가일 입력란이 화면에 남아 있다',
      );
    });

    test('화면에 "ATAS 인가번호" 라벨이 더 이상 없다', () {
      expect(
        RegExp(r"labelText:\s*'ATAS 인가번호'").hasMatch(src),
        isFalse,
        reason: 'ATAS 인가번호 입력란이 화면에 남아 있다',
      );
    });

    test('인가자 스위치 안내문에서 인가일·ATAS 언급이 사라졌다', () {
      expect(src.contains('인가번호·인가일·ATAS번호를 입력하세요'), isFalse);
      expect(src.contains('인가자이면 인가번호를 입력하세요'), isTrue);
    });

    test('저장은 계속 한다 — 컨트롤러·저장 키가 살아 있다', () {
      // 화면에서 감출 뿐, 기존 데이터를 잃지 않아야 한다.
      expect(src.contains("'inductedAt':"), isTrue, reason: '저장 키 유실');
      expect(src.contains("'atasNo':"), isTrue, reason: '저장 키 유실');
      expect(src.contains('inductedCtrl'), isTrue);
      expect(src.contains('atasCtrl'), isTrue);
    });

    test('연동 시 기존 저장값을 지우지 않는다(빈 칸일 때만 채움)', () {
      expect(
        src.contains('if (inductedCtrl != null && inductedCtrl.text.trim().isEmpty)'),
        isTrue,
      );
      expect(
        src.contains('if (atasCtrl != null && atasCtrl.text.trim().isEmpty)'),
        isTrue,
      );
    });
  });

  group('② 번호/이름 조회 → 현재 활동정보 자동 조회', () {
    test('인가번호 입력 즉시 자동 조회가 걸려 있다(onChanged)', () {
      expect(
        RegExp(r'onChanged:\s*\(v\)\s*=>\s*_autoFillFromNumber\(').hasMatch(src),
        isTrue,
        reason: '자동 조회가 연결되지 않았다',
      );
    });

    test('자동 조회가 현재 활동정보 6개 항목을 채운다', () {
      // ② 현재 활동정보 = 소속연맹·소속단위대·직위·활동상태·훈련현황 (+이름·전화)
      for (final field in [
        'leagueCtrl',
        'unitCtrl',
        'positionCtrl',
        'activityCtrl',
        'trainingCtrl',
      ]) {
        expect(
          RegExp('fillIfEmpty\\($field,').hasMatch(src),
          isTrue,
          reason: '$field 가 자동 채움 대상에서 빠졌다',
        );
      }
      expect(RegExp(r'fillIfEmpty\(nameCtrl,').hasMatch(src), isTrue);
      expect(RegExp(r'fillIfEmpty\(phoneCtrl,').hasMatch(src), isTrue);
    });

    test('이미 입력된 값은 덮어쓰지 않는다', () {
      expect(src.contains('if (c.text.trim().isNotEmpty) return;'), isTrue);
    });

    test('재적(현재 활동) 소속을 인가시 소속보다 우선한다', () {
      expect(
        src.contains('m.regLeague.trim().isNotEmpty ? m.regLeague : m.league'),
        isTrue,
      );
      expect(src.contains('m.regUnit.trim().isNotEmpty ? m.regUnit : m.unit'), isTrue);
    });

    test('이름 조회 버튼이 이름 검색을 안내한다', () {
      expect(src.contains('번호·이름으로 검색'), isTrue);
    });

    // ── 조회 규칙을 순수 함수로 고정 ──
    group('조회 규칙 (순수 함수 재현)', () {
      // 파일의 `_findMemberByCodeOrName` 규칙을 그대로 옮긴 것.
      //  · 숫자만 → 범(tsak) 우선, 없으면 은하
      //  · 그 외 → 이름 **정확 일치**, 동명이인이면 null
      String? resolve(
        String raw,
        Map<String, String> tsak, // number -> name
        Map<String, String> eunha, // number -> name
      ) {
        final s = raw.trim();
        if (s.isEmpty) return null;
        final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
        if (RegExp(r'^[0-9]+$').hasMatch(digits)) {
          if (tsak.containsKey(digits)) return 'tsak:$digits:${tsak[digits]}';
          if (eunha.containsKey(digits)) return 'eunha:$digits:${eunha[digits]}';
          return null;
        }
        final key = s.replaceAll(RegExp(r'\s+'), '');
        final all = <String>[
          for (final e in tsak.entries) '${e.value}|tsak:${e.key}:${e.value}',
          for (final e in eunha.entries) '${e.value}|eunha:${e.key}:${e.value}',
        ];
        final hits = [
          for (final a in all)
            if (a.split('|').first.replaceAll(RegExp(r'\s+'), '') == key)
              a.split('|').last,
        ];
        return hits.length == 1 ? hits.first : null;
      }

      final tsak = {'415': '이승준', '75': '이항복', '1346': '양다솜'};
      final eunha = {'75': '은하칠오'};

      test('범 번호는 범에서 먼저 찾는다', () {
        expect(resolve('415', tsak, eunha), 'tsak:415:이승준');
      });

      test('범에 없는 번호는 은하에서 찾는다', () {
        expect(resolve('75', tsak, eunha), 'tsak:75:이항복',
            reason: '범 75 가 있으면 범을 먼저 쓴다');
        expect(resolve('999', tsak, {'999': '은하구구구'}), 'eunha:999:은하구구구');
      });

      test('이름으로도 찾는다', () {
        expect(resolve('이승준', tsak, eunha), 'tsak:415:이승준');
        expect(resolve('  양다솜 ', tsak, eunha), 'tsak:1346:양다솜');
      });

      test('동명이인은 자동 채우지 않는다(null)', () {
        final dup = {'1': '김민수', '2': '김민수'};
        expect(resolve('김민수', dup, {}), isNull,
            reason: '동명이인은 잘못 덮어쓸 위험이 있어 자동 채우지 않는다');
      });

      test('없는 번호·이름은 null', () {
        expect(resolve('77777', tsak, eunha), isNull);
        expect(resolve('없는사람', tsak, eunha), isNull);
      });
    });
  });

  group('③ 자동생성계정 — 전화번호 기반', () {
    test('아이디 = 전화번호(숫자만)', () {
      expect(RegExp(r'return \(ph, last4').hasMatch(src), isTrue);
    });

    test('비밀번호 = 뒤 4자리 + !@@', () {
      expect(src.contains("'\$last4!@@'"), isTrue);
    });

    test('멘토/페런츠를 구분해 안내한다', () {
      expect(src.contains('자동 생성 계정 (멘토 - 전화번호 기반)'), isFalse,
          reason: '문구 형식이 바뀌면 이 검사를 갱신하세요');
      expect(src.contains('전화번호 기반'), isTrue);
      expect(src.contains("'멘토' : '페런츠'"), isTrue);
    });

    test('"따로 아이디를 만들 필요가 없다"는 설명이 있다', () {
      expect(src.contains('계정이 자동 생성됩니다'), isTrue);
      expect(src.contains('따로 아이디를 만들 필요가 없습니다'), isTrue);
    });
  });
}
