// 검색 필터 **'초기화' 칩** 위치·모양·동작 회귀 테스트.
//
// ## 사용자 보고 (2026-11-02, build #577)
//  "초기화 위치 및 폰트가 어색함"  (스크린샷: 회비 칩들 사이에 끼어 있고
//   글자가 칩보다 크게 튀어 보임)
//
// ## 원인
//  ① 위치 — `ActionChip` 이 **회비 칩 목록 안**(가로 스크롤)의 끝에 붙어 있었다.
//     화면 폭에 따라 회비 칩들 중간에 끼어 보이고, 필터 조건이 바뀔 때마다
//     나타났다 사라져 위치가 들쭉날쭉했다.
//  ② 폰트 — `ActionChip` 은 Material 기본 스타일(라벨 14px + 기본 패딩 +
//     아바타 아이콘)이라, 직접 만든 `_filterChip`(10.5px · w600 · radius 14)과
//     글자 크기·높이가 달랐다.
//  ③ 동작 — `clearFilters()` 가 **소속(corps) 필터를 지우지 않았다**.
//     '은하스카우트'를 골라 143명이 보이는 상태에서 초기화를 눌러도 목록이
//     그대로여서 "초기화가 안 된다"로 보였다.
//
// ## 수정 계약
//  · 소속 줄을 `Row([스크롤 칩들][초기화])` 로 나눠 초기화를 **스크롤 밖
//    오른쪽 고정 슬롯**에 둔다.
//  · `_filterResetChip` 은 `_filterChip` 과 같은 10.5px·w600·radius 14 를 쓴다.
//  · 필터가 하나라도 걸렸을 때만 노출(빈 슬롯 방지) — 조건에 corpsFilter 포함.
//  · `clearFilters()` 는 query·league·year·lifetime·kind·**corps** 를 모두 지운다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readFile(String p) => File(p).readAsStringSync();

