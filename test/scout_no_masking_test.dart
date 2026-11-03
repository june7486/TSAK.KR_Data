/// 스카우트회원번호 노출 규칙 테스트
///
/// ## [요구 2026-11-03]
///   "회원명부에 스카우트회원번호 적는 칸을 넣고, 관리자 및 마스터는
///    모든 번호를 확인할 수 있도록 하고, 회원에게는 뒷번호 2자리에
///    * 표 처리해서 노출해줘"
///   "개인정보 활동 동의란에 회원번호 사용에 관한 언급이 없다면 추가해줘"
///   "필요시(행사참가신청과 같은) 회원번호를 전송할 수 있음"
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/export_service.dart';
import 'package:tsak_credential_manager/widgets/privacy_consent.dart';

Member _m(String scoutNo) => Member(id: 'x', number: '415', name: '이승준')
  ..scoutNo = scoutNo;

void main() {
  group('scoutNoMasked — 뒷 2자리 마킹', () {
    test('6자리 123456 → 1234**', () {
      expect(_m('123456').scoutNoMasked, '1234**');
    });

    test('5자리 12345 → 123**', () {
      expect(_m('12345').scoutNoMasked, '123**');
    });

    test('4자리 1234 → 12**', () {
      expect(_m('1234').scoutNoMasked, '12**');
    });

    test('하이픈이 있어도 뒤 2개 숫자만 가린다 (123-456 → 123-4**)', () {
      expect(_m('123-456').scoutNoMasked, '123-4**');
    });

    test('이미 마킹된 값은 그대로 둔다 (이중 마킹 방지)', () {
      expect(_m('1234**').scoutNoMasked, '1234**');
    });

    test('빈 값은 빈 문자열', () {
      expect(_m('').scoutNoMasked, '');
      expect(_m('   ').scoutNoMasked, '');
    });

    test('숫자가 2개 미만이면 전부 가린다 (안전 우선)', () {
      expect(_m('12').scoutNoMasked, '**');
      expect(_m('1').scoutNoMasked, '*');
      expect(_m('A1').scoutNoMasked, '**');
    });
  });

  group('scoutNoDisplay — 권한 분기', () {
    test('관리자·마스터(canSeeAll: true) → 원본 그대로', () {
      expect(_m('123456').scoutNoDisplay(canSeeAll: true), '123456');
    });

    test('회원(canSeeAll: false) → 뒷 2자리 마킹', () {
      expect(_m('123456').scoutNoDisplay(canSeeAll: false), '1234**');
    });

    test('빈 값은 권한과 무관하게 빈 문자열', () {
      expect(_m('').scoutNoDisplay(canSeeAll: true), '');
      expect(_m('').scoutNoDisplay(canSeeAll: false), '');
    });

    test('앞뒤 공백은 제거한다', () {
      expect(_m(' 123456 ').scoutNoDisplay(canSeeAll: true), '123456');
    });
  });

  group('exportValueOf — 출력물도 같은 규칙을 따른다', () {
    test('revealScoutNo=false(기본) → 마킹본', () {
      final m = _m('30601');
      expect(exportValueOf(m, 'scoutNo'), '306**');
    });

    test('revealScoutNo=true → 원본', () {
      final m = _m('30601');
      expect(exportValueOf(m, 'scoutNo', revealScoutNo: true), '30601');
    });

    test('ExportService.revealScoutNo 기본값은 false (안전 우선)', () {
      expect(ExportService.revealScoutNo, isFalse);
    });

    test('rowFor 는 정적 플래그를 따른다', () {
      final m = _m('123456');
      ExportService.revealScoutNo = false;
      expect(ExportService.rowFor(m, ['scoutNo']).first, '1234**');
      ExportService.revealScoutNo = true;
      expect(ExportService.rowFor(m, ['scoutNo']).first, '123456');
      ExportService.revealScoutNo = false; // 원복
    });
  });

  group('개인정보 동의 문구 — 회원번호 조항', () {
    final t = PrivacyConsentField.consentText;

    test('회원번호 항목이 수집 항목에 있다', () {
      expect(t.contains('스카우트회원번호'), isTrue);
    });

    test('9항 — 회원번호의 처리 및 이용 조항이 있다', () {
      expect(t.contains('9. 스카우트회원번호'), isTrue);
    });

    test('열람 권한을 관리자·마스터로 한정한다고 적혀 있다', () {
      expect(t.contains('관리자 및 마스터만'), isTrue);
    });

    test('뒷 2자리 마킹 사실을 고지한다', () {
      expect(t.contains('뒷번호 2자리'), isTrue);
      expect(t.contains('1234**'), isTrue);
    });

    test('필요 시 전송(행사 참가 신청) 조항이 있다', () {
      expect(t.contains('참가 신청'), isTrue);
      expect(t.contains('전송'), isTrue);
    });

    test('거부 권리를 안내한다', () {
      expect(t.contains('동의를 거부할 권리'), isTrue);
    });

    test('기존 주민등록번호 조항은 그대로 남아 있다', () {
      expect(t.contains('주민등록번호(고유식별정보)'), isTrue);
      expect(t.contains('990328-1******'), isTrue);
    });
  });

  group('소스 계약 — 명부·상세 화면에 회원번호 칸이 있는가', () {
    final rosterAdmin =
        File('lib/screens/roster_admin_screen.dart').readAsStringSync();
    final roster = File('lib/screens/roster_screen.dart').readAsStringSync();
    final detail =
        File('lib/screens/member_detail_screen.dart').readAsStringSync();

    test('범스카우트 인가자 명부에 회원번호 헤더가 있다', () {
      expect(rosterAdmin.contains("'회원번호'"), isTrue);
    });

    test('아타스·은하 명부에도 회원번호 헤더가 있다 (3곳 이상)', () {
      final n = RegExp(r"'회원번호'").allMatches(rosterAdmin).length;
      expect(n >= 3, isTrue);
    });

    test('명부가 scoutNosDisplay 로 권한 분기를 한다', () {
      // [turn 37] 복수 회원번호 지원으로 단수 scoutNoDisplay → 복수 scoutNosDisplay 로 바뀌었다.
      expect(rosterAdmin.contains('scoutNosDisplay'), isTrue);
      expect(rosterAdmin.contains('state.isApp'), isTrue);
    });

    test('행사 참가자 명부에 회원번호 토글·컬럼이 있다', () {
      expect(roster.contains('_showScoutNo'), isTrue);
      expect(roster.contains("Text('회원번호')"), isTrue);
      expect(roster.contains('_scoutNoOf'), isTrue);
    });

    test('상세 화면도 권한별 마킹을 쓴다', () {
      // [turn 37] 복수 회원번호 지원 → scoutNosDisplay.
      expect(detail.contains('scoutNosDisplay'), isTrue);
    });

    test('로그인/잠금 시 원본 노출 플래그를 갱신한다', () {
      final appState = File('lib/services/app_state.dart').readAsStringSync();
      expect(appState.contains('ExportService.revealScoutNo = isApp'), isTrue);
      expect(appState.contains('ExportService.revealScoutNo = false'), isTrue);
    });
  });
}
