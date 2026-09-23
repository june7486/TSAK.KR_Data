import 'package:flutter_test/flutter_test.dart';

import 'package:tsak_credential_manager/models/member.dart';

void main() {
  test('Member searchText includes key fields', () {
    final m = Member(
      id: 'm1',
      number: '2186',
      name: '현지환',
      league: '제주',
      unit: '제405단 샘물지역대',
      phone: '010-6888-6397',
    );
    expect(m.searchText.contains('현지환'), isTrue);
    expect(m.searchText.contains('2186'), isTrue);
    expect(m.searchText.contains('010-6888-6397'), isTrue);
  });

  test('Member map round-trip', () {
    final m = Member(
      id: 'm2',
      number: '100',
      name: '홍길동',
      lifetimeMember: true,
      feeYears: {'2025': true, '2026': true},
    );
    final restored = Member.fromMap(m.toMap());
    expect(restored.name, '홍길동');
    expect(restored.lifetimeMember, isTrue);
    expect(restored.paidYears, ['2025', '2026']);
  });
}
