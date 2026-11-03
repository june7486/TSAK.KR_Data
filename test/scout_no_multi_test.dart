/// 회원번호 복수 등록 + 주민번호/회원번호 편집 가능 테스트
///
/// ## [요구 2026-11-03]
///   "스카우트고유번호, 주민등록번호는 입력 및 수정가능하도록 할 것
///    스카우트 고유번호는 복수로 등록되어 있는 사람도 있음
///    스카우트 고유번호를 추가로 등록할 수 있도록 할 것"
///
/// 두 축을 고정한다.
///   ① 모델: `scoutNos` 배열 + `allScoutNos`(하위 호환 포함) + 권한별 마킹
///   ② 화면: 편집 가능 여부 / 추가 칸 / 마킹본이 원본을 덮어쓰지 않는지
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tsak_credential_manager/models/member.dart';

Member _m({String scoutNo = '', List<String>? scoutNos}) => Member(
  id: 'm415',
  number: '415',
  name: '이승준',
  scoutNo: scoutNo,
  scoutNoList: scoutNos,
);

void main() {
  group('allScoutNos — 복수 회원번호', () {
    test('scoutNo 만 있으면 [scoutNo] 하나', () {
      expect(_m(scoutNo: '16187').allScoutNos, ['16187']);
    });

    test('scoutNos 배열을 순서대로 유지한다', () {
      expect(
        _m(scoutNo: '16187', scoutNos: ['16187', '22541', '30001']).allScoutNos,
        ['16187', '22541', '30001'],
      );
    });

    test('중복은 제거된다', () {
      expect(
        _m(scoutNo: '16187', scoutNos: ['16187', '16187', '22541']).allScoutNos,
        ['16187', '22541'],
      );
    });

    test('빈 칸·공백은 버린다', () {
      expect(_m(scoutNos: ['', '  ', '22541']).allScoutNos, ['22541']);
    });

    test('대표가 비어 있으면 배열만 남는다', () {
      expect(_m(scoutNo: '', scoutNos: ['22541']).allScoutNos, ['22541']);
    });

    test('전부 비면 빈 목록', () {
      expect(_m().allScoutNos, isEmpty);
    });

    test('대표가 배열에 없어도 뒤에 붙는다 (데이터 보존)', () {
      // 서버가 scoutNos 를 대표 없이 저장한 경우에도 대표를 잃지 않는다.
      expect(_m(scoutNo: '16187', scoutNos: ['22541']).allScoutNos, [
        '22541',
        '16187',
      ]);
    });
  });

  group('복수 회원번호 마킹', () {
    test('권한 없으면 각 값이 뒷 2자리 마킹된다', () {
      final m = _m(scoutNo: '16187', scoutNos: ['16187', '22541']);
      expect(m.allScoutNosDisplay(canSeeAll: false), ['161**', '225**']);
    });

    test('관리자·마스터면 원본 그대로', () {
      final m = _m(scoutNo: '16187', scoutNos: ['16187', '22541']);
      expect(m.allScoutNosDisplay(canSeeAll: true), ['16187', '22541']);
    });

    test('한 칸 표기 — 가운데 점으로 잇는다', () {
      final m = _m(scoutNo: '16187', scoutNos: ['16187', '22541']);
      expect(m.scoutNosDisplay(canSeeAll: true), '16187 · 22541');
      expect(m.scoutNosDisplay(canSeeAll: false), '161** · 225**');
    });

    test('없으면 빈 문자열', () {
      expect(_m().scoutNosDisplay(canSeeAll: true), '');
    });

    test('대표만 있어도 한 칸 표기가 동작한다', () {
      expect(_m(scoutNo: '16187').scoutNosDisplay(canSeeAll: true), '16187');
    });
  });

  group('toMap / fromMap — 저장·복원 왕복', () {
    test('scoutNos 가 toMap 에 배열로 들어간다', () {
      final m = _m(scoutNo: '16187', scoutNos: ['16187', '22541']);
      final map = m.toMap();
      expect(map['scoutNos'], ['16187', '22541']);
      expect(map['scoutNo'], '16187');
    });

    test('fromMap 이 scoutNos 를 복원한다', () {
      final m = Member.fromMap({
        'id': 'm415',
        'number': '415',
        'name': '이승준',
        'scoutNo': '16187',
        'scoutNos': ['16187', '22541'],
      });
      expect(m.allScoutNos, ['16187', '22541']);
    });

    test('구 데이터(scoutNos 없음)도 대표값으로 동작한다', () {
      final m = Member.fromMap({
        'id': 'm415',
        'number': '415',
        'name': '이승준',
        'scoutNo': '16187',
      });
      expect(m.allScoutNos, ['16187']);
      expect(m.scoutNosDisplay(canSeeAll: true), '16187');
    });

    test('copyWith 로 복수 회원번호를 바꿀 수 있다', () {
      final m = _m(scoutNo: '16187');
      final n = m.copyWith(scoutNoList: ['16187', '22541']);
      expect(n.allScoutNos, ['16187', '22541']);
      // 원본은 그대로 (불변)
      expect(m.allScoutNos, ['16187']);
    });
  });

  group('searchText — 복수 회원번호로도 검색된다', () {
    test('두 번째 회원번호로 검색 가능', () {
      final m = _m(scoutNo: '16187', scoutNos: ['16187', '22541']);
      expect(m.searchText.contains('22541'), isTrue);
    });

    test('대표 회원번호도 검색된다', () {
      final m = _m(scoutNo: '16187', scoutNos: ['16187', '22541']);
      expect(m.searchText.contains('16187'), isTrue);
    });
  });

  group('소스 계약 — 편집 화면', () {
    final edit =
        File('lib/screens/member_edit_screen.dart').readAsStringSync();

    test('회원번호 추가 등록 버튼이 있다', () {
      expect(edit.contains('회원번호 추가 등록'), isTrue);
      expect(edit.contains('_extraScoutNos'), isTrue);
    });

    test('추가 칸을 삭제할 수 있다', () {
      expect(edit.contains('이 회원번호 칸 삭제'), isTrue);
    });

    test('저장 시 대표 + 추가를 합친다', () {
      expect(edit.contains('_scoutNosToSave()'), isTrue);
      expect(edit.contains('scoutNoList: _scoutNosToSave()'), isTrue);
    });

    test('주민등록번호가 더 이상 비활성(enabled: false) 이 아니다', () {
      // 종전 코드의 흔적이 남아 있으면 회귀다.
      //  (주석에 역사 설명으로 남는 것은 허용 — 실제 위젯 인자만 본다)
      expect(edit.contains('enabled: false,'), isFalse);
      expect(edit.contains('readOnly: true,'), isFalse);
      expect(edit.contains('_residentNoView'), isTrue);
    });

    test('마킹본이 원본을 덮어쓰지 않도록 보호한다', () {
      expect(edit.contains('_residentNoToSave()'), isTrue);
      expect(edit.contains("if (!typed.contains('*')) return typed;"), isTrue);
    });

    test('추가 칸 컨트롤러를 dispose 한다', () {
      expect(edit.contains('for (final c in _extraScoutNos)'), isTrue);
      expect(edit.contains('_residentNoView.dispose()'), isTrue);
    });
  });
}
