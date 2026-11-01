// 2026-11-01 8차 요구 — **실제 화면**(`link_profile_sheet.dart`) 3가지 변경 검증.
//
// ## 왜 이 파일이 필요한가 (7차의 실패를 되풀이하지 않기 위해)
//  7차에서는 같은 폼이 **두 곳**에 구현돼 있다는 사실을 놓쳐
//  `link_code_field.dart` 만 고쳤고, 사용자 화면(스크린샷)은 그대로였다.
//  그래서 이 테스트는 **두 구현 모두**를 검사한다.
//
// ## 사용자 요구 (원문 2026-11-01)
//  ① "페런츠 입력란에도 인가일/atas인가번호 입력란 삭제"
//  ② "마스터/관리자로 로그인시: 멘토, 페런츠 인적사항 추가란에 범스카우트
//      인가자번호 입력란에 인가자 이름, 번호를 조회하면 이름을 선택할 수 있도록
//      하고, 그 이름을 선택 후 해당 범인가자의 현재 활동정보가 자동으로
//      입력되도록 할 것, 멘토,페런츠,멘티 모두 같이 조회 후 그 정보가
//      입력되도록 할 것 (마스터, 관리자 로그인이 아닐 경우 개인정보 노출 위험이
//      있으므로 현재처럼 각각 입력할 수 있도록 함)"
//  ③ "text변경: 범스카우트 인가자 -> 멘토(페런츠)가 범인가인 경우"
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 화면 구현 파일 목록 — 멘토/페런츠 폼 2곳 + 멘티 시트 1곳.
const _profileSheet = 'lib/widgets/link_profile_sheet.dart';
const _codeField = 'lib/widgets/link_code_field.dart';
const _menteeSheet = 'lib/widgets/mentee_add_sheet.dart';
const _lookup = 'lib/widgets/tsak_name_lookup.dart';

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path 가 필요하다');
  return f.readAsStringSync();
}

