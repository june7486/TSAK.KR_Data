import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 🌐 같은 IP 다계정 접속 현황 — **참고 표** (turn69)
///
/// ## 사용자 요구 (그대로)
///   "3. 3계정/15분 단, 경고만 팝업하고 기능 및 권한 제약은 없음,
///       경고 및 확인만 시켜주려는 목적 임"
///
/// ## 이 화면의 정체
///   **차단 장치가 아니다.** 관리자가 승인 작업을 하다가
///   "이 IP 에서 여러 계정이 들어왔네" 를 알아채는 **참고 자료**다.
///   · 조회만 한다(쓰기·차단·권한 변경 API 를 부르지 않는다).
///   · 가족·기관이 같은 IP 를 쓰는 경우가 흔하므로, 표시만 하고
///     회원을 자동으로 의심 처리하지 않는다.
///
/// ## 표시 규칙
///   2계정 이상 겹친 IP 대역만 보여준다(1계정은 '다계정'이 아니다).
///   위험도: 3계정 이상 = 주의(high), 2계정 = 관찰(watch).
///   임계값·창(분)은 **서버가 내려준 값**을 그대로 쓴다(화면에 하드코딩 금지).
///   → 기준을 바꾸면 서버 한 곳만 고치면 되고, 화면과 기준이 어긋나지 않는다.
class IpSeenPanel extends StatefulWidget {
  const IpSeenPanel({super.key, this.initiallyExpanded = false});

  /// 승인 화면 안에 들어가므로 기본은 접힘 — 표가 길어 업무를 가리지 않게.
  final bool initiallyExpanded;

  @override
  State<IpSeenPanel> createState() => _IpSeenPanelState();
}

class _IpSeenPanelState extends State<IpSeenPanel> {
  bool _open = false;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  List<Map<String, dynamic>> _groups = [];
  int _threshold = 3;
  int _windowMin = 15;
  int _highCount = 0;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyExpanded;
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await context.read<NasApi>().securityIpSeen();
      if (!mounted) return;
      setState(() {
        _groups = ((j['groups'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _threshold = (j['threshold'] as num?)?.toInt() ?? 3;
        _windowMin = (j['windowMin'] as num?)?.toInt() ?? 15;
        _highCount = (j['highCount'] as num?)?.toInt() ?? 0;
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했습니다: $e';
        _loading = false;
        _loaded = true;
      });
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && !_loaded) _load();
  }

  @override
  Widget build(BuildContext context) {
    final high = _highCount > 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더 (탭하면 펼침) ──
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(
                    high ? Icons.gpp_maybe : Icons.shield_outlined,
                    size: 18,
                    color: high ? AppColors.taegeukRed : AppColors.taegeukBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '같은 IP 다계정 접속 현황 (참고)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: high
                                ? AppColors.taegeukRed
                                : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _loaded
                              ? (_groups.isEmpty
                                  ? '겹친 대역 없음 · $_windowMin분 기준'
                                  : '${_groups.length}개 대역 · '
                                      '$_windowMin분 내 $_threshold계정 이상 ${high ? "있음" : "없음"}')
                              : '$_windowMin분 내 $_threshold계정 이상 접속 표시',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textGray),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textGray),
                ],
              ),
            ),
          ),

          if (_open) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '이 목록은 참고용입니다. 차단·권한 제약은 하지 않습니다.',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                          height: 1.4),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('새로고침',
                        style: TextStyle(fontSize: 11.5)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.taegeukRed)),
              )
            else if (_loaded && _groups.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 14),
                child: Text('같은 IP 로 2개 이상 계정이 접속한 기록이 없습니다.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textGray)),
              )
            else
              for (final g in _groups) _groupCard(g),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _groupCard(Map<String, dynamic> g) {
    final band = (g['band'] ?? '').toString();
    final rows = ((g['accounts'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final risk = (g['risk'] ?? '').toString();
    final isHigh = risk == 'high';
    // 마지막 계정이 1개뿐이면 표로 그릴 이유가 없다(서버가 이미 걸러준다).
    final alerted = g['alerted'] == true;
    final lastAlert = (g['lastAlert'] ?? '').toString();
    final loginCount = (g['loginCount'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHigh
              ? AppColors.taegeukRed.withValues(alpha: 0.35)
              : AppColors.textGray.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isHigh
                  ? AppColors.taegeukRed.withValues(alpha: 0.07)
                  : AppColors.taegeukBlue.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Icon(isHigh ? Icons.warning_amber_rounded : Icons.info_outline,
                    size: 15,
                    color:
                        isHigh ? AppColors.taegeukRed : AppColors.taegeukBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$band 대역',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color:
                            isHigh ? AppColors.taegeukRed : AppColors.textDark),
                  ),
                ),
                Text(
                  '${rows.length}계정 · $loginCount회',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),

          // ── 표 본체 ──
          Table(
            border: TableBorder(
              horizontalInside: BorderSide(
                  color: AppColors.textGray.withValues(alpha: 0.18)),
            ),
            columnWidths: const {
              0: FlexColumnWidth(1.1), // 인가번호
              1: FlexColumnWidth(1.6), // 이름
              2: FlexColumnWidth(0.7), // 횟수
              3: FlexColumnWidth(2.0), // 최근
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                    color: AppColors.textGray.withValues(alpha: 0.06)),
                children: const [
                  _Th('인가번호'),
                  _Th('이름'),
                  _Th('횟수', center: true),
                  _Th('최근 접속'),
                ],
              ),
              for (final r in rows)
                TableRow(children: [
                  _Td((r['ident'] ?? '').toString()),
                  _Td(
                    (r['name'] ?? '').toString().isEmpty
                        ? '-'
                        : (r['name'] ?? '').toString(),
                  ),
                  _Td('${(r['count'] as num?)?.toInt() ?? 0}', center: true),
                  _Td(_shortTime((r['last'] ?? '').toString())),
                ]),
            ],
          ),

          if (alerted && lastAlert.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
              child: Text('경고 알림 발송: $lastAlert',
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textGray)),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// 서버는 'YYYY-MM-DD HH:MM:SS' 를 준다. 표 폭이 좁아 시:분만 남긴다.
  String _shortTime(String s) {
    if (s.length >= 16) return s.substring(5, 16);
    return s;
  }
}

class _Th extends StatelessWidget {
  final String text;
  final bool center;
  const _Th(this.text, {this.center = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          text,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textGray),
        ),
      );
}

class _Td extends StatelessWidget {
  final String text;
  final bool center;
  const _Td(this.text, {this.center = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          text,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textDark),
        ),
      );
}
