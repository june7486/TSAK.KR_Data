// **개인정보 활용 편집** 화면 + 출력물 주민번호 마킹 회귀 테스트.
//
// ## 사용자 요구 (2026-11-02, build #574)
//  · "주민등록정보는 뒷번호가 입력시 마킹처리가 안되고 있음 (예시: 990328-1******)
//     / 노출되는(개인카드에도) 정보에는 뒷번호를 마킹처리하고 오로지 마스터만
//     뒷번호를 확인할 수 있도록 함"
//  · "개인정보 활용 편집: 입수한 정보에 대한 추가내용을 넣어줘.
//     비밀번호, 사진, 인가정보 등등"
//
// ## 이 테스트가 지키는 계약
//  ① 모델 — 원본은 보존, 표시는 마킹 (resident_no_masking_test.dart 가 상세 검증)
//  ② 출력물 — 엑셀·PDF·워드·TXT·PPT 모든 경로가 같은 추출기를 쓴다 → 마킹본
//  ③ 개인정보 활용 편집 화면 — 비밀번호 원문 미표시, 인가정보·사진·연결정보·
//     항목별 노출 편집이 모두 존재
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/services/export_service.dart';

Member mk({
  String id = 'm1',
  String number = '893',
  String name = '이소라',
  String residentNo = '990328-1234567',
  String date = '',
  String league = '경남',
  String unit = '제4004대 김해푸르미지역대',
  String phone = '010-6770-0120',
  String personalPassword = '0120!@@',
  String accessPhone = '',
  String photoPath = '',
  List<String> mentors = const [],
  List<String> parents = const [],
  List<String> mentees = const [],
  List<String> children = const [],
}) => Member(
  id: id,
  number: number,
  name: name,
  residentNo: residentNo,
  date: date,
  league: league,
  unit: unit,
  phone: phone,
  personalPassword: personalPassword,
  accessPhone: accessPhone,
  photoPath: photoPath,
  mentors: mentors,
  parents: parents,
  mentees: mentees,
  children: children,
);

void main() {
  group('① 출력물 — 주민번호는 마킹본으로 나간다', () {
    test('엑셀/PDF/워드/TXT/PPT 공통 추출기가 마킹본을 준다', () {
      final m = mk();
      // 모든 builder 는 rowOf/rowFor → exportValueOf 를 거친다.
      expect(exportValueOf(m, 'residentNo'), '990328-1******');
      expect(ExportService.rowOf(m).contains('990328-1234567'), isFalse,
          reason: '원본 뒷자리가 출력물 행에 절대 들어가면 안 된다');
      expect(
        ExportService.rowFor(m, const ['name', 'residentNo']).last,
        '990328-1******',
      );
    });

    test('명시적으로 revealResidentNo=true 일 때만 원본(마스터 전용 경로)', () {
      final m = mk();
      expect(
        exportValueOf(m, 'residentNo', revealResidentNo: true),
        '990328-1234567',
      );
    });

    test('기본값은 false — 새 호출부가 생겨도 실수로 원본이 새지 않는다', () {
      // 함수 시그니처의 기본값 자체를 계약으로 고정한다.
      final src = File(
        'lib/services/export_service.dart',
      ).readAsStringSync();
      expect(src.contains('bool revealResidentNo = false'), isTrue);
    });

    test('주민번호가 비어 있으면 빈 문자열', () {
      expect(exportValueOf(mk(residentNo: ''), 'residentNo'), '');
    });
  });

  group('② 개인정보 활용 편집 화면 — 소스 계약', () {
    late String src;

    setUpAll(() {
      final f = File('lib/screens/privacy_usage_edit_screen.dart');
      expect(f.existsSync(), isTrue, reason: '화면 파일이 있어야 한다');
      src = f.readAsStringSync();
    });

    test('마스터 전용으로 열린다', () {
      expect(src.contains('if (!state.isMaster)'), isTrue);
      expect(src.contains('마스터 권한이 필요합니다'), isTrue);
    });

    test('비밀번호는 원문을 표시하지 않는다', () {
      expect(src.contains('원문을 볼 수 없고'), isTrue);
      expect(src.contains("설정됨 (원문 비표시)"), isTrue);
      // personalPassword 값을 그대로 그리는 코드가 있으면 실패.
      expect(
        RegExp(r'personalPassword').allMatches(src).length,
        1,
        reason: 'personalPassword 는 "설정됨/미설정" 판단에만 쓰여야 한다',
      );
    });

    test('입수한 인가정보 항목이 모두 나온다', () {
      for (final label in [
        '범인가번호',
        '인가일',
        '소속 연맹',
        '등록 단위대',
        'ATAS 인가번호',
        'ATAS 인가일',
        '영문 이름',
        '훈련현황',
      ]) {
        expect(src.contains("'$label'"), isTrue, reason: '$label 항목 누락');
      }
    });

    test('사진·연결정보 블록이 있다', () {
      expect(src.contains('사진 (초상)'), isTrue);
      expect(src.contains('프로필 사진'), isTrue);
      expect(src.contains('멘토 (나를 배출한 대장)'), isTrue);
      expect(src.contains('페런츠 (나의 부모)'), isTrue);
      expect(src.contains('멘티 (내가 배출한 대원)'), isTrue);
      expect(src.contains('자녀대원'), isTrue);
    });

    test('항목별 노출 3단계 + 전역 따름을 편집할 수 있다', () {
      expect(src.contains('AppState.permPublic'), isTrue);
      expect(src.contains('AppState.permAdmin'), isTrue);
      expect(src.contains('AppState.permHidden'), isTrue);
      expect(src.contains('전역 설정 따름'), isTrue);
      expect(src.contains('setMemberFieldPerm'), isTrue);
    });

    test('주민번호는 원본(마스터)과 표시용 마킹본을 함께 보여준다', () {
      expect(src.contains('표시용(타인·관리자): '), isTrue);
      expect(src.contains('residentNoMasked'), isTrue);
    });

    test('동의 문구 전문이 화면에 포함된다', () {
      expect(src.contains('PrivacyConsentField.consentText'), isTrue);
    });
  });

  group('③ 상세정보 카드에서 편집 화면으로 들어갈 수 있다', () {
    test('마스터에게만 진입 버튼이 보인다', () {
      final src = File(
        'lib/screens/member_detail_screen.dart',
      ).readAsStringSync();
      expect(src.contains('showPrivacyUsageEdit(context, m)'), isTrue);
      expect(src.contains("'개인정보 활용'"), isTrue);
      expect(src.contains('isMaster\n          ? TextButton.icon'), isTrue);
    });
  });
}