void main() {
  late String sheet; // 실제 스크린샷의 그 창
  late String field; // 같은 기능의 두 번째 구현
  late String mentee; // 멘티 추가 시트
  late String lookup; // 공용 조회 위젯

  setUpAll(() {
    sheet = _read(_profileSheet);
    field = _read(_codeField);
    mentee = _read(_menteeSheet);
    lookup = _read(_lookup);
  });

  // ─────────────────────────────────────────────────────────────── ①
  group('① 인가일 · ATAS 인가번호 입력란 삭제 (멘토 + 페런츠)', () {
    for (final entry in {
      'link_profile_sheet.dart': _profileSheet,
      'link_code_field.dart': _codeField,
    }.entries) {
      test('${entry.key} — "인가일" 라벨이 없다', () {
        expect(
          RegExp(r"labelText:\s*'인가일'").hasMatch(_read(entry.value)),
          isFalse,
          reason: '인가일 입력란이 아직 화면에 남아 있다',
        );
      });

      test('${entry.key} — "ATAS 인가번호" 라벨이 없다', () {
        expect(
          RegExp(r"labelText:\s*'ATAS 인가번호'").hasMatch(_read(entry.value)),
          isFalse,
          reason: 'ATAS 인가번호 입력란이 아직 화면에 남아 있다',
        );
      });

      test('${entry.key} — 안내문에서 인가일·ATAS 언급이 사라졌다', () {
        final s = _read(entry.value);
        expect(s.contains('인가번호·인가일·ATAS번호를 입력하세요'), isFalse);
        expect(s.contains('인가자이면 인가번호를 입력하세요'), isTrue);
      });

      test('${entry.key} — 저장 키는 살아 있다(기존 데이터 보존)', () {
        final s = _read(entry.value);
        expect(s.contains("'inductedAt':"), isTrue, reason: '저장 키 유실');
        expect(s.contains("'atasNo':"), isTrue, reason: '저장 키 유실');
        expect(s.contains('inductedCtrl'), isTrue);
        expect(s.contains('atasCtrl'), isTrue);
      });
    }

    test('화면에서 감춘 값도 조회해 오면 살려 둔다(빈 칸일 때만)', () {
      // 인가일·ATAS 를 아예 저장하지 않으면 기존 값이 지워진다.
      expect(sheet.contains('fillIfEmpty(inductedCtrl, m.date)'), isTrue);
      expect(sheet.contains('fillIfEmpty(atasCtrl, m.atasNo)'), isTrue);
      expect(field.contains('fillIfEmpty(inductedCtrl, m.date)'), isTrue);
      expect(field.contains('fillIfEmpty(atasCtrl, m.atasNo)'), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────── ②
  group('② 마스터·관리자 전용 이름 조회 → 선택 → 활동정보 자동 입력', () {
    test('권한 판정 = 마스터 또는 관리자(isApp)', () {
      // 개인 로그인에 열면 인가자 개인정보를 아무나 조회할 수 있다.
      expect(
        lookup.contains('bool tsakIsAdminViewer(AppState state)'),
        isTrue,
      );
      expect(lookup.contains('state.isMaster || state.isApp'), isTrue);
    });

    test('세 화면 모두 권한 게이트를 쓴다', () {
      for (final s in [sheet, field, mentee]) {
        expect(s.contains('tsakIsAdminViewer('), isTrue);
      }
    });

    test('link_profile_sheet — 조회 필드가 이름/번호 검색을 안내한다', () {
      expect(sheet.contains('TsakMemberLookupField('), isTrue);
      expect(sheet.contains('이름/번호 조회'), isTrue);
      expect(sheet.contains('이름을 선택하면 현재 활동정보가 자동 입력됩니다'), isTrue);
    });

    test('link_profile_sheet — 조회 결과를 고르면 활동정보를 채운다', () {
      expect(sheet.contains('onPicked:'), isTrue);
      expect(sheet.contains('fillFromMember('), isTrue);
      for (final f in [
        'nameCtrl',
        'phoneCtrl',
        'leagueCtrl',
        'unitCtrl',
        'positionCtrl',
        'activityCtrl',
        'trainingCtrl',
      ]) {
        expect(
          RegExp('fillIfEmpty\\($f,').hasMatch(sheet),
          isTrue,
          reason: '$f 가 자동 채움 대상에서 빠졌다',
        );
      }
    });

    test('기존에 손으로 적은 값은 덮어쓰지 않는다', () {
      expect(sheet.contains('if (c.text.trim().isNotEmpty) return;'), isTrue);
      expect(field.contains('if (c.text.trim().isNotEmpty) return;'), isTrue);
    });

    test('재적 소속을 인가시 소속보다 우선한다', () {
      expect(
        sheet.contains('m.regLeague.trim().isNotEmpty ? m.regLeague : m.league'),
        isTrue,
      );
      expect(
        sheet.contains('m.regUnit.trim().isNotEmpty ? m.regUnit : m.unit'),
        isTrue,
      );
    });

    test('비관리자(개인 로그인)는 기존처럼 직접 입력한다', () {
      // 조회 필드는 canLookup 일 때만, 아니면 순수 TextField.
      expect(
        RegExp(r'if \(canLookup\)').hasMatch(sheet),
        isTrue,
        reason: '조회 필드에 권한 분기가 없다',
      );
      expect(sheet.contains('개인정보') || sheet.contains('개인 로그인'), isTrue);
    });

    test('멘티 시트도 같은 조회를 쓴다', () {
      expect(mentee.contains('TsakMemberLookupField('), isTrue);
      expect(mentee.contains('canLookup'), isTrue);
      // 선택 시 이름까지 채워 저장 전 확인이 가능해야 한다.
      expect(mentee.contains('_name.text = m.name.trim();'), isTrue);
    });

    test('조회 위젯이 이름 부분일치로 후보를 보여준다', () {
      expect(lookup.contains('bool contains'), isFalse);
      expect(lookup.contains('nm.contains(key)'), isTrue);
    });

    test('조회 위젯은 번호 완전일치를 먼저 본다', () {
      expect(lookup.contains('tsakDigits(m.number) == digits'), isTrue);
    });

    test('은하 번호는 G 접두어로 되돌려 넣는다', () {
      expect(lookup.contains("m.corps == 'eunha' ? 'G\$d' : d"), isTrue);
    });

    // ── 검색 규칙을 순수 함수로 재현해 계약을 고정 ──
    group('검색 규칙 (순수 함수 재현)', () {
      // tsak_name_lookup.dart 의 tsakSearchMembers 와 같은 규칙.
      List<String> search(String raw, List<(String no, String name)> pool) {
        final key = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        if (key.isEmpty) return const [];
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        final out = <String>[];
        void take((String, String) e) {
          final tag = '${e.$1}:${e.$2}';
          if (!out.contains(tag)) out.add(tag);
        }

        if (digits.isNotEmpty) {
          for (final e in pool) {
            if (e.$1 == digits) take(e);
          }
          for (final e in pool) {
            if (e.$1.startsWith(digits)) take(e);
          }
        }
        for (final e in pool) {
          if (e.$2.replaceAll(RegExp(r'\s+'), '').toLowerCase() == key) take(e);
        }
        for (final e in pool) {
          if (e.$2.replaceAll(RegExp(r'\s+'), '').toLowerCase().contains(key)) take(e);
        }
        return out;
      }

      final pool = <(String, String)>[
        ('415', '이승준'),
        ('75', '이항복'),
        ('1346', '양다솜'),
        ('2186', '김범수'),
        ('75', '김민수'), // 은하 75 (번호 중복)
      ];

      test('이름 일부만 적어도 후보가 나온다', () {
        expect(search('승준', pool), ['415:이승준']);
      });

      test('동명이인은 둘 다 보여 주고 사용자가 고른다', () {
        final r = search('김민수', pool);
        expect(r, contains('75:김민수'));
      });

      test('번호 완전일치가 앞자리 일치보다 먼저 온다', () {
        final r = search('75', pool);
        expect(r.first, '75:이항복');
        expect(r, contains('75:김민수'));
      });

      test('번호 앞자리로도 찾는다', () {
        expect(search('218', pool), contains('2186:김범수'));
      });

      test('일치 없으면 빈 목록', () {
        expect(search('없는사람', pool), isEmpty);
        expect(search('   ', pool), isEmpty);
      });

      test('같은 사람은 한 번만 나온다', () {
        final r = search('415', pool);
        expect(r.where((e) => e == '415:이승준').length, 1);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────── ③
  group('③ 문구 변경: 범스카우트 인가자 → 멘토(페런츠)가 범인가인 경우', () {
    const newLabel = '멘토(페런츠)가 범인가인 경우';

    test('link_profile_sheet 에 새 문구가 있다', () {
      expect(sheet.contains(newLabel), isTrue);
      expect(sheet.contains("'범스카우트 인가자'"), isFalse);
    });

    test('link_code_field 에 새 문구가 있다', () {
      expect(field.contains(newLabel), isTrue);
      expect(field.contains("'범스카우트 인가자'"), isFalse);
    });

    test('문구는 스위치 제목(title)으로 쓰인다', () {
      // `title:` 뒤 200자 안에 새 문구가 오는 자리가 하나 이상 있어야 한다.
      var i = sheet.indexOf('title:');
      var ok = false;
      while (i >= 0) {
        final tail = sheet.substring(
          i,
          (i + 200).clamp(0, sheet.length),
        );
        if (tail.contains(newLabel)) {
          ok = true;
          break;
        }
        i = sheet.indexOf('title:', i + 1);
      }
      expect(ok, isTrue, reason: '스위치 제목이 아니다');
    });
  });

  // ─────────────────────────────────────────────────────────────── 부가
  group('부가 — 문구·오탈자 정리', () {
    test('훈련현황 힌트의 "부교" 오탈자가 "부교수" 로 고쳐졌다', () {
      expect(sheet.contains('부교수'), isTrue);
      expect(RegExp(r'커미셔너과정 / 부교 /').hasMatch(sheet), isFalse);
    });

    test('자동 계정 안내가 멘토/페런츠를 구분한다', () {
      expect(sheet.contains("자동 생성 계정 (\${isMentor ? '멘토' : '페런츠'}"), isTrue);
      expect(sheet.contains('따로 아이디를 만들 필요가 없습니다'), isTrue);
    });
  });
}
