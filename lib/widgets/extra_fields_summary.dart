import 'package:flutter/material.dart';


import '../services/extra_fields.dart';
import '../theme/app_theme.dart';

/// 행사 **추가입력사항 취합(집계) 시트**.
///
/// ## 요구 (원문 2026-10-30)
///  > "추가입력사항도 매우 중요한 정보야
///  >  이 내용도 자세히 보여주고 정리되고 출력시 구분해서 보여져야 해,
///  >  그리고 **항목별로 취합도 가능해야 해**"
///
/// ## 무엇을 하는가
///  참석자 전원의 추가입력 값을 **항목별로 모아** 한 화면에 정리한다.
///
///  · **선택형 항목**(이동방법·숙박여부·도착시간) → 값별 인원수 + 비율 막대
///    `자차 2명 (40%) / 대중교통 1명 (20%) / 미입력 2명`
///  · **자유 입력 항목**(출발장소·소요시간·동행자·주소·전달사항)
///    → 값별 명단 `인천 송도: 김승수, 이승준`
///  · **전달사항(요청)** 은 맨 위에 전부 펼쳐 보여준다 — 놓치면 사고가 난다.
///
/// ## 왜 시트인가
///  행사 상세 화면을 떠나지 않고 확인해야 현장에서 쓸 수 있다.
///  (차량 배차·방 배정·식이요법 확인을 참석자 목록 보면서 해야 한다)
Future<void> showExtraFieldsSummary(
  BuildContext context, {
  required String eventTitle,
  required List<Map<String, dynamic>> attendees,
  List<Map<String, dynamic>>? members,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExtraSummarySheet(
      eventTitle: eventTitle,
      attendees: attendees,
      members: members ?? const <Map<String, dynamic>>[],
    ),
  );
}

class _ExtraSummarySheet extends StatelessWidget {
  const _ExtraSummarySheet({
    required this.eventTitle,
    required this.attendees,
    required this.members,
  });

  final String eventTitle;
  final List<Map<String, dynamic>> attendees;
  final List<Map<String, dynamic>> members;

  /// 값이 하나라도 있는 참석자만 집계 대상(빈 행으로 통계가 흐려지지 않게).
  List<Map<String, dynamic>> get _rows => attendees;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final filled = _rows.where((a) => ExtraFields.filledCount(a) > 0).length;
    final msgs = <String>[];
    for (final a in _rows) {
      final v = ExtraFields.message.valueOf(a);
      if (v.isEmpty) continue;
      final nm = '${a['name'] ?? ''}'.trim();
      msgs.add('${nm.isEmpty ? '(이름없음)' : nm} — $v');
    }
    return Container(
      height: h * 0.9,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          // ── 헤더 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
            decoration: const BoxDecoration(
              color: AppColors.purple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.summarize, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '추가입력사항 취합',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$eventTitle · 참석 ${_rows.length}명 '
                        '(입력 $filled명)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
              children: [
                if (filled == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        '이 행사에는 아직 추가입력사항이 없습니다.',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                    ),
                  )
                else ...[
                  // ── ① 전달사항 먼저 (가장 중요) ──
                  if (msgs.isNotEmpty) _msgCard(msgs),
                  // ── ② 선택형 항목 집계 ──
                  for (final f in ExtraFields.countable)
                    _tallyCard(f, ExtraFields.tally(f, _rows)),
                  // ── ③ 자유 입력 목록형 ──
                  for (final f in ExtraFields.all)
                    if (!ExtraFields.countable.contains(f))
                      _listCard(f, ExtraFields.listOf(f, _rows)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 전달사항 — 전부 펼쳐 보여준다(접지 않는다).
  Widget _msgCard(List<String> msgs) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    color: AppColors.taegeukRed.withValues(alpha: 0.06),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.campaign,
                size: 16,
                color: AppColors.taegeukRed,
              ),
              const SizedBox(width: 6),
              const Text(
                '운영진 전달사항',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.taegeukRed,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${msgs.length}건',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final m in msgs)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '· $m',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  /// 선택형 항목 집계 — 값별 인원 + 막대.
  Widget _tallyCard(ExtraField f, Map<String, int> tally) {
    final total = tally.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return _emptyCard(f);
    }
    final accent = ExtraFields.colorOf(f.group);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(f.icon, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  '응답 $total명',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final e in tally.entries) ...[
              Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: e.key == '미입력'
                            ? AppColors.textGray
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : e.value / total,
                        minHeight: 8,
                        backgroundColor: AppColors.textGray.withValues(
                          alpha: 0.15,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          e.key == '미입력'
                              ? AppColors.textGray.withValues(alpha: 0.5)
                              : accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 58,
                    child: Text(
                      '${e.value}명 (${(e.value / total * 100).round()}%)',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
            ],
          ],
        ),
      ),
    );
  }

  /// 자유 입력 항목 — 값별 명단.
  Widget _listCard(ExtraField f, Map<String, List<String>> list) {
    if (list.isEmpty) return _emptyCard(f);
    final accent = ExtraFields.colorOf(f.group);
    final entries = list.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(f.icon, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  '${list.length}종',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${e.value.length}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.textDark,
                          ),
                          children: [
                            TextSpan(
                              text: e.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: ' — ${e.value.join(', ')}',
                              style: const TextStyle(
                                color: AppColors.textGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(ExtraField f) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(f.icon, size: 15, color: AppColors.textGray),
          const SizedBox(width: 6),
          Text(
            f.label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textGray,
            ),
          ),
          const Spacer(),
          const Text(
            '입력 없음',
            style: TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    ),
  );
}

/// 문자열만으로 인원 요약을 만든다(출력·클립보드용).
///
/// 결산자료·CSV 에서 같은 문구를 쓰도록 여기서 한 번만 만든다.
String extraSummaryLine(
  List<Map<String, dynamic>> attendees, {
  bool includeMessage = true,
}) {
  final out = <String>[];
  for (final f in ExtraFields.countable) {
    final t = ExtraFields.tally(f, attendees);
    if (t.isEmpty) continue;
    out.add(
      '${f.label}: '
      '${t.entries.map((e) => '${e.key} ${e.value}').join(' / ')}',
    );
  }
  if (includeMessage) {
    final msgs = <String>[];
    for (final a in attendees) {
      final v = ExtraFields.message.valueOf(a);
      if (v.isEmpty) continue;
      final nm = '${a['name'] ?? ''}'.trim();
      msgs.add('${nm.isEmpty ? '(이름없음)' : nm}: $v');
    }
    if (msgs.isNotEmpty) out.add('운영진 전달사항: ${msgs.join(' | ')}');
  }
  return out.join('\n');
}
