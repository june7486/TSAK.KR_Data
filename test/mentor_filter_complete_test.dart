// 멘토 · 페런츠 필터 — **인원 누락 방지** 회귀 테스트
//
// ## [요구 2026-11-04]
//   "멘토 버튼을 클릭하면 멘토로 등록된 네임카드가 나와야 하는데,
//    현재 일부 인원 이름이 누락되고 있음. 박인규, 민병인 등.."
//
// ## 실제 원인 (운영 DB 실측, fixture 로 고정)
//   · `mentees` 를 가진 회원은 **4명뿐**이고 그중 3명은 `mentees` 코드가
//     **자기 번호**다 (현승용 590 → [590]). 반쪽 연결 상태.
//   · 박인규(01064407181)·민병인(01082907590)은 **일반회원** → 회원카드에
//     `mentees` 가 없고, 멘토 신원은 `link_profiles`(`멘토:415`·`멘토:417`)에만 있다.
//   → 종전 필터(`m.mentees.isNotEmpty`)는 이들을 화면에서 지웠다.
//
// ## 고친 규칙
//   멘토 = `mentees` 보유 회원 **∪** `link_profiles` 멘토와 **전화번호가 일치**하는 회원
//
// 이 테스트는 위 규칙을 **fixture 실데이터**로 검증한다.
// ⚠️ HomeScreen 을 pump 하면 이 샌드박스에서 끝나지 않으므로 순수 함수로만 본다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/models/member.dart';
import 'package:tsak_credential_manager/models/link_person.dart';

List<Member> _members() {
  final j =
      json.decode(File('test/fixtures/link_mentors_sample.json')
              .readAsStringSync())
          as Map<String, dynamic>;
  return ((j['members'] as List?) ?? [])
      .cast<Map<String, dynamic>>()
      .map(Member.fromMap)
      .toList();
}

