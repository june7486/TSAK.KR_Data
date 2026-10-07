import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';

/// 관리자 1명(인가번호) 전용 메뉴 접근권한 설정 창 (마스터 전용).
///
/// 마스터가 관리자 아이디를 누르면 열린다. 어느 메뉴까지 허용할지 켜고 끄면
/// 서버(/api/admin/perms/set)에 인가번호별 override 로 저장되어, 그 관리자가
/// 개인 로그인으로 접속해도 지정한 범위까지만 기능이 열린다.
class AdminPermScreen extends StatefulWidget {
  const AdminPermScreen({super.key, required this.number, this.name = ''});

  /// 관리자 인가번호(아이디).
  final String number;

  /// 표시용 이름(없으면 미확인).
  final String name;

  @override
  State<AdminPermScreen> createState() => _AdminPermScreenState();
}

class _AdminPermScreenState extends State<AdminPermScreen> {
  bool _busy = true;

  /// 이 관리자에게 실제 적용될 값(override 없으면 역할 기본값).
  Map<String, bool> _effective = {};

  /// override 로 지정된(개별 조정된) 메뉴 키.
  final Set<String> _customized = {};

  /// 이 관리자에 대해 저장된 override 가 하나라도 있는지.
  bool _hasOverride = false;

  /// 메뉴 키 → 표시 이름/설명/아이콘 (역할 권한 화면과 동일 카탈로그).
  static const List<Map<String, dynamic>> _menus = [
    {'key': 'board', 'label': '게시판', 'desc': '게시글 열람·작성·댓글', 'icon': Icons.forum_outlined},
    {'key': 'events', 'label': '행사관리', 'desc': '행사 사진·동영상·참가자', 'icon': Icons.event_note},
    {'key': 'merchBuy', 'label': '수품구매', 'desc': '굿즈 주문·결제', 'icon': Icons.shopping_cart_checkout},
    {'key': 'memberSearch', 'label': '명단검색', 'desc': '이름·번호 조회(타인 개인정보 제외)', 'icon': Icons.search},
    {'key': 'memberDetail', 'label': '타인 상세열람', 'desc': '타인의 개인정보 상세 열람', 'icon': Icons.badge_outlined},
    {'key': 'merchMgmt', 'label': '수품관리', 'desc': '수품 판매관리·등록·재고·통계', 'icon': Icons.inventory_2},
    {'key': 'supplies', 'label': '비품재고 관리', 'desc': '중앙회 비품 리스트 등록·수정·삭제·정렬', 'icon': Icons.inventory},
    {'key': 'finance', 'label': '재무관리', 'desc': '참가비·지출·결산 (기본자료는 마스터 전용)', 'icon': Icons.account_balance_wallet},
    {'key': 'stats', 'label': '통계', 'desc': '명단·연맹·연회비 통계', 'icon': Icons.insights},
    {'key': 'bulk', 'label': '단체문자', 'desc': '단체 소식/문자 발송 · 일괄작업', 'icon': Icons.campaign},
    {'key': 'memberAdd', 'label': '인가자 생성', 'desc': '범스카우트 인가자 신규 등록', 'icon': Icons.person_add_alt_1},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    final r = await state.nas.fetchAdminPerms();
    final defaults = <String, bool>{};
    final rawDefaults = (r['defaults'] as Map?) ?? {};
    for (final e in rawDefaults.entries) {
      defaults['${e.key}'] = e.value == true;
    }
    // 메뉴 카탈로그 기준으로 기본값을 채운다(누락 대비).
    for (final m in _menus) {
      defaults.putIfAbsent(m['key'] as String, () => false);
    }
    final ap = (r['adminPerms'] as Map?) ?? {};
    final ov = ap[widget.number] as Map?;
    final effective = <String, bool>{...defaults};
    final customized = <String>{};
    if (ov != null) {
      for (final e in ov.entries) {
        effective['${e.key}'] = e.value == true;
        customized.add('${e.key}');
      }
    }
    if (!mounted) return;
    setState(() {
      _effective = effective;
      _customized
        ..clear()
        ..addAll(customized);
      _hasOverride = ov != null;
      _busy = false;
    });
  }

