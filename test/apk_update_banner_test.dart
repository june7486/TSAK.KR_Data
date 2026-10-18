import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/build_info.dart';
import 'package:tsak_credential_manager/widgets/apk_update_banner.dart';

void main() {
  testWidgets('배너: update null 이면 미표시', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApkUpdateBanner(update: null, onUpdate: () {}),
      ),
    ));
    expect(find.textContaining('새 버전'), findsNothing);
  });

  testWidgets('배너: 새 버전 표시 + 업데이트 버튼', (tester) async {
    var tapped = false;
    const u = ApkUpdate(build: 999, version: '1.0.0+999', url: 'https://x/a.apk');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApkUpdateBanner(update: u, onUpdate: () => tapped = true),
      ),
    ));
    expect(find.textContaining('새 버전이 있습니다'), findsOneWidget);
    expect(find.text('새 버전이 있습니다 · 1.0.0+999'), findsOneWidget);
    expect(find.textContaining('1.0.0+448'), findsOneWidget); // 현재 빌드 표기
    expect(find.text('지금 업데이트'), findsOneWidget);
    await tester.tap(find.text('지금 업데이트'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('배너: busy 상태면 진행률 표시', (tester) async {
    const u = ApkUpdate(build: 999, version: '1.0.0+999', url: 'https://x/a.apk');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ApkUpdateBanner(update: u, onUpdate: () {}, busy: true, progress: 0.42),
      ),
    ));
    expect(find.textContaining('42%'), findsOneWidget);
    expect(find.text('지금 업데이트'), findsNothing);
  });

  test('ApkUpdate.isNewer: 현재 빌드보다 크면 true', () {
    const newer = ApkUpdate(build: 99999, version: 'x', url: 'https://x/a.apk');
    const older = ApkUpdate(build: 0, version: 'x', url: 'https://x/a.apk');
    expect(newer.isNewer, isTrue);
    expect(older.isNewer, isFalse);
  });
}
