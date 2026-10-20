import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';

/// ATAS 검색 요구: 검색창에 'atas'/'아타스' 를 치면 ATAS 보유자가 나와야 한다.
void main() {
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
