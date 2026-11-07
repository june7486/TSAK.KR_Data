// ─────────────────────────────────────────────────────────────────────────────
//  행사 상세 화면 — 로딩이 '영원한 스피너'로 갇히지 않는지 지키는 계약 테스트
//
//  [요구 turn70]
//    "후원금을 입력하거나 참가비를 입력 할 때 이렇게 로딩이 에러가 나는
//     문제가 생김 버그인지 오류인지 확인 해 줘"
//
//  ⚠️ 이 파일은 **소스 계약(source contract)** 테스트다.
//     `HomeScreen` / `EventDetailScreen` 을 실제로 pump 하면 이 샌드박스에서는
//     위젯 트리가 끝나지 않아 테스트가 영구 대기한다(알려진 제약).
//     그래서 위젯을 띄우는 대신, 소스에 '회복 불가 구조'가 다시 들어오지
//     않았는지 텍스트로 검사한다. 느리지만 결정적이고, 조용한 회귀를 잡는다.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;
  late String api;

  setUpAll(() {
    src = File('lib/screens/event_detail_screen.dart').readAsStringSync();
    api = File('lib/services/nas_api.dart').readAsStringSync();
  });

  group('① _load() 는 모든 경로에서 스피너를 내린다', () {
    test('try/finally 구조로 _loading 을 무조건 정리한다', () {
      // finally 블록이 존재하고, 그 안에서 _loading 을 false 로 되돌려야 한다.
      expect(src, contains('} finally {'));
      final fi = src.indexOf('} finally {');
      expect(fi, greaterThan(0), reason: '_load() 에 finally 가 있어야 한다');
      final tail = src.substring(fi, fi + 500);
      expect(
        tail,
        contains('_loading = false'),
        reason: 'finally 에서 _loading 을 내려야 영구 스피너가 사라진다',
      );
      expect(
        tail,
        contains('hideBusy()'),
        reason: 'finally 에서 전역 오버레이도 정리해야 한다',
      );
    });

    test('finally 직전 catch 에서도 _loading = false 를 보장한다', () {
      // ⚠️ `} catch (err) {` 는 _load() 안에 두 번 나온다(내부 재시도용 1개).
      //    바깥(마지막) catch 를 잡아야 하므로 finally 위치에서 역방향으로 찾는다.
      final fi = src.indexOf('} finally {');
      expect(fi, greaterThan(0));
      final ci = src.lastIndexOf('} catch (err) {', fi);
      expect(ci, greaterThan(0), reason: 'finally 앞에 바깥 catch 가 있어야 한다');
      final seg = src.substring(ci, fi);
      expect(seg, contains('_loading = false'));
    });

    test('실패 스낵바에 "다시 시도" 액션이 있다', () {
      // 스피너가 풀린 뒤 사용자가 스스로 회복할 수 있어야 한다.
      expect(src, contains("SnackBarAction(label: '다시 시도'"));
    });
  });

  group('② 로딩 전체에 마감시간(deadline)이 있다', () {
    test('_kLoadDeadline 상수가 선언되어 있다', () {
      expect(src, contains('_kLoadDeadline'));
      expect(
        src,
        contains('static const Duration _kLoadDeadline'),
        reason: '하드코딩 대신 한 곳에서 관리해야 튜닝이 안전하다',
      );
    });

    test('_fetchAll() 호출이 timeout 으로 감싸여 있다', () {
      final hits = '_fetchAll().timeout('.allMatches(src).length;
      expect(
        hits,
        2,
        reason: '1차 시도 + 1회 재시도 = 정확히 2곳이어야 한다',
      );
    });

    test('전체 재시도는 1회뿐이다 (2차 실패 시 포기)', () {
      // 재시도 사슬이 다시 길어지면 4분짜리 스피너가 부활한다.
      expect(src, contains(r"throw Exception('$err2 (1차: $firstErr)')"));
    });

    test('재무 재시도에도 12초 상한이 있다', () {
      expect(src, contains("onTimeout: () => throw TimeoutException('재무 응답 지연')"));
    });

    test('deep media 조회에도 상한이 있다', () {
      expect(src, contains('.timeout(const Duration(seconds: 18))'));
    });
  });

  group('③ 오래된 호출이 최신 결과를 덮어쓰지 않는다', () {
    test('진행 토큰(_loadSeq)으로 최신 호출을 판별한다', () {
      expect(src, contains('int _loadSeq = 0;'));
      expect(src, contains('final int mySeq = ++_loadSeq;'));
      expect(src, contains('bool isStale() => mySeq != _loadSeq;'));
    });

    test('setState 직전에 stale 검사를 한다', () {
      expect(
        src,
        contains('if (isStale() || !mounted) return;'),
        reason: '늦게 끝난 옛 호출이 새 화면을 빈 상태로 덮으면 안 된다',
      );
    });
  });

  group('④ 저장 후에는 재무만 다시 읽는다', () {
    test('_loadFinanceOnly() 가 존재한다', () {
      expect(src, contains('Future<void> _loadFinanceOnly() async {'));
    });

    test('_financeEdit 는 전체 _load() 대신 재무만 재조회한다', () {
      // 저장 직후 전체 재조회(5개 API)로 되돌아가면 이 테스트가 깨진다.
      final ei = src.indexOf('Future<void> _financeEdit(');
      expect(ei, greaterThan(0));
      // _financeEdit 본문 끝을 대략 잡아 검사
      final seg = src.substring(ei, ei + 20000);
      expect(seg, contains('await _loadFinanceOnly();'));
      expect(
        seg.contains('\n    await _load();\n'),
        isFalse,
        reason: '저장 후 전체 재조회로 회귀하면 안 된다',
      );
    });

    test('재무 전용 재조회는 스피너를 건드리지 않는다', () {
      final fi = src.indexOf('Future<void> _loadFinanceOnly() async {');
      final seg = src.substring(fi, fi + 2200);
      expect(
        seg.contains('_loading = true'),
        isFalse,
        reason: '재무만 갱신할 때 화면 전체를 스피너로 덮으면 안 된다',
      );
    });
  });

  group('⑤ 개별 API 타임아웃이 명시되어 있다', () {
    test('eventGet 은 12초', () {
      final i = api.indexOf('Future<Map<String, dynamic>> eventGet(');
      expect(i, greaterThan(0));
      final seg = api.substring(i, i + 900);
      expect(seg, contains('timeout: const Duration(seconds: 12)'));
    });

    test('eventFinance 는 12초', () {
      final i = api.indexOf('Future<Map<String, dynamic>> eventFinance(');
      expect(i, greaterThan(0));
      final seg = api.substring(i, i + 800);
      expect(seg, contains('timeout: const Duration(seconds: 12)'));
    });

    test('eventAccessMap 은 12초', () {
      final i = api.indexOf('Future<Map<String, dynamic>> eventAccessMap(');
      expect(i, greaterThan(0));
      final seg = api.substring(i, i + 800);
      expect(seg, contains('timeout: const Duration(seconds: 12)'));
    });

    test('eventFiles 는 60초 (대용량 폴더 허용)', () {
      final i = api.indexOf('Future<List<Map<String, dynamic>>> eventFiles(');
      expect(i, greaterThan(0));
      final seg = api.substring(i, i + 1400);
      expect(seg, contains('timeout: const Duration(seconds: 60)'));
    });
  });
}