  void _toggle(String key, bool value) {
    setState(() => _effective[key] = value);
  }

  void _setAll(bool value) {
    setState(() {
      for (final m in _menus) {
        _effective[m['key'] as String] = value;
      }
    });
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    final updates = <String, bool>{
      for (final m in _menus) m['key'] as String: _effective[m['key']] == true,
    };
    final ok = await state.nas.setAdminPerms(widget.number, updates);
    if (!mounted) return;
    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('관리자 #${widget.number} 권한을 저장했습니다')),
      );
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('권한 저장에 실패했습니다 (마스터 세션 확인)')),
      );
    }
  }

  Future<void> _reset() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기본값으로 되돌리기'),
        content: Text(
          '관리자 #${widget.number} 의 개별 권한을 모두 지우고 '
          '역할 기본값(관리자 기본 권한)으로 되돌립니다.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('되돌리기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final done = await state.nas.resetAdminPerms(widget.number);
    if (!mounted) return;
    if (done) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기본 권한으로 되돌렸습니다')),
      );
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('되돌리기에 실패했습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: TsakAppBar(title: const Text('관리자 권한 설정')),
        body: const Center(child: Text('마스터만 접근할 수 있습니다')),
      );
    }
    final name = widget.name.isEmpty ? '이름 미확인' : widget.name;
    final allowed = _effective.values.where((v) => v).length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        leading: const AppBackButton(label: '뒤로'),
        leadingWidth: 84,
        title: Text('관리자 #${widget.number} 권한'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  children: [
                    _headerCard(name, allowed),
                    const SizedBox(height: 12),
                    _quickRow(),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                        child: Column(
                          children: [
                            for (final m in _menus) _menuSwitch(m),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '· 켠 메뉴만 이 관리자에게 허용됩니다. '
                      '끄면 그 관리자는 해당 메뉴 버튼이 보이지 않습니다.\n'
                      '· 「기본값으로」를 누르면 역할 기본 권한으로 돌아갑니다.',
                      style: TextStyle(fontSize: 11, color: AppColors.textGray),
                    ),
                  ],
                ),
              ),
              _bottomBar(),
            ],
          ),
          BusyOverlay(
            visible: _busy,
            title: '권한을 처리하는 중입니다',
            lines: const [
              'NAS 서버에 권한 설정을 저장하고 있습니다...',
              '화면을 갱신하는 중...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerCard(String name, int allowed) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아이디 #${widget.number}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '허용 메뉴 $allowed / ${_menus.length}'
                  '${_hasOverride ? ' · 개별 설정됨' : ' · 역할 기본값'}',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _busy ? null : () => _setAll(true),
            icon: const Icon(Icons.done_all, size: 16),
            label: const Text('전체 허용'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _busy ? null : () => _setAll(false),
            icon: const Icon(Icons.block, size: 16),
            label: const Text('전체 해제'),
          ),
        ),
      ],
    );
  }

  Widget _menuSwitch(Map<String, dynamic> m) {
    final key = m['key'] as String;
    final on = _effective[key] == true;
    final custom = _customized.contains(key);
    const color = AppColors.taegeukBlue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(
            m['icon'] as IconData,
            size: 17,
            color: on ? color : AppColors.textGray,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      m['label'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: on ? AppColors.textDark : AppColors.textGray,
                      ),
                    ),
                    if (custom) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '개별',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.purple,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  m['desc'] as String,
                  style: const TextStyle(fontSize: 10, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            activeThumbColor: Colors.white,
            activeTrackColor: color,
            onChanged: _busy ? null : (v) => _toggle(key, v),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.taegeukRed,
              ),
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.settings_backup_restore, size: 17),
              label: const Text('기본값으로'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('권한 저장'),
            ),
          ],
        ),
      ),
    );
  }
}
