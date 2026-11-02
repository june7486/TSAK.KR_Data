// 은하 인가정보 무결성 테스트 (build #579)
//
// 요구(원문 2026-11-02):
//   "은하20호 정보가 누락됨 은하19호의 인가시 정보와 동일하게 업데이트 해줘"
//
// ## 실제 원인 (조사 결과)
//   NAS 의 `db/eunha_members.json` 안에서 **G20 한 건만** id·number·name·
//   corps·memo 5개 키로 얇아져 있었다. 인가 당시 정보(소속연맹·등록단위대·
//   생년월일·인가일)가 통째로 비어 상세 화면에 아무것도 뜨지 않았다.
//   반면 앱 번들 시드(assets/data/eunha_members_seed.json)에는 값이 살아
//   있었다 → 시드가 '정답'이고, 서버 레코드가 얇아진 것이 문제였다.
//
// ## 조치
//   ① 데이터 복구(G20 → 시드 값) + 백업 자동 생성.
//   ② 프록시 부팅 시 `인가정보 자동 보충` 가드 추가
//      (비어 있는 필드만 시드로 채운다 — 사용자가 고친 값은 건드리지 않음).
//
// 이 테스트는 ②의 사고가 다시 나지 않도록 **시드 자체**를 지킨다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';

void main() {
  final seedFile = File('assets/data/eunha_members_seed.json');

  List<Map<String, dynamic>> loadSeed() {
    final raw = json.decode(seedFile.readAsStringSync()) as List;
    return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  group('은하 시드 — 인가 당시 정보가 온전한가', () {
    test('시드 파일이 존재하고 165명이다', () {
      expect(seedFile.existsSync(), isTrue);
      expect(loadSeed().length, 165);
    });

    test('모든 은하 대원이 소속연맹·등록단위대·생년월일·인가일을 갖는다', () {
      final missing = <String>[];
      for (final m in loadSeed()) {
        final no = '${m['number'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
        for (final k in ['league', 'unit', 'birthday', 'date']) {
          if ('${m[k] ?? ''}'.trim().isEmpty) missing.add('$no:$k');
        }
      }
      expect(missing, isEmpty, reason: '누락: ${missing.take(10).toList()}');
    });

    test('모든 은하 대원에 id·number·name·corps 가 있다', () {
      for (final m in loadSeed()) {
        for (final k in ['id', 'number', 'name', 'corps']) {
          expect('${m[k] ?? ''}'.trim(), isNotEmpty, reason: '$k @ $m');
        }
        expect(m['corps'], 'eunha');
      }
    });

    test('번호가 중복되지 않고 1~165 를 모두 덮는다', () {
      final nums = <int>[];
      for (final m in loadSeed()) {
        nums.add(int.parse('${m['number']}'.replaceAll(RegExp(r'[^0-9]'), '')));
      }
      expect(nums.toSet().length, nums.length, reason: '중복 번호 있음');
      expect(nums.toSet(), Set<int>.from(List.generate(165, (i) => i + 1)));
    });

    test('인가일 형식이 YYYY.MM.DD 이다', () {
      final bad = <String>[];
      for (final m in loadSeed()) {
        final d = '${m['date'] ?? ''}';
        if (!RegExp(r'^\d{4}\.\d{2}\.\d{2}$').hasMatch(d)) {
          bad.add('${m['number']}:$d');
        }
      }
      expect(bad, isEmpty, reason: bad.take(10).toList().toString());
    });
  });

  group('G19 · G20 — 인가정보 4항목이 동일한 형태인가', () {
    Map<String, dynamic> byNo(String no) => loadSeed().firstWhere(
      (m) => '${m['number']}'.replaceAll(RegExp(r'[^0-9]'), '') == no,
    );

    test('G19 와 G20 이 같은 소속연맹·등록단위대·인가일을 갖는다', () {
      final a = byNo('19');
      final b = byNo('20');
      expect(b['league'], a['league']);
      expect(b['unit'], a['unit']);
      expect(b['date'], a['date']);
    });

    test('G20 은 이정일 · 생년월일 1973.08.17', () {
      final b = byNo('20');
      expect(b['name'], '이정일');
      expect(b['birthday'], '1973.08.17');
    });

    test('G20 은 은하 소속이며 인가자(일반회원 아님)다', () {
      final b = byNo('20');
      expect(b['corps'], 'eunha');
      expect(b['isRegular'], isFalse);
    });

    test('시드 G20 을 Member 로 읽으면 4항목이 채워진다', () {
      final m = Member.fromMap(byNo('20'));
      expect(m.name, '이정일');
      expect(m.corps, 'eunha');
      expect(m.league, isNotEmpty);
      expect(m.unit, isNotEmpty);
      expect(m.birthday, isNotEmpty);
      expect(m.date, isNotEmpty);
      // 은하 번호는 G 접두어가 붙은 명부 표기를 유지한다.
      expect(m.rosterNumber, 'G20');
      // 표기 검색(은하20호)도 당연히 성립.
      expect(m.searchText.contains('은하20'), isTrue);
    });
  });

  group('소스 계약 — 프록시에 인가정보 자동 보충 가드가 있다', () {
    final proxy = File('/home/user/nas_proxy/proxy_server.py');

    test('프록시 파일을 읽을 수 있다', () {
      expect(proxy.existsSync(), isTrue);
    });

    test('부팅 시 은하 인가정보를 시드로 보충하는 코드가 있다', () {
      if (!proxy.existsSync()) return;
      final src = proxy.readAsStringSync();
      expect(src.contains('은하 인가정보 유실 자동 복구'), isTrue);
      expect(src.contains('eunha 인가정보 자동 보충'), isTrue);
      // 비어 있는 필드만 채우는 조건(사용자가 고친 값을 덮지 않는다).
      expect(
        src.contains('if (not str(m.get(k) or "").strip()'),
        isTrue,
        reason: '빈 값일 때만 채우는 가드가 있어야 한다',
      );
      expect(src.contains('fill_keys = ("league", "unit", "birthday", "date")'),
          isTrue);
    });
  });
}
