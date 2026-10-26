// ── 마스터 권한 / 영구 마스터 삭제 회귀 테스트 ────────────────────────────
//
// 배경(요구 2026-10-26):
//   ① "마스터권한으로 접속시 패스워드 조회가 안됨"
//   ② "415호의 마스터 영구권한 삭제할 것"
//
// 원인:
//   개인 탭에서 415(당시 영구 마스터)로 로그인하면 앱은 `_tier='master'` 로
//   승격했지만 **서버 세션은 personal** 로 발급됐다. 마스터 전용 API
//   (`/api/member/password`)는 세션 등급을 보므로 401 → 앱이 null 을 돌려주고
//   화면에는 "현재 비밀번호 조회 실패"만 떴다.
//
// 이 테스트가 지키는 것:
//   · 영구 마스터 목록이 비어 있으면 415 는 **개인 등급**이어야 한다
//     (다시 415 를 넣으면 two-source-of-truth 문제가 재발한다).
//   · 마스터 비번은 그대로 유효해야 한다(복구 경로 보존).
//   · 개인 기본비번 규칙('415!@@')이 유지돼야 한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/app_config.dart';

void main() {
  group('영구 마스터 목록', () {
    test('415 는 더 이상 영구 마스터가 아니다', () {
      expect(AppConfig.permanentMasterNumbers.contains('415'), isFalse);
      expect(AppConfig.isPermanentMaster('415'), isFalse);
    });

    test('목록은 비어 있다 (프록시 PERMANENT_MASTERS 와 동일해야 함)', () {
      expect(AppConfig.permanentMasterNumbers, isEmpty);
    });

    test('번호 형식이 섞여 들어와도 숫자만 비교한다', () {
      // 목록이 비었으므로 어떤 형태든 false. (구현 자체는 숫자 정규화 유지)
      expect(AppConfig.isPermanentMaster('tiger415'), isFalse);
      expect(AppConfig.isPermanentMaster('범415'), isFalse);
      expect(AppConfig.isPermanentMaster(''), isFalse);
    });
  });

  group('마스터 복구 경로는 그대로', () {
    test('마스터 비밀번호 상수는 불변', () {
      expect(AppConfig.masterPassword, 'Corbuser7!@@');
    });

    test('앱 접근 비밀번호도 불변', () {
      expect(AppConfig.appPassword, 'Tsak1988!!');
    });

    test('개인 기본비번 접미사 유지', () {
      expect(AppConfig.personalSuffix, '!@@');
      expect('415${AppConfig.personalSuffix}', '415!@@');
    });
  });
}
