import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/tsak_app_bar.dart';

/// 메뉴 접근권한 관리 (마스터 전용).
///
/// 역할별(마스터·관리자·범스카우트 인가자·서포터즈·비인가자)로 어떤 메뉴에
/// 접근할 수 있는지를 마스터가 직접 켜고 끈다. 값은 서버(/api/perms/set)에
/// 저장되어 모든 기기에 즉시 반영된다.
class RolePermissionsScreen extends StatefulWidget {
  const RolePermissionsScreen({super.key});

  @override
  State<RolePermissionsScreen> createState() => _RolePermissionsScreenState();
}

class _RolePermissionsScreenState extends State<RolePermissionsScreen> {
  bool _busy = false;

  /// 메뉴 키 → 표시 이름/설명/아이콘
  static const List<Map<String, dynamic>> _menus = [
    {'key': 'board', 'label': '게시판', 'desc': '게시글 열람·작성·댓글',
     'icon': Icons.forum_outlined},
    {'key': 'events', 'label': '행사관리', 'desc': '행사 사진·동영상·참가자',
     'icon': Icons.event_note},
    {'key': 'merchBuy', 'label': '수품구매', 'desc': '굿즈 주문·결제',
     'icon': Icons.shopping_cart_checkout},
    {'key': 'memberSearch', 'label': '명단검색', 'desc': '이름·번호 조회(타인 개인정보 제외)',
     'icon': Icons.search},
    {'key': 'memberDetail', 'label': '타인 상세열람', 'desc': '타인의 개인정보 상세 열람',
     'icon': Icons.badge_outlined},
    {'key': 'merchMgmt', 'label': '수품관리', 'desc': '수품 판매관리·등록·재고·통계',
     'icon': Icons.inventory_2},
    {'key': 'finance', 'label': '재무관리', 'desc': '참가비·지출·결산·기본자료',
     'icon': Icons.account_balance_wallet},
    {'key': 'stats', 'label': '통계', 'desc': '명단·연맹·연회비 통계',
     'icon': Icons.insights},
    {'key': 'bulk', 'label': '단체문자', 'desc': '단체 소식/문자 발송 · 일괄작업',
     'icon': Icons.campaign},
    {'key': 'memberAdd', 'label': '인가자 생성', 'desc': '범스카우트 인가자 신규 등록',
     'icon': Icons.person_add_alt_1},
  ];

  /// 역할 키 → 표시 이름/설명/색
  static const List<Map<String, dynamic>> _roles = [
    {'key': 'master', 'label': '마스터', 'desc': '모든 권한(변경 불가)',
     'color': AppColors.taegeukRed},
    {'key': 'app', 'label': '관리자', 'desc': '마스터가 지정한 관리자',
     'color': AppColors.taegeukBlue},
    {'key': 'personal', 'label': '범스카우트 인가자',
     'desc': '인가번호로 로그인 · 수품구매·행사·게시판 중심',
     'color': AppColors.purple},
    {'key': 'supporter', 'label': '서포터즈', 'desc': '일반 아이디 · 개인정보 열람 불가',
     'color': AppColors.scoutGreen},
    {'key': 'guest', 'label': '비인가자', 'desc': '전화번호 뒷자리 로그인 · 최소 권한',
     'color': AppColors.textGray},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadRolePermissions();
    });
  }

  Future<void> _toggle(String role, String key, bool value) async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    final ok = await state.setRolePermission(role, {key: value});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('권한 저장에 실패했습니다')),
      );
    }
  }

  bool _isOn(Map<String, Map<String, bool>> perms, String role, String key) {
    final t = perms[role];
    if (t == null) return false;
    return t[key] == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return Scaffold(
        appBar: TsakAppBar(title: const Text('메뉴 접근권한 관리')),
        body: const Center(child: Text('마스터 권한이 필요합니다')),
      );
    }
    final perms = state.perms;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        title: const Text('메뉴 접근권한 관리'),
        actions: [
          const AppHomeEmblem(size: 22),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => state.loadRolePermissions(),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
            children: [
              _introCard(),
              const SizedBox(height: 12),
              for (final r in _roles) _roleCard(state, perms, r),
            ],
          ),
          BusyOverlay(
            visible: _busy,
            title: '접근권한을 반영하는 중입니다',
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

  Widget _introCard() {
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
                Text('역할별 메뉴 접근권한',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text(
                  '스위치를 켜고 끄면 서버에 즉시 저장되어 모든 기기에 반영됩니다.\n'
                  '범스카우트 인가자는 기본적으로 수품구매·행사관리·게시판만 허용됩니다.',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleCard(
      AppState state, Map<String, Map<String, bool>> perms, Map<String, dynamic> r) {
    final role = r['key'] as String;
    final color = r['color'] as Color;
    final isMaster = role == 'master';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '${r['label']}',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w900,
                      color: AppColors.textDark),
                ),
                const SizedBox(width: 6),
                if (isMaster)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.taegeukRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('고정',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.taegeukRed)),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2, bottom: 4),
              child: Text('${r['desc']}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray)),
            ),
            const Divider(height: 12),
            for (final m in _menus)
              _menuSwitch(
                state: state,
                perms: perms,
                role: role,
                key: m['key'] as String,
                label: m['label'] as String,
                desc: m['desc'] as String,
                icon: m['icon'] as IconData,
                locked: isMaster,
                color: color,
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuSwitch({
    required AppState state,
    required Map<String, Map<String, bool>> perms,
    required String role,
    required String key,
    required String label,
    required String desc,
    required IconData icon,
    required bool locked,
    required Color color,
  }) {
    final on = _isOn(perms, role, key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(icon, size: 17, color: on ? color : AppColors.textGray),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: on ? AppColors.textDark : AppColors.textGray)),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textGray)),
              ],
            ),
          ),
          Switch(
            value: on,
            activeThumbColor: Colors.white,
            activeTrackColor: color,
            onChanged: locked ? null : (v) => _toggle(role, key, v),
          ),
        ],
      ),
    );
  }
}
