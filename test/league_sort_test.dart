import 'package:flutter_test/flutter_test.dart';
import 'package:tsak_credential_manager/services/league_names.dart';

void main() {
  test('종교 연맹(가톨릭→원불교→기독교)은 가나다에서 맨 뒤', () {
    final keys = ['가톨릭', '강원', '원불교', '기독교', '서울', '제주', '(미지정)'];
    keys.sort(compareLeagueName);
    expect(keys,
        ['강원', '서울', '제주', '가톨릭', '원불교', '기독교', '(미지정)']);
  });

  test('권역 통합 라벨 — 대전·충남·세종', () {
    expect(leagueRegion('대전'), '대전·충남·세종');
    expect(leagueRegion('충남'), '대전·충남·세종');
    expect(leagueRegion('충남·세종'), '대전·충남·세종');
    expect(leagueRegion('대전·충남·세종'), '대전·충남·세종');
    expect(leagueRegion('서울남부'), '서울');
    expect(leagueRegion('가톨릭'), '가톨릭');
  });
}
