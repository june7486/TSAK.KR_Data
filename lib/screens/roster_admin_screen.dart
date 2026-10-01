import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/scroll_arrows.dart';
import '../widgets/tsak_app_bar.dart';

/// 명부관리 — (관리자·마스터, 관리자 명부는 마스터 전용)
///
/// 별도 창(화면)으로 5종 명부를 탭으로 제공한다.
///   1. 범스카우트 인가자 명부 : 범인가번호 + 아타스인가번호 + 이름 + 연락처 + 소속
///   2. 멘토 대장 명부        : 범인가번호(멘토메달신청인) + 받는분의 범인가번호
///                              또는 생성년월(수정가능) + 이름 + 연락처 + 소속
///   3. 페런츠 명부           : 2와 동일 스키마
///   4. 서포터즈              : 아이디생성년월 + 이름 + 전화번호 + 소속
///   5. 관리자 명부 (마스터만) : 범인가번호 + 아타스인가번호 + 이름 + 연락처 + 소속
///                              + 관리자권한 부여일
class RosterAdminScreen extends StatefulWidget {
  const RosterAdminScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<RosterAdminScreen> createState() => _RosterAdminScreenState();
}

class _RosterAdminScreenState extends State<RosterAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> _profiles = <String, dynamic>{};
  Map<String, dynamic> _adminInfo = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profs = await state.nas.linkProfiles();
      Map<String, dynamic> admins = <String, dynamic>{};
      if (state.isMaster) {
        admins = await state.nas.merchantAdmins();
      }
      if (!mounted) return;
      setState(() {
        _profiles = profs;
        _adminInfo = admins;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ---- 소속 문자열 ----
  String _org(String league, String unit) {
    final l = league.trim();
    final u = unit.trim();
    if (l.isEmpty && u.isEmpty) return '';
    if (l.isEmpty) return u;
    if (u.isEmpty) return l;
    return '$l · $u';
  }

  // ---- 생성년월 (yyyy.MM) ----
  String _ym(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final m = RegExp(r'(\d{4})[.\-/]?(\d{2})').firstMatch(s);
    if (m != null) return '${m.group(1)}.${m.group(2)}';
    return s;
  }

  List<Member> _credentialMembers(AppState state) {
    final list = state.allMembers.where((m) => !m.isRegular).toList();
    list.sort((a, b) => a.numberInt.compareTo(b.numberInt));
    return list;
  }

  List<Member> _supporters(AppState state) {
    final list = state.allMembers.where((m) => m.isRegular).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// kind('mentor'|'parent') 프로필을 [번호, 프로필] 목록으로 정렬 반환.
  List<MapEntry<String, Map<String, dynamic>>> _linkProfiles(String kind) {
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    _profiles.forEach((k, v) {
      if (v is Map && (v['kind'] ?? 'mentor').toString() == kind) {
        out.add(MapEntry(k, v.cast<String, dynamic>()));
      }
    });
    out.sort((a, b) => '${a.value['name']}'.compareTo('${b.value['name']}'));
    return out;
  }

  // ---- 받는분 인가번호/생성년월 셀 (인라인 수정) ----
  Widget _receiverCell(Map<String, dynamic> prof) {
    final state = context.read<AppState>();
    final receiverNo = '${prof['receiverNo'] ?? ''}'.trim();
    final created = _ym('${prof['updatedAt'] ?? ''}');
    final canEdit = state.isApp || state.isMaster;
    if (!canEdit) {
      return Text(
        receiverNo.isNotEmpty ? receiverNo : created,
        style: TextStyle(
          fontSize: 12,
          fontWeight: receiverNo.isNotEmpty ? FontWeight.w800 : FontWeight.w500,
          color: receiverNo.isNotEmpty
              ? AppColors.textDark
              : AppColors.textGray,
        ),
      );
    }
    return InkWell(
      onTap: () => _editReceiver(prof),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            receiverNo.isNotEmpty ? receiverNo : created,
            style: TextStyle(
              fontSize: 12,
              fontWeight: receiverNo.isNotEmpty
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: receiverNo.isNotEmpty
                  ? AppColors.textDark
                  : AppColors.textGray,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.edit, size: 13, color: AppColors.purpleLight),
        ],
      ),
    );
  }

  Future<void> _editReceiver(Map<String, dynamic> prof) async {
    final nas = context.read<AppState>().nas;
    final ctrl = TextEditingController(text: '${prof['receiverNo'] ?? ''}');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('받는분의 범인가번호 — ${prof['name'] ?? ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '받는분의 범인가번호',
                hintText: '예: 2186 (비우면 생성년월로 표시)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '생성년월: ${_ym('${prof['updatedAt'] ?? ''}')}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (r == null) return;
    // 취소(null)와 빈값('') 구분: 빈값은 삭제(생성년월 대체).
    setState(() => _busy = true);
    try {
      final res = await nas.linkProfileSetReceiver(
        number: '${prof['number'] ?? ''}',
        receiverNo: r,
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        _snack('저장했습니다');
        await _refresh();
      } else {
        _snack('저장 실패');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMaster = state.isMaster;

    if (!(state.isApp || state.isMaster)) {
      return Scaffold(
        appBar: TsakAppBar(
          leading: const AppBackButton(label: '뒤로'),
          leadingWidth: 84,
          title: const Text('명부관리'),
        ),
        body: const Center(child: Text('관리자 권한이 필요합니다')),
      );
    }

    return Scaffold(
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: const Text('명부관리'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.72),
          labelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
          tabs: [
            const Tab(text: '범인가자'),
            const Tab(text: '멘토 대장'),
            const Tab(text: '페런츠'),
            const Tab(text: '서포터즈'),
            if (isMaster) const Tab(text: '관리자'),
          ],
        ),
      ),
      body: Stack(
        children: [
          _body(state, isMaster),
          if (_busy) const BusyOverlay(visible: true),
        ],
      ),
    );
  }

  Widget _body(AppState state, bool isMaster) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 44,
              color: AppColors.tigerGold,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _refresh, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return TabBarView(
      controller: _tab,
      children: [
        _credentialTable(state),
        _linkTable(state, 'mentor'),
        _linkTable(state, 'parent'),
        _supporterTable(state),
        if (isMaster) _adminTable(),
      ],
    );
  }

  // ---- 공통 테이블 래퍼 ----
  Widget _tableWrap(List<String> headers, List<List<Widget>> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '표시할 명부가 없습니다.',
            style: TextStyle(color: AppColors.textGray),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDEAE6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // 요약 + 복사
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFFF6F4F1),
              child: Row(
                children: [
                  Text(
                    '총 ${rows.length}명',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _copyTsv(headers, rows),
                    icon: const Icon(Icons.copy_all, size: 15),
                    label: const Text('표 복사', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ScrollArrows(
                      step: 220,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            const Color(0xFFF6F4F1),
                          ),
                          headingTextStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.purple,
                          ),
                          dataTextStyle: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textDark,
                          ),
                          horizontalMargin: 12,
                          columnSpacing: 16,
                          columns: [
                            for (final h in headers) DataColumn(label: Text(h)),
                          ],
                          rows: [
                            for (final r in rows)
                              DataRow(cells: [for (final c in r) DataCell(c)]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyTsv(List<String> headers, List<List<Widget>> rows) async {
    // 위젯에서 텍스트만 추출해 탭 구분 텍스트로 복사(엑셀 붙여넣기용).
    final buf = StringBuffer(headers.join('\t'));
    buf.writeln();
    for (final r in rows) {
      final cells = r.map((w) {
        if (w is Text) return w.data ?? '';
        if (w is Row) {
          final t = w.children.whereType<Text>().firstOrNull;
          return t?.data ?? '';
        }
        return '';
      });
      buf.writeln(cells.join('\t'));
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    _snack('명부를 복사했습니다 (엑셀에 붙여넣기)');
  }

  Widget _t(String s, {bool bold = false}) => Text(
    s,
    style: TextStyle(
      fontSize: 12,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      color: bold ? AppColors.textDark : AppColors.textDark,
    ),
  );

  // ---- 1. 범스카우트 인가자 명부 ----
  Widget _credentialTable(AppState state) {
    final list = _credentialMembers(state);
    final headers = ['#', '범인가번호', '아타스인가번호', '이름', '연락처', '소속'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      final contact = m.phone.trim().isNotEmpty ? m.phone : m.tel;
      rows.add([
        _t('${i + 1}'),
        _t(m.number, bold: true),
        _t(m.atasNo),
        _t(m.name, bold: true),
        _t(contact),
        _t(_org(m.league, m.unit)),
      ]);
    }
    return _tableWrap(headers, rows);
  }

  // ---- 2/3. 멘토 대장 · 페런츠 명부 ----
  Widget _linkTable(AppState state, String kind) {
    final list = _linkProfiles(kind);
    final headers = ['#', '범인가번호', '이름', '연락처', '아이디', '소속'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final prof = list[i].value;
      // 자동생성 아이디(수품구매시 입력한 인적사항의 전화번호 기반).
      final loginId = '${prof['loginId'] ?? ''}'.trim();
      rows.add([
        _t('${i + 1}'),
        _receiverCell(prof),
        _t('${prof['name'] ?? ''}', bold: true),
        _t('${prof['phone'] ?? ''}'),
        _t(loginId.isEmpty ? '—' : loginId),
        _t(_org('${prof['league'] ?? ''}', '${prof['unit'] ?? ''}')),
      ]);
    }
    return _tableWrap(headers, rows);
  }

  // ---- 4. 서포터즈 ----
  Widget _supporterTable(AppState state) {
    final list = _supporters(state);
    final headers = ['#', '아이디생성년월', '이름', '전화번호', '소속'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      // 아이디(계정) 생성년월 — 서버가 저장 시 부여한 createdAt(updatedAt) 기준.
      final created = _ym(
        m.updatedAt != null
            ? '${m.updatedAt!.year}.${m.updatedAt!.month.toString().padLeft(2, '0')}'
            : '',
      );
      final phone = m.phone.trim().isNotEmpty ? m.phone : m.accessPhone;
      rows.add([
        _t('${i + 1}'),
        _t(created),
        _t(m.name, bold: true),
        _t(phone),
        _t(_org(m.league, m.unit)),
      ]);
    }
    return _tableWrap(headers, rows);
  }

  // ---- 5. 관리자 명부 (마스터만) ----
  Widget _adminTable() {
    final list = (_adminInfo['admins'] as List?) ?? const [];
    final headers = ['#', '범인가번호', '이름', '연락처', '소속', '권한부여일'];
    final rows = <List<Widget>>[];
    for (var i = 0; i < list.length; i++) {
      final a = (list[i] as Map).cast<String, dynamic>();
      rows.add([
        _t('${i + 1}'),
        _t('${a['number'] ?? ''}', bold: true),
        _t('${a['name'] ?? ''}', bold: true),
        _t('${a['phone'] ?? ''}'),
        _t(_org('${a['league'] ?? ''}', '${a['unit'] ?? ''}')),
        _t('${a['grantedAt'] ?? ''}'),
      ]);
    }
    return _tableWrap(headers, rows);
  }
}
