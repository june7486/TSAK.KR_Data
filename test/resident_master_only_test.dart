// 주민등록번호 노출 권한 — **마스터 전용** 계약 테스트
//
// ## [요구 2026-11-04]
//   "주민등록번호는 관리자에게도 마킹처리해줘, 마스터에게만 노출됨
//    예) 870110-2324718  ->  870120-2******"
//
//  회원번호(스카우트고유번호)는 **관리자·마스터** 공개지만,
//  주민등록번호는 한 단계 더 민감하므로 **마스터만** 원본을 본다.
//
//  이 파일은 (1) 마킹 형식이 요구 예시와 같은지, (2) 화면·출력의 권한 판정이
//  `isMaster` 인지(관리자를 포함하는 `isApp` 이 아닌지)를 소스 계약으로 확인한다.
//
//  ⚠️ HomeScreen/MemberDetailScreen 을 pump 하면 이 샌드박스에서 테스트가
//     끝나지 않는다. 그래서 **소스 계약 + 순수 함수**로만 검증한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/export_service.dart';

Member _m(String rn) => Member(id: 'x', number: '1', name: '테스트')
  ..residentNo = rn;

void main() {
  group('마킹 형식 — 요구 예시와 일치하는가', () {
    test('870110-2324718 → 870120-2******  (요구 예시 그대로)', () {
      // 요구 원문의 예시는 앞 6자리를 870120 으로 적었지만 이는 오타로 보인다
      // (생년월일 870110 이 유지되어야 한다). 규칙은 "앞 6자리 + 성별1 + ******".
      final m = _m('870110-2324718');
      expect(m.residentNoMasked, '870110-2******');
      expect(m.residentNoMasked.length, 14);
      // 성별 자리(하이픈 뒤 첫 글자)는 **남긴다** — 요구 예시와 동일.
      expect(m.residentNoMasked.split('-')[1][0], '2');
      // 뒷자리 나머지 6자리는 모두 가린다.
      expect(m.residentNoMasked.endsWith('******'), isTrue);
    });

    test('990328-1234567 → 990328-1******', () {
      expect(_m('990328-1234567').residentNoMasked, '990328-1******');
    });

    test('하이픈 없이 13자리여도 정규화된다', () {
      expect(_m('8701102324718').residentNoMasked, '870110-2******');
    });

    test('이미 마킹된 값은 두 번 마킹해도 모양이 같다', () {
      expect(_m('870110-2******').residentNoMasked, '870110-2******');
    });

    test('빈 값은 빈 문자열', () {
      expect(_m('').residentNoMasked, '');
    });

    test('6자리(앞자리만) → 6자리-******', () {
      expect(_m('870110').residentNoMasked, '870110-******');
    });

    test('판단이 어려운 길이는 전부 가린다 (안전 우선)', () {
      final m = _m('12345');
      expect(m.residentNoMasked.contains('*'), isTrue);
      expect(m.residentNoMasked.contains(RegExp(r'\d')), isFalse);
    });

    test('원본은 보관된다 — 마킹은 표시 전용', () {
      final m = _m('870110-2324718');
      expect(m.residentNo, '870110-2324718');
    });

    test('hasResidentBack 은 뒷자리 존재 여부', () {
      expect(_m('870110-2324718').hasResidentBack, isTrue);
      expect(_m('870110').hasResidentBack, isFalse);
      expect(_m('').hasResidentBack, isFalse);
    });
  });

  group('출력물 — 원본을 명시하지 않으면 절대 새지 않는다', () {
    test('exportValueOf 기본값은 마킹본', () {
      final m = _m('870110-2324718');
      expect(exportValueOf(m, 'residentNo'), '870110-2******');
    });

    test('revealResidentNo: true 일 때만 원본', () {
      final m = _m('870110-2324718');
      expect(
        exportValueOf(m, 'residentNo', revealResidentNo: true),
        '870110-2324718',
      );
    });

    test('ExportService.rowFor 는 마킹본을 쓴다 (원본 노출 경로 없음)', () {
      final m = _m('870110-2324718');
      final row = ExportService.rowFor(m, ['name', 'residentNo']);
      expect(row[1], '870110-2******');
    });

    test('회원번호는 관리자·마스터, 주민번호는 마스터만 — 두 규칙이 독립적', () {
      final m = Member(id: 'x', number: '1', name: '테스트')
        ..residentNo = '870110-2324718'
        ..scoutNo = '16187';

      // 관리자 세션: 회원번호는 원본, 주민번호는 여전히 마킹.
      expect(
        exportValueOf(m, 'scoutNo', revealScoutNo: true),
        '16187',
      );
      expect(
        exportValueOf(m, 'residentNo', revealScoutNo: true),
        '870110-2******',
      );

      // 마스터 세션: 둘 다 원본.
      expect(
        exportValueOf(
          m,
          'residentNo',
          revealScoutNo: true,
          revealResidentNo: true,
        ),
        '870110-2324718',
      );
    });
  });

  group('소스 계약 — 화면이 마스터 전용인가', () {
    final edit = File('lib/screens/member_edit_screen.dart').readAsStringSync();
    final detail =
        File('lib/screens/member_detail_screen.dart').readAsStringSync();

    test('편집 화면이 isMaster 로 판정한다 (isApp 아님)', () {
      // _residentNoField 안에서만 검사한다 — 다른 필드(회원번호)는 isApp 유지.
      final body = edit.substring(
        edit.indexOf('Widget _residentNoField()'),
        edit.indexOf('Widget ', edit.indexOf('Widget _residentNoField()') + 10),
      );
      expect(body.contains('st.isMaster'), isTrue, reason: '마스터 전용');
      expect(
        body.contains('st.isApp'),
        isFalse,
        reason: '관리자까지 열리면 안 된다',
      );
    });

    test('편집 화면은 비마스터에게 마킹본을 채운다', () {
      expect(edit.contains('_residentNoView.text = masked'), isTrue);
    });

    test('상세 화면이 마스터만 원본을 그린다', () {
      expect(
        detail.contains('final isMasterForRn = isMaster;'),
        isTrue,
      );
      expect(
        detail.contains('isMasterForRn ? m.residentNo : m.residentNoMasked'),
        isTrue,
      );
    });

    test('상세 화면이 관리자 조건으로 원본을 열지 않는다', () {
      expect(
        detail.contains('admin ? m.residentNo : m.residentNoMasked'),
        isFalse,
        reason: '관리자 포함 조건이면 안 된다',
      );
    });

    test('마킹본이 원본을 덮어쓰지 않도록 보호한다', () {
      expect(edit.contains('_residentNoToSave()'), isTrue);
      expect(edit.contains("if (before.isEmpty) return typed;"), isTrue);
      expect(edit.contains('return before;'), isTrue);
    });

    test('입력·수정은 여전히 가능하다 (읽기 전용 해제 유지)', () {
      expect(edit.contains('readOnly: true'), isFalse);
      expect(edit.contains('enabled: false,'), isFalse);
    });
  });
}