Map<String, dynamic> _profiles() {
  final j =
      json.decode(File('test/fixtures/link_profiles_sample.json')
              .readAsStringSync())
          as Map<String, dynamic>;
  return (j['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// AppState._profilePhones 와 동일한 규칙 (kind 별 전화번호 집합).
Set<String> profilePhones(Map<String, dynamic> profiles, String kind) {
  final out = <String>{};
  for (final v in profiles.values) {
    if (v is! Map) continue;
    if ('${v['kind'] ?? ''}'.trim() != kind) continue;
    final d = _digits('${v['phone'] ?? ''}');
    if (d.isNotEmpty) out.add(d);
  }
  return out;
}

/// 수정된 AppState 필터와 동일한 규칙.
List<Member> filterMentor(List<Member> all, Map<String, dynamic> profiles) {
  final phones = profilePhones(profiles, 'mentor');
  return all
      .where(
        (m) =>
            m.mentees.isNotEmpty ||
            phones.contains(_digits(m.phone)) ||
            phones.contains(_digits(m.accessPhone)),
      )
      .toList();
}

List<Member> filterParent(List<Member> all, Map<String, dynamic> profiles) {
  final phones = profilePhones(profiles, 'parent');
  return all
      .where(
        (m) =>
            m.parents.isNotEmpty ||
            phones.contains(_digits(m.phone)) ||
            phones.contains(_digits(m.accessPhone)),
      )
      .toList();
}

void main() {
  group('fixture 실데이터 — 누락되던 사람이 나오는가', () {
    final all = _members();
    final profs = _profiles();

    test('fixture 에 박인규·민병인이 들어 있다', () {
      expect(all.any((m) => m.name == '박인규'), isTrue);
      expect(all.any((m) => m.name == '민병인'), isTrue);
    });

    test('두 사람 모두 일반회원(인가번호 없음) — 회원카드만으론 못 찾는다', () {
      final p = all.firstWhere((m) => m.name == '박인규');
      final m = all.firstWhere((m) => m.name == '민병인');
      expect(p.number.trim().isEmpty, isTrue);
      expect(m.number.trim().isEmpty, isTrue);
      expect(p.mentees.isEmpty, isTrue);
      expect(m.mentees.isEmpty, isTrue);
    });

    test('박인규가 멘토 필터 결과에 나온다', () {
      final r = filterMentor(all, profs);
      expect(r.any((m) => m.name == '박인규'), isTrue,
          reason: 'link_profiles 멘토:415/417 의 전화번호로 매칭');
    });

    test('민병인은 **어느 저장소에도 멘토로 등록돼 있지 않다** (데이터 사실)', () {
      // 실측: 민병인(일반회원, 01082907590)
      //   · link_profiles → 없음
      //   · link/ledger(mentor) → 없음
      //   · 다른 회원의 mentors 배열 → 이 전화번호를 참조하는 곳 0건
      //   · 본인 mentors=[] mentees=[]
      // 즉 **화면 버그가 아니라 등록 누락**이다. 앱은 등록된 것만 보여줄 수 있다.
      // (앱에서 '민병인' 카드를 열어 멘토로 등록하면 즉시 목록에 나타난다.)
      final p = profs.values
          .whereType<Map>()
          .any((v) => _digits('${v['phone'] ?? ''}') == '01082907590');
      expect(p, isFalse, reason: 'link_profiles 에 없음');

      final linked = all.any(
        (m) => [...m.mentors, ...m.mentees, ...m.parents, ...m.children]
            .any((c) => _digits(c) == '01082907590'),
      );
      expect(linked, isFalse, reason: '어떤 연결에도 없음');
    });

    test('등록만 되면 민병인도 즉시 잡힌다 (규칙 검증)', () {
      // 앱에서 민병인을 멘토로 등록했을 때와 동일한 상황을 만든다.
      final withProfile = <String, dynamic>{
        ...profs,
        '멘토:9999': {
          'kind': 'mentor',
          'name': '민병인',
          'number': '',
          'phone': '010-8290-7590',
        },
      };
      final r = filterMentor(all, withProfile);
      expect(r.any((m) => m.name == '민병인'), isTrue,
          reason: '전화번호 매칭은 번호 없는 일반회원도 잡는다');
    });

    test('기존 mentees 보유자도 계속 나온다 (회귀 방지)', () {
      final r = filterMentor(all, profs);
      expect(r.any((m) => m.name == '현승용'), isTrue);
    });

    test('멘토가 아닌 사람은 나오지 않는다', () {
      final r = filterMentor(all, profs);
      // 김원태(305)는 멘티(mentors=[1089])일 뿐 멘토가 아니다.
      expect(r.any((m) => m.name == '김원태'), isFalse);
    });

    test('종전 규칙만 쓰면 누락되던 것을 확인 (회귀 근거)', () {
      final old = all.where((m) => m.mentees.isNotEmpty).toList();
      expect(old.any((m) => m.name == '박인규'), isFalse);
      expect(old.any((m) => m.name == '민병인'), isFalse);
    });

    test('페런츠 필터도 같은 방식으로 동작한다', () {
      final r = filterParent(all, profs);
      // 페런츠:2229(노본) · 페런츠:590(현승용)
      expect(r.isNotEmpty, isTrue);
    });
  });

  group('전화번호 정규화 — 표기가 달라도 같은 사람', () {
    test('하이픈 유무를 무시한다', () {
      final a = _digits('010-6440-7181');
      final b = _digits('01064407181');
      expect(a, b);
    });

    test('link_profiles 의 박인규 두 키가 같은 전화번호로 모인다', () {
      final p = _profiles();
      final p415 = (p['멘토:415'] as Map)['phone'];
      final p417 = (p['멘토:417'] as Map)['phone'];
      expect(_digits('$p415'), _digits('$p417'));
    });
  });

  group('kind 화이트리스트 — 멘토/페런츠만 포함', () {
    test('kind=mentor 만 멘토 전화번호 집합에 들어간다', () {
      final p = _profiles();
      final mentor = profilePhones(p, 'mentor');
      final parent = profilePhones(p, 'parent');
      // 노본은 kind=parent 로만 등록된 항목도 있다.
      expect(mentor.contains(_digits('010-3365-7480')), isTrue);
      expect(parent.contains(_digits('010-3365-7480')), isTrue);
      // 반대로 멘토에만 있는 번호는 parent 집합에 없다.
      expect(parent.contains(_digits('01082907590')), isFalse);
    });

    test('빈 전화번호는 집합에 넣지 않는다', () {
      final p = {
        '멘토:x': {'kind': 'mentor', 'name': '무전화', 'phone': ''},
      };
      expect(profilePhones(p, 'mentor').isEmpty, isTrue);
    });
  });

  group('LinkPerson — 번호 없는 멘토 표기', () {
    test('인가번호가 있으면 범#번호', () {
      final p = LinkPerson(name: '박인규', code: '417');
      expect(p.badge, '범#417');
      expect(p.hasCode, isTrue);
    });

    test('번호가 없으면 전화번호를 쓴다', () {
      final p = LinkPerson(name: '민병인', phone: '010-8290-7590');
      expect(p.badge, '010-8290-7590');
      expect(p.hasCode, isFalse);
    });

    test('말머리는 멘토/페런츠', () {
      expect(const LinkPerson(name: 'a').kindLabel, '멘토');
      expect(const LinkPerson(name: 'a', kind: 'parent').kindLabel, '페런츠');
    });

    test('소속 표기 — 연맹 · 소속대', () {
      final p = LinkPerson(name: '박인규', league: '경기남부', unit: '김포지역대');
      expect(p.org, '경기남부 · 김포지역대');
    });

    test('검색어에 이름·번호·전화·소속이 모두 들어간다', () {
      final p = LinkPerson(
        name: '박인규',
        code: '417',
        phone: '01064407181',
        league: '경기남부',
        unit: '김포지역대',
      );
      expect(p.searchText.contains('박인규'), isTrue);
      expect(p.searchText.contains('417'), isTrue);
      expect(p.searchText.contains('01064407181'), isTrue);
      expect(p.searchText.contains('김포지역대'), isTrue);
    });
  });

  group('소스 계약 — 필터가 link_profiles 를 보는가', () {
    final src = File('lib/services/app_state.dart').readAsStringSync();

    test('멘토 필터가 profilePhones 를 쓴다', () {
      expect(src.contains("final mentorPhones = _profilePhones('mentor');"), isTrue);
    });

    test('페런츠 필터도 profilePhones 를 쓴다', () {
      expect(src.contains("final parentPhones = _profilePhones('parent');"), isTrue);
    });

    test('accessPhone 도 비교한다 (번호 없는 일반회원)', () {
      expect(src.contains('_digitsOf(m.accessPhone)'), isTrue);
    });

    test('로그인·필터 진입 시 link_profiles 를 불러온다', () {
      expect(src.contains('unawaited(loadLinkProfiles())'), isTrue);
      expect(src.contains('Future<void> loadLinkProfiles()'), isTrue);
    });

    test('loadLinkProfiles 는 nas.linkProfiles 를 호출한다', () {
      expect(src.contains('await nas.linkProfiles()'), isTrue);
    });
  });
}
