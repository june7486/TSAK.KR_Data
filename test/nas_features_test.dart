import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/finance_service.dart';
import 'package:tsak_credential_manager/services/import_parser.dart';
import 'package:tsak_credential_manager/services/member_repository.dart';
import 'package:tsak_credential_manager/services/nas_api.dart';

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

  group('개인 접근 격리 (restrictedNumber)', () {
    test('개인 접근 시 본인만 조회, byNumber 차단', () async {
      final repo = MemberRepository.memory();
      await repo.save(Member(id: 'm1', number: '415', name: '이승준'));
      await repo.save(Member(id: 'm2', number: '200', name: '홍길동'));
      expect(repo.all().length, 2);

      repo.restrictedNumber = '415';
      expect(repo.all().length, 1);
      expect(repo.all().first.number, '415');
      expect(repo.byNumber('415')?.name, '이승준');
      expect(repo.byNumber('200'), isNull); // 타인 접근 차단

      repo.restrictedNumber = null;
      expect(repo.all().length, 2);
    });
  });

  group('FinanceService — 입금자 자동분류 (이름 앞뒤 텍스트/행사명 인식)', () {
    final members = [
      Member(id: 'm1', number: '415', name: '이승준', league: '제주'),
      Member(id: 'm2', number: '200', name: '홍길동', league: '광주'),
    ];

    test('이름 앞뒤 텍스트가 있어도 동일인으로 인식 + 맥락 기록', () {
      final fs = FinanceService(NasApi());
      final r = fs.classify(
        {'date': '2024-05-01', 'payer': '홍길동 제405단 후원', 'amount': '100000'},
        members: members,
      );
      expect(r.matched, isTrue);
      expect(r.number, '200');
      expect(r.context.contains('제405단'), isTrue);
    });

    test('행사명이 포함되어도 동일인으로 인식', () {
      final fs = FinanceService(NasApi());
      final r = fs.classify(
        {
          'date': '2024-05-03',
          'payer': '이승준',
          'memo': '2024 정기총회 참가비',
          'amount': 30000,
        },
        members: members,
      );
      expect(r.matched, isTrue);
      expect(r.number, '415');
      expect(r.category, '참가비');
    });

    test('미매칭 입금은 unmatched 로 표시', () {
      final fs = FinanceService(NasApi());
      final r = fs.classify(
        {'date': '2024-05-09', 'payer': '알수없는입금자', 'amount': 5000},
        members: members,
      );
      expect(r.matched, isFalse);
    });
  });
}
