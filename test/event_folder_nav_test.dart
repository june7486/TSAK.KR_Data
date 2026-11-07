// ─────────────────────────────────────────────────────────────────────────────
//  행사 '사진+동영상' 폴더 탐색 — 화면 전체를 스피너로 덮지 않는지 지키는 계약
//
//  [요구 turn71]
//    "행사 폴더에서 자꾸 로딩이 걸림 급하게 수습해야 함"
//
//  증상: 폴더를 열 때마다 `body: _loading || _tab == null` 분기가 켜져
//        탭 바만 남고 본문이 사라졌다(작은 스피너).
//  원인: `_enterFolder()` / 브레드크럼 / `_refreshMedia()` 가 모두
//        **전체 `_load()`**(5개 API)를 다시 호출했다.
//
//  ⚠️ 소스 계약 테스트 — EventDetailScreen 을 실제로 pump 하면 이 샌드박스에서
//     위젯 트리가 끝나지 않는다(알려진 제약). 그래서 소스를 검사한다.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;
  late int loadMediaOnlyAt;

  setUpAll(() {
    src = File('lib/screens/event_detail_screen.dart').readAsStringSync();
    loadMediaOnlyAt = src.indexOf('Future<void> _loadMediaOnly({bool fresh = false}) async {');
  });

  group('① 폴더 이동 전용 경량 경로가 존재한다', () {
    test('_loadMediaOnly() 가 정의되어 있다', () {
      expect(loadMediaOnlyAt, greaterThan(0));
    });

    test('경량 경로는 화면 전체 스피너(_loading)를 켜지 않는다', () {
      final seg = src.substring(loadMediaOnlyAt, loadMediaOnlyAt + 2400);
      expect(
        seg.contains('_loading = true'),
        isFalse,
        reason: '폴더 이동이 화면 전체 스피너를 켜면 신고 증상이 재발한다',
      );
    });

    test('경량 경로는 목록 전용 표시(_mediaBusy)를 쓴다', () {
      final seg = src.substring(loadMediaOnlyAt, loadMediaOnlyAt + 2400);
      expect(seg, contains('_mediaBusy = true'));
      expect(seg, contains('_mediaBusy = false'));
    });

    test('경량 경로는 try/finally 로 진행 표시를 반드시 해제한다', () {
      final seg = src.substring(loadMediaOnlyAt, loadMediaOnlyAt + 2400);
      expect(seg, contains('} finally {'));
      expect(seg, contains('hideBusy()'));
    });

    test('폴더 이동은 기본적으로 캐시를 쓴다 (fresh 는 opt-in)', () {
      final seg = src.substring(loadMediaOnlyAt, loadMediaOnlyAt + 2600);
      expect(seg, contains('{bool fresh = false}'));
      expect(seg, contains('fresh: fresh,'));
      expect(
        seg.contains('fresh: true,'),
        isFalse,
        reason: '폴더 이동마다 NAS 강제 재조회(0.6s)를 하면 안 된다',
      );
    });

    test('경량 경로는 eventFiles(media) 만 호출한다', () {
      final seg = src.substring(loadMediaOnlyAt, loadMediaOnlyAt + 2600);
      expect(seg, contains("'media'"));
      // 다른 API 를 끌어오면 경량이 아니다.
      expect(seg.contains('eventGet('), isFalse);
      expect(seg.contains('eventFinance('), isFalse);
      expect(seg.contains('eventAccessMap('), isFalse);
      expect(seg.contains("'plan'"), isFalse);
    });
  });

  group('② 폴더 진입·브레드크럼이 전체 재조회로 회귀하지 않는다', () {
    test('_enterFolder 는 _loadMediaOnly() 를 부른다', () {
      final i = src.indexOf('void _enterFolder(String name');
      expect(i, greaterThan(0));
      final seg = src.substring(i, i + 900);
      expect(seg, contains('_loadMediaOnly();'));
      expect(
        seg.contains('    _load();\n'),
        isFalse,
        reason: '폴더 진입이 전체 _load() 로 돌아가면 로딩 지옥이 부활한다',
      );
    });

    test('브레드크럼(루트)은 _loadMediaOnly() 를 부른다', () {
      final i = src.indexOf("_crumb('사진+동영상'");
      expect(i, greaterThan(0));
      final seg = src.substring(i, i + 400);
      expect(seg, contains('_loadMediaOnly();'));
    });

    test('브레드크럼(중간 경로)은 _loadMediaOnly() 를 부른다', () {
      final i = src.indexOf('_mediaPath[i],');
      expect(i, greaterThan(0));
      final seg = src.substring(i, i + 700);
      expect(seg, contains('_loadMediaOnly();'));
    });

    test('나스 새로고침(_refreshMedia)은 _loadMediaOnly() 를 부른다', () {
      final i = src.indexOf('Future<void> _refreshMedia() async {');
      expect(i, greaterThan(0));
      final seg = src.substring(i, i + 700);
      expect(seg, contains('_loadMediaOnly(fresh: true);'));
      expect(seg.contains('await _load(fresh: true)'), isFalse);
    });

    test('폴더 생성(mkdir) 후에도 _loadMediaOnly() 를 부른다', () {
      final i = src.indexOf("if (!done) _snack('폴더 생성 실패');");
      expect(i, greaterThan(0));
      final seg = src.substring(i, i + 200);
      expect(seg, contains('_loadMediaOnly();'));
    });
  });

  group('③ 목록에만 진행 표시가 뜬다', () {
    test('_mediaBusy 상태에서 얇은 진행 막대를 그린다', () {
      expect(src, contains('if (_mediaBusy)'));
      expect(src, contains('LinearProgressIndicator(minHeight: 2.5)'));
    });

    test('_mediaBusy 필드가 선언되어 있다', () {
      expect(src, contains('bool _mediaBusy = false;'));
    });
  });

  group('④ 경량 경로도 race·평탄화 규칙을 지킨다', () {
    test('진행 토큰(_loadSeq)으로 오래된 응답을 버린다', () {
      final seg = src.substring(loadMediaOnlyAt, loadMediaOnlyAt + 2400);
      expect(seg, contains('final int mySeq = ++_loadSeq;'));
      expect(seg, contains('if (isStale() || !mounted) return;'));
    });

    test('폴더만 있으면 재귀 평탄화(deep)로 다시 받는다', () {
      final seg = src.substring(loadMediaOnlyAt, loadMediaOnlyAt + 2400);
      expect(seg, contains('deep: true'));
      expect(seg, contains('_mediaDeep = deep;'));
    });
  });
}
