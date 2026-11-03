// 주민등록번호 **뒷자리 마킹** 규칙 회귀 테스트.
//
// ## 사용자 요구 (2026-11-02, build #574)
//  "주민등록정보는 뒷번호가 입력시 마킹처리가 안되고 있음
//   (예시: 990328-1******) / 노출되는(개인카드에도) 정보에는 뒷번호를
//   마킹처리하고 오로지 마스터만 뒷번호를 확인할 수 있도록 함"
//
// ## 규칙 (Member.residentNoMasked)
//  · 앞 6자리 + '-' + 뒷자리 첫 글자(성별) + '*' 6개
//  · 하이픈이 없어도 13자리면 같은 모양으로 정규화
//  · 이미 마킹된 값은 그대로
//  · 6자리만 있으면 `######-******`
//  · 그 외 이상 길이는 전부 마킹(안전 우선)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/widgets/privacy_consent.dart';

Member mk({String residentNo = '', String name = '테스트'}) => Member(
  id: 'm_${name}_$residentNo',
  number: '1',
  name: name,
  residentNo: residentNo,
);

void main() {
  group('① residentNoMasked — 마킹 형태', () {
    test('요구 예시 그대로: 990328-1234567 → 990328-1******', () {
      // 사용자가 예시로 든 바로 그 형태.
      expect(mk(residentNo: '990328-1234567').residentNoMasked, '990328-1******');
    });

    test('하이픈이 없어도 13자리면 하이픈을 넣어 마킹한다', () {
      expect(mk(residentNo: '9903281234567').residentNoMasked, '990328-1******');
    });

    test('뒷자리가 2로 시작하면(여성) 성별 숫자를 보존한다', () {
      expect(mk(residentNo: '900101-2345678').residentNoMasked, '900101-2******');
    });

    test('공백·구분자가 섞여도 숫자만 뽑아 판단한다', () {
      expect(mk(residentNo: ' 990328 - 1234567 ').residentNoMasked, '990328-1******');
    });

    test('이미 마킹된 값은 두 번 마킹하지 않는다', () {
      const already = '990328-1******';
      expect(mk(residentNo: already).residentNoMasked, already);
    });

    test('앞 6자리만 입력된 경우에도 뒷자리가 없다고 표시한다', () {
      expect(mk(residentNo: '990328').residentNoMasked, '990328-******');
    });

    test('빈 값은 빈 문자열(행을 만들지 않게)', () {
      expect(mk(residentNo: '').residentNoMasked, '');
      expect(mk(residentNo: '   ').residentNoMasked, '');
    });

    test('이상 길이는 전부 가린다 — 원본 숫자를 절대 흘리지 않는다', () {
      final masked = mk(residentNo: '123').residentNoMasked;
      expect(masked.contains(RegExp(r'[0-9]')), isFalse,
          reason: '판단 불가능한 값은 숫자를 노출하면 안 된다');
    });
  });

  group('② 원본 보존 / 뒷자리 유무', () {
    test('마킹은 표시 전용 — 원본 residentNo 는 그대로 남는다', () {
      final m = mk(residentNo: '990328-1234567');
      expect(m.residentNo, '990328-1234567');
      expect(m.residentNoMasked, isNot(m.residentNo));
    });

    test('hasResidentBack — 뒷자리가 채워졌는지 판단', () {
      expect(mk(residentNo: '990328-1234567').hasResidentBack, isTrue);
      expect(mk(residentNo: '9903281234567').hasResidentBack, isTrue);
      expect(mk(residentNo: '990328').hasResidentBack, isFalse);
      expect(mk(residentNo: '').hasResidentBack, isFalse);
    });
  });

  group('③ 화면이 마스터만 원본을 보는지 (소스 계약)', () {
    late String detail;
    late String edit;

    setUpAll(() {
      detail = File(
        'lib/screens/member_detail_screen.dart',
      ).readAsStringSync();
      edit = File('lib/screens/member_edit_screen.dart').readAsStringSync();
    });

    test('상세정보 — 마스터가 아니면 마킹본을 쓴다', () {
      expect(
        detail.contains('isMasterForRn ? m.residentNo : m.residentNoMasked'),
        isTrue,
        reason: '마스터만 원본, 나머지는 마킹본',
      );
    });

    test('편집화면 — 주민번호 필드가 마스터 분기를 가진 헬퍼로 교체됐다', () {
      expect(edit.contains('Widget _residentNoField()'), isTrue);
      expect(edit.contains('final canSeeAll = st.isApp'), isTrue);
      expect(
        edit.contains('final masked = m?.residentNoMasked'),
        isTrue,
        reason: '비마스터는 마킹본만 본다',
      );
      // [turn 37] "입력 및 수정가능하도록" 요구로 읽기 전용을 해제했다.
      // 대신 마킹본이 원본을 덮어쓰지 않도록 _residentNoToSave() 가 방어한다.
      expect(edit.contains('readOnly: true'), isFalse);
      expect(edit.contains('_residentNoToSave()'), isTrue);
    });

    test('상세화면은 주민번호 원본을 직접 그리지 않는다', () {
      expect(
        detail.contains("['주민등록번호', 'residentNo', m.residentNo]"),
        isFalse,
        reason: '종전 코드 — 권한이 있으면 뒷자리까지 그대로 보였다',
      );
    });
  });

  group('④ 동의 문구에 비밀번호·사진·인가정보 조항이 들어갔다', () {
    late String t;
    setUpAll(() => t = PrivacyConsentField.consentText);

    test('인가정보 항목이 명시된다', () {
      expect(t.contains('인가정보'), isTrue);
      expect(t.contains('범인가번호'), isTrue);
      expect(t.contains('ATAS 인가번호'), isTrue);
    });

    test('비밀번호 관리 원칙 조항이 있다', () {
      expect(t.contains('비밀번호 관리 원칙'), isTrue);
      expect(t.contains('원문을 보관·표시하지 않습니다'), isTrue);
    });

    test('주민등록번호 마킹 정책이 조항으로 들어갔다', () {
      expect(t.contains('제24조의2'), isTrue);
      expect(t.contains('뒷자리를 마킹'), isTrue);
      expect(t.contains('마스터만'), isTrue);
    });

    test('사진(초상) 조항과 프로필 사진 언급이 있다', () {
      expect(t.contains('사진(초상) 처리'), isTrue);
      expect(t.contains('프로필 사진'), isTrue);
    });

    test('연결정보(멘토·페런츠·멘티·자녀) 항목이 있다', () {
      expect(t.contains('멘토'), isTrue);
      expect(t.contains('페런츠'), isTrue);
      expect(t.contains('멘티'), isTrue);
      expect(t.contains('자녀대원'), isTrue);
    });

    test('동의를 거부할 권리 조항이 유지된다', () {
      expect(t.contains('거부할 권리'), isTrue);
      expect(t.contains('제15조'), isTrue);
      expect(t.contains('제17조'), isTrue);
    });
  });
}
