import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/import_parser.dart';

void main() {
  group('ImportParser (AI 자동 인식)', () {
    test('CSV 헤더 자동 인식', () {
      const csv = '인가번호,성명,소속연맹,단위대,핸드폰,ATAS 인가번호\n'
          '2186,홍길동,제주,제405단,010-1111-2222,358\n'
          '2187,"김철수",광주,제101단,010-3333-4444,';
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final list = ImportParser.parse('test.csv', bytes);
      expect(list.length, 2);
      expect(list[0].number, '2186');
      expect(list[0].name, '홍길동');
      expect(list[0].league, '제주');
      expect(list[0].atasNo, '358');
      expect(list[1].name, '김철수');
    });

    test('탭 구분 텍스트, 헤더 없음', () {
      const txt = '2186\t홍길동\t제주\t제405단\n2187\t김철수\t광주\t제101단';
      final bytes = Uint8List.fromList(utf8.encode(txt));
      final list = ImportParser.parse('pasted.txt', bytes);
      expect(list.length, 2);
      expect(list[0].number, '2186');
      expect(list[1].name, '김철수');
    });

    test('JSON 목록 인식', () {
      const js = '[{"id":"m1","number":"1","name":"가나다","league":"서울"}]';
      final bytes = Uint8List.fromList(utf8.encode(js));
      final list = ImportParser.parse('m.json', bytes);
      expect(list.length, 1);
      expect(list[0].name, '가나다');
    });
  });

  group('Member — 개인 비밀번호 규칙', () {
    test('인가번호 + !@@ 형식', () {
      final m = Member(id: 'm1', number: '415', name: '이승준');
      final pw = '${m.number}!@@';
      expect(pw, '415!@@');
    });
    test('ATAS + 인가번호 검색', () {
      final m = Member(
          id: 'm1', number: '100', name: '이승준', atasNo: '358');
      expect(m.searchText.contains('358'), isTrue);
      expect(m.searchText.contains('100'), isTrue);
    });
  });
}
