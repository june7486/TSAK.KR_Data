import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';

/// 홈 메뉴 노출권한 관리 (마스터 전용).
///
/// 홈 화면 우측 상단 ⋮(오버플로) 메뉴의 각 항목을 **누구에게 노출할지**를
/// 마스터/관리자 **복수 선택**으로 정한다. 값은 서버(/api/home/menus/set)에
/// 저장되어 모든 기기에 즉시 반영된다.
///
/// 노출 순서는 항상 **마스터 항목이 상단, 관리자 항목이 하단**이다.
///  · 마스터만 켬  → 마스터 구역에만 표시
///  · 관리자만 켬  → 관리자 구역에 표시(마스터에게도 관리자 구역으로 보임)
///  · 둘 다 켬     → 마스터 구역에 표시(마스터·관리자 모두 열람)
///  · 둘 다 끔     → 숨김
class HomeMenuPermScreen extends StatefulWidget {
  const HomeMenuPermScreen({super.key});

  @override
  State<HomeMenuPermScreen> createState() => _HomeMenuPermScreenState();
}

class _HomeMenuPermScreenState extends State<HomeMenuPermScreen> {
  bool _busy = false;

  /// 메뉴 키 → 아이콘 (서버는 문자열 아이콘 이름만 내려준다).
  static const Map<String, IconData> _icons = {
    'admin_panel_settings': Icons.admin_panel_settings,
    'workspace_premium': Icons.workspace_premium,
    'folder_special': Icons.folder_special,
    'settings': Icons.settings,
    'cloud_download': Icons.cloud_download,
    'app_registration': Icons.app_registration,
    'account_balance_wallet': Icons.account_balance_wallet,
    'auto_awesome': Icons.auto_awesome,
    'checklist': Icons.checklist,
  };

  /// 노출 순서(서버 dict 순서와 동일하게 고정) — 마스터 구역(상단) / 관리자 구역(하단).
  static const List<String> _masterGroup = [
    'admin',
    'master_console',
    'source',
    'settings',
    'refresh',
  ];
  static const List<String> _adminGroup = [
    'member_request',
    'finance',
    'import',
    'select',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadHomeMenus();
    });
  }

  Future<void> _set(String key, {bool? master, bool? admin}) async {
    final state = context.read<AppState>();
    final upd = <String, bool>{};
    if (master != null) upd['master'] = master;
    if (admin != null) upd['admin'] = admin;
    setState(() => _busy = true);
    final ok = await state.setHomeMenus({key: upd});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('노출권한 저장에 실패했습니다')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: TsakAppBar(title: const Text('홈 메뉴 노출권한')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final menus = state.homeMenus;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        title: const Text('홈 메뉴 노출권한'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => state.loadHomeMenus(),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
            children: [
              _intro(),
              const SizedBox(height: 12),
              _groupHeader(
                '마스터 구역 (상단)',
                AppColors.masterInk,
                '홈 ⋮ 메뉴 상단에 배치됩니다. 기본은 마스터 전용이며, '
                    '"관리자에게 노출"을 켜면 관리자에게도 표시됩니다(위치는 상단 고정).',
              ),
              for (final key in _masterGroup)
                if (menus[key] != null)
                  _menuCard(state, key, menus[key]!, masterGroup: true),
              const SizedBox(height: 6),
              _groupHeader(
                '관리자 구역 (하단)',
                AppColors.adminInk,
                '홈 ⋮ 메뉴 하단에 배치됩니다. 관리자에게 기본 노출되며, '
                    '마스터 노출을 끄면 마스터에게는 보이지 않습니다(위치는 하단 고정).',
              ),
              for (final key in _adminGroup)
                if (menus[key] != null)
                  _menuCard(state, key, menus[key]!, masterGroup: false),
              const SizedBox(height: 8),
              _footer(),
            ],
          ),
          BusyOverlay(
            visible: _busy,
            title: '노출권한을 반영하는 중입니다',
            lines: const [
              'NAS 서버에 설정을 저장하고 있습니다...',
              '홈 메뉴를 갱신하는 중...',
              '잠시만 기다려 주세요...',
            ],
          ),
        ],
      ),
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.tune, color: Colors.white, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '홈 ⋮ 메뉴 노출권한',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '각 메뉴를 누구에게 보여줄지 마스터·관리자를 복수 선택할 수 있습니다.\n'
                  '노출 위치(구역)는 메뉴마다 고정입니다 — 마스터 항목은 상단, 관리자 항목은 하단.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.adminTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.adminInk.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.adminInk),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '체크는 "누구에게 노출"을 뜻합니다. 둘 다 켜면 마스터·관리자 모두 열람합니다.\n'
              '마스터 구역 항목은 관리자에게 기본 숨김이며, "관리자에게 노출"을 켜면 '
              '관리자에게도 보입니다(위치는 그대로 상단).\n'
              '둘 다 끄면 어떤 역할에도 보이지 않습니다.',
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: AppColors.adminInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(String title, Color color, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              desc,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: AppColors.textGray,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuCard(
    AppState state,
    String key,
    Map<String, dynamic> m, {
    required bool masterGroup,
  }) {
    final label = '${m['label'] ?? ''}';
    final icon = _icons['${m['icon']}'] ?? Icons.circle_outlined;
    final onM = m['master'] == true;
    final onA = m['admin'] == true;

    // 노출 대상 미리보기 문구.
    final placement = () {
      if (!onM && !onA) return '숨김 · 어디에도 표시되지 않음';
      if (onM && onA) return '마스터 · 관리자 모두 열람';
      if (onM) {
        return masterGroup
            ? '마스터 전용 (관리자에게 숨김)'
            : '마스터만 열람 (관리자에게 숨김)';
      }
      return '관리자 전용 (마스터에게 숨김)';
    }();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: (onM || onA) ? AppColors.textDark : AppColors.textGray,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: (onM || onA)
                          ? AppColors.textDark
                          : AppColors.textGray,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              placement,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textGray),
            ),
            const Divider(height: 14),
            Row(
              children: [
                Expanded(
                  child: _roleCheck(
                    label: '마스터에게 노출',
                    color: AppColors.masterInk,
                    tint: AppColors.masterTint,
                    value: onM,
                    onChanged: (v) => _set(key, master: v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _roleCheck(
                    label: '관리자에게 노출',
                    color: AppColors.adminInk,
                    tint: AppColors.adminTint,
                    value: onA,
                    onChanged: (v) => _set(key, admin: v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleCheck({
    required String label,
    required Color color,
    required Color tint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: value ? tint : const Color(0xFFF1F0F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? color.withValues(alpha: 0.45) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: value ? color : AppColors.textGray,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: value ? color : AppColors.textGray,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