/// 주석(`//...`)을 지운 소스 — 주석 안에 등장하는 단어('초기화'·'ActionChip' 등)를
/// 코드로 오탐하지 않기 위해 검사 전에 반드시 통과시킨다.
String stripComments(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  late String home;
  late String state;

  setUpAll(() {
    home = stripComments(readFile('lib/screens/home_screen.dart'));
    state = stripComments(readFile('lib/services/app_state.dart'));
  });

  group('① clearFilters — 보이는 필터를 모두 되돌린다', () {
    late String body;

    setUpAll(() {
      final i = state.indexOf('void clearFilters() {');
      expect(i, greaterThan(0), reason: 'clearFilters 를 찾지 못함');
      body = state.substring(i, state.indexOf('refresh();', i));
    });

    test('검색어·연맹·회비·평생회원·회원종류를 지운다', () {
      expect(body.contains("_query = ''"), isTrue);
      expect(body.contains("_leagueFilter = ''"), isTrue);
      expect(body.contains("_yearFilter = ''"), isTrue);
      expect(body.contains('_onlyLifetime = false'), isTrue);
      expect(body.contains("_kindFilter = ''"), isTrue);
    });

    test('소속(범/은하) 필터도 지운다 — 보고된 버그의 핵심', () {
      expect(
        body.contains("_corpsFilter = ''"),
        isTrue,
        reason: "소속 필터가 남아 '은하스카우트 143명' 화면에서 초기화가 안 먹혔다",
      );
    });

    test('마지막에 refresh() 로 목록을 다시 계산한다', () {
      final i = state.indexOf('void clearFilters() {');
      final seg = state.substring(i, i + 800);
      expect(seg.contains('refresh();'), isTrue);
    });
  });

  group('② 노출 조건 — 소속 필터도 포함', () {
    test('hasFilter 조건에 corpsFilter 가 들어간다', () {
      final i = home.indexOf('final hasFilter =');
      expect(i, greaterThan(0), reason: 'hasFilter 를 찾지 못함');
      final seg = home.substring(i, i + 400);
      expect(seg.contains('state.corpsFilter.isNotEmpty'), isTrue);
      expect(seg.contains('state.query.isNotEmpty'), isTrue);
      expect(seg.contains('state.leagueFilter.isNotEmpty'), isTrue);
      expect(seg.contains('state.yearFilter.isNotEmpty'), isTrue);
      expect(seg.contains('state.onlyLifetime'), isTrue);
      expect(seg.contains('state.kindFilter.isNotEmpty'), isTrue);
    });

    test('조건은 한 곳(hasFilter)에서만 판단한다 — 중복 조건 금지', () {
      // 종전에는 회비 줄에 같은 조건이 길게 인라인으로 있었다.
      expect(
        home.contains('if (state.query.isNotEmpty ||\n                    state.leagueFilter'),
        isFalse,
        reason: '인라인 조건이 남아 있으면 hasFilter 와 어긋난다',
      );
    });
  });

  group('③ 위치 — 스크롤 밖 고정 슬롯', () {
    test('소속 줄이 Row([Expanded(HScrollMenu)][초기화]) 구조다', () {
      final i = home.indexOf('_filterResetChip(');
      expect(i, greaterThan(0), reason: '초기화 칩 호출을 찾지 못함');
      // 초기화 호출 **앞쪽**(같은 Row 안)에 스크롤 영역이 Expanded 로 감싸여 있어야 한다.
      final before = home.substring((i - 2600).clamp(0, i), i);
      expect(before.contains('Expanded('), isTrue,
          reason: '스크롤 칩 영역이 Expanded 로 감싸여 고정 슬롯과 분리돼야 한다');
      expect(before.contains('HScrollMenu('), isTrue);
      final seg = home.substring(i - 200, i + 600);
      expect(seg.contains('_filterResetChip('), isTrue);
      expect(
        seg.contains('if (hasFilter)'),
        isTrue,
        reason: '필터가 없을 때 빈 슬롯이 남으면 레이아웃이 어색해진다',
      );
    });

    test('회비 줄에는 초기화가 더 이상 없다', () {
      final i = home.indexOf("label: '평생회원'");
      expect(i, greaterThan(0));
      // 평생회원 칩부터 연맹 줄 전까지 = 회비 줄
      final j = home.indexOf("label: '전체 연맹'", i);
      expect(j, greaterThan(i));
      final feeRow = home.substring(i, j);
      expect(
        feeRow.contains("'초기화'"),
        isFalse,
        reason: '회비 칩 중간에 끼어 보이던 원인',
      );
      expect(feeRow.contains('ActionChip'), isFalse);
    });

    test('초기화를 누르면 검색창도 함께 비운다', () {
      final i = home.indexOf('_filterResetChip(');
      final seg = home.substring(i - 200, i + 400);
      expect(seg.contains('_searchCtrl.clear()'), isTrue);
      expect(seg.contains('state.clearFilters()'), isTrue);
    });
  });

  group('④ 폰트·모양 — _filterChip 과 통일', () {
    late String reset;

    setUpAll(() {
      final i = home.indexOf('Widget _filterResetChip(');
      expect(i, greaterThan(0), reason: '_filterResetChip 을 찾지 못함');
      reset = home.substring(i, i + 1400);
    });

    test('글자 크기 10.5 / 굵기 w600 — 일반 칩과 같다', () {
      expect(reset.contains('fontSize: 10.5'), isTrue);
      expect(reset.contains('FontWeight.w600'), isTrue);
    });

    test('모서리 반경 14 / 세로 패딩 3 / 가로 패딩 8 — 일반 칩과 같다', () {
      expect(reset.contains('BorderRadius.circular(14)'), isTrue);
      expect(
        reset.contains(
          'EdgeInsets.symmetric(horizontal: 8, vertical: 3)',
        ),
        isTrue,
      );
    });

    test('ActionChip 을 쓰지 않는다(기본 스타일이 원인이었다)', () {
      expect(reset.contains('ActionChip'), isFalse);
      expect(home.contains('ActionChip('), isFalse,
          reason: '필터 영역에서 ActionChip 을 완전히 제거했다');
    });

    test('아이콘은 12px 로 작게 — 라벨과 높이를 맞춘다', () {
      expect(reset.contains('Icon(Icons.refresh, size: 12'), isTrue);
    });
  });
}
