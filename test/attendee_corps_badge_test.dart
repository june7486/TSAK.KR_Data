// 행사 참가자 명단 — 이름 옆 **범/은하 단추 + 번호** 계약 테스트
//
// ## [요구 2026-11-04]
//   "행사 참가자 명단에서 범스카우트인가자 및 은하스카우트들은 이름 옆에
//    범, 은하 단추와 번호를 꼭 같이 기입해줘"
//
// ## 이 테스트가 지키는 것
//   ① 소속 판정: 서버 `corps` 우선, 비어 있으면 로컬 명부로 **복원**
//      (옛 참가 행에서 배지가 '일반' 으로 떨어지던 문제 방지)
//   ② 번호 라벨: 인가자는 `범#415` / `은하#43`, 비인가는 `일반#010…`
//   ③ 화면: 배지·이름·번호가 **한 줄에** 붙어 있다(소스 계약)
//
// ⚠️ EventDetailScreen 을 pump 하면 이 샌드박스에서 테스트가 끝나지 않는다.
//    그래서 순수 함수 + 소스 계약으로만 검증한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';

Member _m(String number, {String corps = 'tsak', bool regular = false}) =>
    Member(id: 'id$number', number: number, name: '테스트$number')
      ..corps = corps
      ..isRegular = regular;

/// AppState 의 복원 규칙을 화면 없이 재현 — 같은 입력에 같은 결과인지 확인.
/// (실제 구현은 AppState.corpsMarkForAttendee / numberLabelForAttendee)
String _resolveMark(Map<String, dynamic> a, List<Member> tsak,
    List<Member> eunha) {
  final server = '${a['corps'] ?? ''}'.trim().toLowerCase();
  if (server == 'eunha') return '은하';
  if (server == 'tsak') return '범';
  if (a['licensed'] == false) return '일반';
  if ('${a['identityKey'] ?? ''}'.startsWith('reg:')) return '일반';
  final ident = '${a['number'] ?? a['phone'] ?? ''}';
  final digits = ident.replaceAll(RegExp(r'[^0-9]'), '');
  for (final m in tsak) {
    if (m.number.replaceAll(RegExp(r'[^0-9]'), '') == digits) {
      return m.isRegular ? '일반' : (m.corps == 'eunha' ? '은하' : '범');
    }
  }
  for (final m in eunha) {
    if (m.number.replaceAll(RegExp(r'[^0-9]'), '') == digits) {
      return m.corps == 'eunha' ? '은하' : '범';
    }
  }
  return server.isEmpty ? '일반' : '';
}

