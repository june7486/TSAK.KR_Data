import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 마스터 전용 — 자료 저장공간 관리.
///
/// 모든 자료(사진·동영상·첨부파일)를 어디에 저장할지 선택한다.
///   · 현재 NAS / 구글드라이브(아이디·패스워드·폴더URL) / 추가(추후 선택)
///   · 저장공간을 바꾸면 "기존자료를 저장 후 업로드하시겠습니까?" 를 확인하고,
///     이관 시 기존 자료는 남겨둔 채 새 공간으로 복사한다.
///   · 이관 완료 후 "기존 자료를 삭제할지"를 별도로 확인한다.
///   · 모든 항목의 데이터는 저장공간 이동 후에도 동일 상태(썽크)를 유지한다.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadStorage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isMaster) {
      return const Scaffold(body: Center(child: Text('마스터만 접근할 수 있습니다')));
    }
    final spaces = state.storageSpaces;
    final active = state.storageActive;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: TsakAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        leadingWidth: 48,
        title: const Text('자료 저장공간'),
        actions: const [AppHomeEmblem(size: 26)],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.cloud_sync, color: AppColors.purple),
                          SizedBox(width: 8),
                          Text(
                            '저장공간 선택',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '모든 자료(사진·동영상·첨부파일)를 어디에 저장할지 고릅니다. '
                        '현재 사용중: ${_labelOf(spaces, active)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final key in ['nas', 'gdrive', 'etc'])
                _spaceCard(
                  state,
                  key,
                  ((spaces[key] as Map?) ?? {}).cast<String, dynamic>(),
                ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '이관 규칙',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '· 저장공간을 바꾸면 "기존자료를 저장 후 업로드하시겠습니까?" '
                        '를 먼저 확인합니다.\n'
                        '· 이관 시 기존 저장공간의 자료는 그대로 남겨둡니다.\n'
                        '· 이관이 끝나면 "기존 자료를 삭제할지"를 따로 물어봅니다.\n'
                        '· 모든 항목의 데이터는 이동 후에도 동일 상태로 썽크를 맞춥니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textGray,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('자료를 이관하는 중입니다...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _labelOf(Map<String, dynamic> spaces, String key) {
    final sp = spaces[key];
    if (sp is Map) return '${sp['label'] ?? key}';
    return key;
  }

  Widget _spaceCard(AppState state, String key, Map<String, dynamic> sp) {
    final active = state.storageActive == key;
    final cfg = (sp['config'] as Map?)?.cast<String, dynamic>() ?? {};
    final type = '${sp['type'] ?? key}';
    final idCtrl = TextEditingController(text: '${cfg['id'] ?? ''}');
    final pwCtrl = TextEditingController(text: '${cfg['password'] ?? ''}');
    final urlCtrl = TextEditingController(text: '${cfg['folderUrl'] ?? ''}');
    final epCtrl = TextEditingController(text: '${cfg['endpoint'] ?? ''}');
    final labelCtrl = TextEditingController(text: '${sp['label'] ?? ''}');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  type == 'nas'
                      ? Icons.dns
                      : type == 'gdrive'
                          ? Icons.add_to_drive
                          : Icons.storage,
                  color: active ? AppColors.purple : AppColors.textGray,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${sp['label'] ?? key}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.scoutGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '사용중',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.scoutGreen,
                      ),
                    ),
                  ),
              ],
            ),
            if (type != 'nas') ...[
              const SizedBox(height: 10),
              if (type == 'etc')
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: '저장공간 이름',
                    hintText: '예: 회사 서버, 원드라이브 등',
                    isDense: true,
                  ),
                ),
              if (type == 'etc') const SizedBox(height: 8),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: '아이디',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '패스워드',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: '폴더 URL',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: epCtrl,
                decoration: const InputDecoration(
                  labelText: '업로드 엔드포인트 (선택 · Apps Script 웹앱 URL)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final err = await state.saveStorage({
                      'spaces': {
                        key: {
                          'label': labelCtrl.text.trim().isEmpty
                              ? '${sp['label'] ?? key}'
                              : labelCtrl.text.trim(),
                          'config': {
                            'id': idCtrl.text.trim(),
                            'password': pwCtrl.text,
                            'folderUrl': urlCtrl.text.trim(),
                            'endpoint': epCtrl.text.trim(),
                          },
                        },
                      },
                    });
                    if (!mounted) return;
                    _snack(err == null ? '저장했습니다' : '실패: $err');
                  },
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('설정 저장'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: active
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('현재 사용중'),
                    )
                  : FilledButton.icon(
                      onPressed: () => _switchTo(state, key, sp),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(
                        '이 저장공간으로 전환'
                        '${state.storageActive == 'nas' ? ' (기존자료 업로드 확인)' : ''}',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchTo(
    AppState state,
    String key,
    Map<String, dynamic> sp,
  ) async {
    final label = '${sp['label'] ?? key}';
    // 1) 이관 통계 미리보기
    final sweep = await state.migrateStorage(key, sweep: true);
    final mat = (sweep['material'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (mat['total'] as num?)?.toInt() ?? 0;
    final bytes = (mat['bytes'] as num?)?.toInt() ?? 0;
    if (!mounted) return;

    // 2) "기존자료를 저장 후 업로드하시겠습니까?" 확인
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("'$label' 로 전환"),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '기존자료를 저장 후 업로드하시겠습니까?',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '대상 자료: 총 $total건 (약 ${_fmtBytes(bytes)})\n'
              '· 재무 첨부 ${mat['financeCount'] ?? 0}건 · '
              '행사 사진/동영상 ${mat['eventCount'] ?? 0}건 · '
              '기본자료 ${mat['filesCount'] ?? 0}건',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textGray,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '· 이관 시 기존 저장공간의 자료는 그대로 남겨둡니다.\n'
              '· 이관 후 "기존 자료를 삭제할지"를 따로 물어봅니다.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('예, 업로드합니다'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 3) 이관 실행
    setState(() => _busy = true);
    final res = await state.migrateStorage(key);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res['ok'] != true) {
      _snack('전환 실패: ${res['error'] ?? ''}');
      return;
    }
    final pending = res['pending'] == true;
    final copied = (res['copied'] as num?)?.toInt() ?? 0;
    final failed = (res['failed'] as num?)?.toInt() ?? 0;

    // 4) 이관 결과 + "기존 자료를 삭제할지" 별도 확인
    final delOld = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이관 완료'),
        scrollable: true,
        content: Text(
          "'$label' 로 전환했습니다.\n"
          '성공 $copied건${failed > 0 ? ' · 실패 $failed건' : ''}'
          '${pending ? '\n\n※ 업로드 엔드포인트가 미설정이라 일부 자료는 보류되었습니다. '
              '설정 저장 후 다시 시도하세요.' : ''}\n\n'
          '기존 저장공간의 자료를 삭제할까요?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니오, 남겨둡니다'),
          ),
          if (!pending)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.taegeukRed,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('예, 기존 자료 삭제'),
            ),
        ],
      ),
    );
    if (delOld == true) {
      setState(() => _busy = true);
      final n = await state.purgeOldStorage('nas');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('기존 자료 $n건을 삭제했습니다');
    } else {
      _snack("전환 완료 — 기존 자료는 보존됩니다");
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  static String _fmtBytes(int n) {
    if (n <= 0) return '0 B';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
