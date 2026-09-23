import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/widgets/member_card.dart';
import 'package:tsak_credential_manager/widgets/member_avatar.dart';

void main() {
  testWidgets('아바타에 인가번호가 표시된다 (사진 없을 때)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberAvatar(name: '조원호', number: '30', size: 50),
        ),
      ),
    );
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('카드에 ATAS 번호 배지가 표시된다', (tester) async {
    final m = Member(
      id: 'm30',
      number: '30',
      name: '조원호',
      league: '서울남부',
      unit: '제1단',
      date: '1982.05.01.',
      atasNo: '358',
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MemberCard(member: m))),
    );
    expect(find.text('ATAS 358'), findsOneWidget);
    expect(find.text('#30'), findsOneWidget);
    // 아바타 안에 인가번호
    expect(find.text('30'), findsOneWidget);
  });
}