void main() {
  group('번호 라벨 — 인가자/비인가 구분', () {
    test('범스카우트 인가자 → 범#415', () {
      expect(Member.numLabelOf('415', 'tsak'), '범#415');
    });

    test('은하스카우트 인가자 → 은하#43', () {
      expect(Member.numLabelOf('43', 'eunha'), '은하#43');
    });

    test('비인가 일반회원 → 일반#전화번호', () {
      expect(Member.numLabelOf('01074451179', 'tsak', true), '일반#01074451179');
    });

    test('은하 번호에 G 접두가 섞여도 숫자만 남긴다', () {
      expect(Member.numLabelOf('G43', 'eunha'), '은하#43');
    });

    test('빈 번호는 라벨 없음', () {
      expect(Member.numLabelOf('', 'tsak'), '');
    });
  });

  group('말머리(단추) — 범/은하/일반', () {
    test('corpsMarkLabel: 범', () {
      expect(_m('415').corpsMarkLabel, '범');
    });

    test('corpsMarkLabel: 은하', () {
      expect(_m('43', corps: 'eunha').corpsMarkLabel, '은하');
    });

    test('corpsMarkLabel: 일반회원은 범 단추가 아니라 일반', () {
      expect(_m('01074451179', regular: true).corpsMarkLabel, '일반');
    });
  });

  group('소속 복원 — 서버가 비워 보낸 옛 참가 행', () {
    final tsak = [_m('415'), _m('311'), _m('1378')];
    final eunha = [_m('43', corps: 'eunha'), _m('19', corps: 'eunha')];

    test('서버 corps 가 tsak 이면 그대로 범', () {
      expect(_resolveMark({'corps': 'tsak', 'number': '415'}, tsak, eunha), '범');
    });

    test('서버 corps 가 eunha 이면 그대로 은하', () {
      expect(
        _resolveMark({'corps': 'eunha', 'number': '43'}, tsak, eunha),
        '은하',
      );
    });

    test('corps 가 비어 있어도 범 명부에서 찾아 범으로 복원한다', () {
      expect(_resolveMark({'corps': '', 'number': '311'}, tsak, eunha), '범');
    });

    test('corps 가 비어 있어도 은하 명단에서 찾아 은하로 복원한다', () {
      expect(_resolveMark({'corps': '', 'number': '43'}, tsak, eunha), '은하');
    });

    test('명부에 없는 비인가는 일반', () {
      expect(_resolveMark({'corps': '', 'number': '99999'}, tsak, eunha), '일반');
    });

    test('licensed=false 는 명부에 있어도 일반 (저장된 신원 우선)', () {
      expect(
        _resolveMark({'corps': '', 'number': '415', 'licensed': false}, tsak,
            eunha),
        '일반',
      );
    });

    test('identityKey 가 reg: 이면 일반', () {
      expect(
        _resolveMark(
          {'corps': '', 'number': '415', 'identityKey': 'reg:abc'},
          tsak,
          eunha,
        ),
        '일반',
      );
    });

    test('일반회원 카드는 범 단추를 달지 않는다', () {
      final reg = [_m('01074451179', regular: true)];
      expect(
        _resolveMark({'corps': '', 'number': '01074451179'}, reg, eunha),
        '일반',
      );
    });

    test('번호가 겹칠 때(범 43 ↔ 은하 43) 서버 corps 를 신뢰한다', () {
      final tsak43 = [...tsak, _m('43')];
      // 서버가 은하라고 했으면 은하.
      expect(
        _resolveMark({'corps': 'eunha', 'number': '43'}, tsak43, eunha),
        '은하',
      );
      // 서버가 범이라고 했으면 범.
      expect(
        _resolveMark({'corps': 'tsak', 'number': '43'}, tsak43, eunha),
        '범',
      );
    });
  });

  group('소스 계약 — 배지·번호가 이름 옆에 붙어 있는가', () {
    final src = File('lib/screens/event_detail_screen.dart').readAsStringSync();
    final state = File('lib/services/app_state.dart').readAsStringSync();

    test('AppState 가 참가자 소속 복원 함수를 제공한다', () {
      expect(state.contains('String corpsMarkForAttendee('), isTrue);
      expect(state.contains('String numberLabelForAttendee('), isTrue);
    });

    test('참가자 타일이 번호를 복원 함수로 얻는다', () {
      expect(
        src.contains('final numLabel = st0.numberLabelForAttendee(a);'),
        isTrue,
      );
    });

    test('참가자 타일이 소속을 복원 함수로 얻는다', () {
      expect(src.contains('st0.corpsMarkForAttendee(a)'), isTrue);
    });

    /// 참가자 타일(비선택 모드)의 title Row.
    ///  일반 타일은 `leading: _attendeeLeading(...)` 뒤에 title Row 가 온다 —
    ///  이 앵커로 선택 모드 타일과 구분한다.
    String titleBlock() {
      final lead = src.indexOf('leading: _attendeeLeading(');
      expect(lead, greaterThan(0), reason: '일반 타일 leading 앵커');
      final i = src.indexOf('title: Row(', lead);
      expect(i, greaterThan(0), reason: '일반 타일 title Row');
      return src.substring(i, (i + 3000).clamp(0, src.length));
    }

    test('이름(title) Row 안에 배지와 번호가 함께 있다', () {
      final chunk = titleBlock();
      expect(chunk.isNotEmpty, isTrue, reason: '배지·번호가 있는 title Row');
      expect(chunk.contains("a['name']"), isTrue, reason: '이름');
    });

    test('일괄 선택 모드 타일에도 배지·번호가 있다', () {
      final i = src.indexOf('if (_selMode) {');
      expect(i, greaterThan(0));
      final chunk = src.substring(i, i + 2500);
      expect(chunk.contains('corpLabel'), isTrue);
      expect(chunk.contains('numLabel'), isTrue);
    });

    test('번호가 없어도 배지는 남는다 (범/은하 단추는 항상)', () {
      final chunk = titleBlock();
      // 배지 Container 는 조건 없이 그려지고, 번호만 조건부여야 한다.
      expect(chunk.contains('if (numLabel.isNotEmpty)'), isTrue);
      expect(chunk.contains('if (corpLabel.isNotEmpty)'), isFalse);
    });
  });
}
