import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';

/// ATAS 검색 요구: 검색창에 'atas'/'아타스' 를 치면 ATAS 보유자가 나와야 한다.
// ── ATAS 인가 당시 정보 필드 ──────────────────────────────────────────────
//
// (요구: "아타스인가정보 중 인가번호만 있다면 나머지는 추후 입력할 수 있도록
//        항목만 만들고 비워 놔")
//  · ATAS 소속연맹·단위대·인가일은 **범인가(league/unit/date)와 별개** 필드다.
//  · 지금은 비어 있고, 값을 넣으면 저장·복원되어야 한다.
void atasFieldsTests() {
  test('ATAS 전용 필드는 기본적으로 비어 있다', () {
    final m = Member(id: 'a', number: '415', name: '이승준', atasNo: '13702');
    expect(m.atasLeague, '');
    expect(m.atasUnit, '');
    expect(m.atasDate, '');
    // 범인가 값과 섞이지 않는다.
    m.league = '인천';
    m.unit = '제1234단';
    expect(m.atasLeague, '');
  });

  test('ATAS 전용 필드 저장·복원(map 왕복)', () {
    final m = Member(
      id: 'a',
      number: '415',
      name: '이승준',
      atasNo: '13702',
      atasLeague: '광주',
      atasUnit: '제188대 한울지역대',
      atasDate: '2001-09-03',
    );
    final back = Member.fromMap(m.toMap());
    expect(back.atasNo, '13702');
    expect(back.atasLeague, '광주');
    expect(back.atasUnit, '제188대 한울지역대');
    expect(back.atasDate, '2001-09-03');
  });

  test('copyWith 로 ATAS 항목만 수정된다', () {
    final m = Member(id: 'a', number: '415', name: '이승준', atasNo: '13702');
    final m2 = m.copyWith(atasLeague: '광주', atasDate: '2001-09-03');
    expect(m2.atasLeague, '광주');
    expect(m2.atasDate, '2001-09-03');
    expect(m2.atasNo, '13702');
    expect(m2.atasUnit, '');
  });
}

void main() {
  atasFieldsTests();

  Member mk(String number, String name, {String atasNo = ''}) => Member(
        id: 'id$number',
        number: number,
        name: name,
        atasNo: atasNo,
      );

  group('searchText — ATAS 키워드', () {
    test('ATAS 보유자는 atas/아타스 로 검색된다', () {
      final m = mk('415', '이승준', atasNo: '358');
      expect(m.hasAtas, isTrue);
      expect(m.searchText.contains('atas'), isTrue);
      expect(m.searchText.contains('아타스'), isTrue);
      expect(m.searchText.contains('358'), isTrue);
    });

    test('ATAS 미보유자는 atas 로 검색되지 않는다', () {
      final m = mk('416', '김테스트');
      expect(m.hasAtas, isFalse);
      expect(m.searchText.contains('atas'), isFalse);
      expect(m.searchText.contains('아타스'), isFalse);
    });

    test('공백만 있는 ATAS 번호는 미보유로 취급', () {
      expect(mk('417', '공백', atasNo: '   ').hasAtas, isFalse);
    });
  });

  group('ATAS 번호 검색', () {
    test('ATAS 번호 원문이 searchText 에 포함된다', () {
      final m = mk('415', '이승준', atasNo: '12567');
      expect(m.searchText.contains('12567'), isTrue);
    });
  });
}
