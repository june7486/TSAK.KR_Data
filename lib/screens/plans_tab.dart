import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/doc_pdf.dart';
import '../services/export_save.dart';
import '../services/file_save.dart';
import '../services/nas_api.dart';
import '../services/output_formats.dart';
import '../services/pdf_to_jpg.dart';
import '../services/print_doc.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/busy_overlay.dart';
import 'merch_detail_screen.dart';

/// 기획실 — 신규 수품 아이템 기획 관리 화면(관리자·마스터 전용, 탭 내장형).
///
/// 각 아이템: 사진 · 설명 · 메모 · 가격 · 동영상 · 기획자 · 기획안 제출일 ·
///           현재 진행상황 · (수요조사 시) 최소 제작 착수 수량
/// - "수요조사 진행" 체크 → 개인/공개 수품구매 하단에 노출되어 **누구나 사전신청**.
/// - 신청자 명단·순번·정보를 여기서 모두 확인(개인 페이지와 동일 숫자 연동).
class PlansTab extends StatefulWidget {
  const PlansTab({super.key});

  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;

  final _picker = ImagePicker();

  NasApi get _nas => context.read<NasApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _nas.merchAdmin();
      if (!mounted) return;
      setState(() {
        _plans = _list(r['plans']);
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

  String _whoName() {
    final s = context.read<AppState>();
    if (s.isMaster) return '마스터';
    if (s.isApp) return '관리자';
    if (s.who.isNotEmpty) {
      final m = s.repo.byNumber(s.who);
      if (m != null && m.name.isNotEmpty) return m.name;
      return s.who;
    }
    return '';
  }

  String _today() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${p(d.month)}.${p(d.day)}';
  }

  Future<void> _pickPhoto(Map<String, dynamic> draft) async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final b64 = base64Encode(bytes);
      final r = await _nas.merchImageUpload(
        'plan_${DateTime.now().millisecondsSinceEpoch}.jpg',
        b64,
      );
      if (r['ok'] == true) {
        draft['photo'] = '${r['file'] ?? ''}';
        if (mounted) setState(() {});
      } else {
        _snack('사진 업로드 실패');
      }
    } catch (e) {
      _snack('사진 선택 실패: $e');
    }
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final desc = TextEditingController(text: '${existing?['desc'] ?? ''}');
    final memo = TextEditingController(text: '${existing?['memo'] ?? ''}');
    final price = TextEditingController(text: '${existing?['price'] ?? ''}');
    final video = TextEditingController(text: '${existing?['video'] ?? ''}');
    final maker = TextEditingController(text: '${existing?['maker'] ?? ''}');
    final submitted = TextEditingController(
      text: '${existing?['submittedAt'] ?? ''}'.isNotEmpty
          ? '${existing?['submittedAt']}'
          : _today(),
    );
    final progress = TextEditingController(
      text: '${existing?['progress'] ?? ''}',
    );
    final minQty = TextEditingController(text: '${existing?['minQty'] ?? ''}');
    final draft = <String, dynamic>{'photo': '${existing?['photo'] ?? ''}'};
    bool surveyOpen = existing?['surveyOpen'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? '기획 아이템 추가' : '기획 아이템 수정'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 사진
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 64,
                          height: 64,
                          color: AppColors.bg,
                          child: '${draft['photo']}'.isEmpty
                              ? const Icon(
                                  Icons.image_outlined,
                                  color: AppColors.textGray,
                                )
                              : Image.network(
                                  _nas.merchImageUrl('${draft['photo']}'),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textGray,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickPhoto(draft).then((_) => setD(() {})),
                        icon: const Icon(Icons.photo_camera_outlined, size: 16),
                        label: const Text('사진 선택'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: '아이템명 *',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: desc,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: '설명',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: memo,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: '메모',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '가격(원)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: minQty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '최소 제작 착수 수량',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: video,
                    decoration: const InputDecoration(
                      labelText: '동영상 (URL)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: maker,
                          decoration: const InputDecoration(
                            labelText: '기획자',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: submitted,
                          decoration: const InputDecoration(
                            labelText: '기획안 제출일',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: progress,
                    decoration: const InputDecoration(
                      labelText: '현재 진행상황',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('수요조사 진행'),
                    subtitle: const Text('수품구매 하단에 노출되어 누구나 사전신청 가능'),
                    value: surveyOpen,
                    onChanged: (v) => setD(() => surveyOpen = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) {
      _snack('아이템명을 입력하세요');
      return;
    }
    final r = await _nas.merchSavePlan(
      id: '${existing?['id'] ?? ''}',
      name: name.text.trim(),
      photo: '${draft['photo'] ?? ''}',
      video: video.text.trim(),
      desc: desc.text.trim(),
      memo: memo.text.trim(),
      price: int.tryParse(price.text.trim()) ?? 0,
      maker: maker.text.trim(),
      submittedAt: submitted.text.trim(),
      progress: progress.text.trim(),
      minQty: int.tryParse(minQty.text.trim()) ?? 0,
      surveyOpen: surveyOpen,
      whoName: _whoName(),
    );
    if (!mounted) return;
    _snack(r['ok'] == true ? '저장했습니다' : '저장 실패');
    if (r['ok'] == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기획 아이템 삭제'),
        content: Text('"${p['name']}" 을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await _nas.merchDeletePlan('${p['id']}');
    if (!mounted) return;
    _snack(ok ? '삭제했습니다' : '삭제 실패');
    if (ok) _load();
  }

  Future<void> _toggleSurvey(Map<String, dynamic> p, bool on) async {
    setState(() => p['surveyOpen'] = on);
    final r = await _nas.merchSavePlan(
      id: '${p['id']}',
      name: '${p['name']}',
      surveyOpen: on,
      whoName: _whoName(),
    );
    if (!mounted) return;
    if (r['ok'] != true) {
      setState(() => p['surveyOpen'] = !on);
      _snack('수요조사 상태 변경 실패');
    }
  }

  Future<void> _onReorder(int oldI, int newI) async {
    if (newI > oldI) newI -= 1;
    setState(() {
      final moved = _plans.removeAt(oldI);
      _plans.insert(newI, moved);
    });
    final ids = _plans.map((e) => '${e['id']}').toList();
    final ok = await _nas.merchPlansOrder(ids);
    if (!ok && mounted) _snack('순서 저장 실패');
  }

  Future<void> _viewApplicants(Map<String, dynamic> p) async {
    final r = await _nas.merchSurveyApplicants('${p['id']}');
    if (!mounted) return;
    if (r['ok'] != true) {
      _snack('신청자 조회 실패');
      return;
    }
    final survey = (r['survey'] as Map?)?.cast<String, dynamic>() ?? {};
    final apps = ((survey['applicants'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final minimum = (survey['minimum'] as num?)?.toInt() ?? 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('수요조사 신청자 (${apps.length}명)'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '최소 제작 ${minimum > 0 ? '$minimum명' : '미정'} 대비 '
                '${apps.length}명 신청',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.purpleDark,
                ),
              ),
              const SizedBox(height: 8),
              if (apps.isEmpty)
                const Text(
                  '아직 신청자가 없습니다',
                  style: TextStyle(color: AppColors.textGray),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: apps.length,
                    itemBuilder: (_, i) {
                      final a = apps[i];
                      final num = '${a['number'] ?? ''}';
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.purple.withValues(
                            alpha: 0.12,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          '${a['name'] ?? ''}'
                          '${num.isNotEmpty ? '  (#$num)' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${a['phone'] ?? ''}'
                          '${'${a['email'] ?? ''}'.isNotEmpty ? ' · ${a['email']}' : ''}'
                          '  ·  ${a['at'] ?? ''}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.taegeukRed,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  size: 18,
                  color: AppColors.purple,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '기획실',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                if (_plans.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '기획안 목록 출력 (PDF·JPG·엑셀·PPT·워드)',
                    onPressed: _showPlansOutputDialog,
                    icon: const Icon(Icons.print_outlined, size: 20),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '새로고침',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              '신규 수품 기획 · 수요조사 진행 시 수품구매 하단에 노출되어 누구나 사전신청',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 10),
            if (_plans.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  '등록된 기획 아이템이 없습니다. 아래 + 버튼으로 추가하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textGray),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _plans.length,
                onReorder: _onReorder,
                itemBuilder: (ctx, i) {
                  final p = _plans[i];
                  return Container(
                    key: ValueKey('pl-${p['id']}'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Container(
                                width: 38,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.purple.withValues(
                                    alpha: 0.07,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.purple.withValues(
                                      alpha: 0.22,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.drag_indicator,
                                      size: 18,
                                      color: AppColors.purple,
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      '순서변경',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.purple.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(child: _planCard(p)),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'planAdd',
            onPressed: () => _edit(),
            backgroundColor: AppColors.purple,
            icon: const Icon(Icons.add),
            label: const Text('기획 아이템 추가'),
          ),
        ),
        BusyOverlay(
          visible: _loading,
          title: '기획안을 불러오는 중입니다',
          lines: const [
            '기획실 자료를 확인하고 있습니다...',
            '수요조사 현황을 집계하는 중...',
            '잠시만 기다려 주세요...',
          ],
        ),
      ],
    );
  }

  Widget _planCard(Map<String, dynamic> p) {
    final photo = '${p['photo'] ?? ''}';
    final photoUrl = photo.isEmpty ? '' : _nas.merchImageUrl(photo);
    final apps = (p['applicants'] as List?) ?? [];
    final count = apps.length;
    final minQty = (p['minQty'] as num?)?.toInt() ?? 0;
    final surveyOpen = p['surveyOpen'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (surveyOpen ? AppColors.scoutGreen : AppColors.purple)
              .withValues(alpha: surveyOpen ? 0.5 : 0.15),
          width: surveyOpen ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openPlanDetail(p),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 54,
                    height: 54,
                    color: AppColors.bg,
                    child: photoUrl.isEmpty
                        ? const Icon(
                            Icons.image_outlined,
                            color: AppColors.textGray,
                          )
                        : Image.network(
                            photoUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textGray,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${p['name'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (surveyOpen) _chip('수요조사 진행중', AppColors.scoutGreen),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if ('${p['desc'] ?? ''}'.isNotEmpty)
                      Text(
                        '${p['desc']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        if (((p['price'] as num?)?.toInt() ?? 0) > 0)
                          _kv('가격', _won((p['price'] as num?)?.toInt() ?? 0)),
                        if ('${p['maker'] ?? ''}'.isNotEmpty)
                          _kv('기획자', '${p['maker']}'),
                        if ('${p['submittedAt'] ?? ''}'.isNotEmpty)
                          _kv('기획안', '${p['submittedAt']}'),
                        if ('${p['progress'] ?? ''}'.isNotEmpty)
                          _kv('진행상황', '${p['progress']}'),
                        if (minQty > 0) _kv('최소수량', '$minQty'),
                        if ('${p['video'] ?? ''}'.isNotEmpty) _kv('동영상', '있음'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 수요조사 현황 + 신청자
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.groups_outlined,
                  size: 16,
                  color: AppColors.purple,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '신청 $count명'
                    '${minQty > 0 ? ' / 최소 $minQty명' : ''}'
                    '${minQty > 0 && count >= minQty ? '  ✓ 제작가능' : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _viewApplicants(p),
                  icon: const Icon(Icons.list_alt, size: 16),
                  label: const Text('신청자 명단'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 수요조사 진행 체크
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('수요조사 진행', style: TextStyle(fontSize: 13)),
                  value: surveyOpen,
                  onChanged: (v) => _toggleSurvey(p, v == true),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _edit(existing: p);
                  if (v == 'del') _delete(p);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('수정')),
                  PopupMenuItem(value: 'del', child: Text('삭제')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 기획안 이미지 클릭 → 확대 이미지 + 상세 설명 화면(돌아가기 포함).
  void _openPlanDetail(Map<String, dynamic> p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchDetailScreen(item: p, isSurvey: true),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c),
    ),
  );

  Widget _kv(String k, String v) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$k ',
        style: const TextStyle(fontSize: 11, color: AppColors.textGray),
      ),
      Text(
        v,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    ],
  );

  String _won(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf원';
  }

  String _plansDocHtml() {
    final rows = <List<DocCell>>[];
    for (var i = 0; i < _plans.length; i++) {
      final p = _plans[i];
      final apps = (p['applicants'] as List?) ?? [];
      final minQty = (p['minQty'] as num?)?.toInt() ?? 0;
      rows.add([
        DocCell('${i + 1}', align: 'center'),
        DocCell(
          '${p['name'] ?? ''}',
          accent: kMujiAccents[i % kMujiAccents.length],
          bold: true,
          sub: '${p['desc'] ?? ''}',
        ),
        DocCell('${p['maker'] ?? ''}'),
        DocCell(
          '${p['price'] ?? 0}'.isNotEmpty
              ? _won((p['price'] as num?)?.toInt() ?? 0)
              : '-',
          align: 'right',
        ),
        DocCell('${p['submittedAt'] ?? ''}', align: 'center'),
        DocCell('${p['progress'] ?? ''}'),
        DocCell(
          '${apps.length}${minQty > 0 ? ' / $minQty' : ''}명',
          align: 'center',
          bold: minQty > 0 && apps.length >= minQty,
        ),
      ]);
    }
    final html = buildMujiDoc(
      meta: _plansMeta(),
      columns: _plansColumns,
      rows: rows,
    );
    return html;
  }

  static const List<String> _plansColumns = [
    '번호',
    '아이템',
    '기획자',
    '가격',
    '기획안 제출일',
    '진행상황',
    '신청/최소',
  ];

  DocMeta _plansMeta() => DocMeta(
    title: '수품 기획안 목록 (기획실)',
    subtitle: '한국범스카우트중앙회 · 신규 수품 기획',
    description: '신규 수품 기획 아이템과 수요조사 신청 현황입니다.',
    author: _whoName(),
    extra: {'기획 아이템': '${_plans.length}건'},
  );

  List<List<DocCell>> _plansRows() {
    final rows = <List<DocCell>>[];
    for (var i = 0; i < _plans.length; i++) {
      final p = _plans[i];
      final apps = (p['applicants'] as List?) ?? [];
      final minQty = (p['minQty'] as num?)?.toInt() ?? 0;
      rows.add([
        DocCell('${i + 1}', align: 'center'),
        DocCell(
          '${p['name'] ?? ''}',
          accent: kMujiAccents[i % kMujiAccents.length],
          bold: true,
          sub: '${p['desc'] ?? ''}',
        ),
        DocCell('${p['maker'] ?? ''}'),
        DocCell(
          '${p['price'] ?? 0}'.isNotEmpty
              ? _won((p['price'] as num?)?.toInt() ?? 0)
              : '-',
          align: 'right',
        ),
        DocCell('${p['submittedAt'] ?? ''}', align: 'center'),
        DocCell('${p['progress'] ?? ''}'),
        DocCell(
          '${apps.length}${minQty > 0 ? ' / $minQty' : ''}명',
          align: 'center',
          bold: minQty > 0 && apps.length >= minQty,
        ),
      ]);
    }
    return rows;
  }

  /// 기획안 목록 출력 — 규칙(#14): PDF → JPG → 엑셀 → PPT → 워드.
  Future<void> _printPlans({
    TsakOutputFormat format = TsakOutputFormat.pdf,
  }) async {
    if (_plans.isEmpty) {
      _snack('출력할 기획안이 없습니다');
      return;
    }
    if (isWebRuntime) {
      switch (format) {
        case TsakOutputFormat.pdf:
          // 규칙: 실제 PDF 파일로 저장.
          try {
            final bytes = await DocPdf.build(
              meta: _plansMeta(),
              columns: _plansColumns,
              rows: _plansRows(),
              footerLeft: '한국범스카우트중앙회 수품',
            );
            await _saveBytes(bytes, '수품_기획안목록.pdf');
          } catch (e) {
            _snack('PDF 생성 실패: $e');
          }
          return;
        case TsakOutputFormat.jpg:
          // 규칙: 실제 .jpg 파일로 저장(인쇄창 불필요).
          try {
            final bytes = await DocPdf.build(
              meta: _plansMeta(),
              columns: _plansColumns,
              rows: _plansRows(),
              footerLeft: '한국범스카우트중앙회 수품',
            );
            final jpg = await pdfToJpg(bytes);
            await _saveBytes(jpg, '수품_기획안목록.jpg', mime: 'image/jpeg');
          } catch (e) {
            _snack('JPG 생성 실패: $e');
          }
          return;
        case TsakOutputFormat.excel:
          await Clipboard.setData(ClipboardData(text: _plansCsvText()));
          _snack('엑셀용 데이터를 복사했습니다 (붙여넣기)');
          return;
        case TsakOutputFormat.ppt:
        case TsakOutputFormat.word:
        case TsakOutputFormat.txt:
          await Clipboard.setData(ClipboardData(text: _plansPlainText(format)));
          _snack('${format.label}용 텍스트를 복사했습니다 (붙여넣기)');
          return;
      }
    } else {
      await Clipboard.setData(ClipboardData(text: _plansPlainText(format)));
      _snack('기획안 목록을 복사했습니다');
    }
  }

  /// 바이트를 실제 파일로 저장(웹) / 클립보드 폴백.
  Future<void> _saveBytes(
    Uint8List bytes,
    String filename, {
    String? mime,
  }) async {
    try {
      final ok = await saveBytesAs(
        bytes,
        filename,
        mime ?? mimeForFilename(filename),
      );
      _snack(ok ? '$filename 저장을 시작했습니다' : '저장하지 못했습니다');
    } catch (e) {
      _snack('저장 실패: $e');
    }
  }

  /// 기획안 목록을 **OS 공유 시트**(모든 기기)로 공유한다 — PDF 파일로 바로 전송.
  Future<void> _sharePlans() async {
    if (_plans.isEmpty) {
      _snack('공유할 기획안이 없습니다');
      return;
    }
    try {
      final bytes = await DocPdf.build(
        meta: _plansMeta(),
        columns: _plansColumns,
        rows: _plansRows(),
        footerLeft: '한국범스카우트중앙회 수품',
      );
      final res = await shareFileNamed(
        bytes: bytes,
        filename: '수품_기획안목록.pdf',
        mime: 'application/pdf',
        subject: '수품 기획안 목록',
        text: '수품 기획안 목록 · ${_plans.length}건',
      );
      _snack(tsakShareMessage(res, what: '기획안 목록 PDF'));
    } catch (e) {
      _snack('공유 실패: $e');
    }
  }

  /// 기획안 출력 형식 선택 다이얼로그 (#14 규칙).
  Future<void> _showPlansOutputDialog() async {
    if (_plans.isEmpty) {
      _snack('출력할 기획안이 없습니다');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기획안 목록 출력 형식'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '규칙 순서: PDF → JPG → 엑셀 → PPT → 워드',
              style: TextStyle(fontSize: 11.5, color: AppColors.textGray),
            ),
            const SizedBox(height: 12),
            TsakOutputBar(
              onFormat: (f) {
                Navigator.pop(ctx);
                _printPlans(format: f);
              },
              onShare: () {
                Navigator.pop(ctx);
                _sharePlans();
              },
              onShareImage: () {
                Navigator.pop(ctx);
                _printPlans(format: TsakOutputFormat.jpg);
              },
              onShareLink: () {
                Navigator.pop(ctx);
                showLinkShareDialog(context, '${_nas.baseUrl}/#/merch-admin');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// 기획안 목록 → CSV(엑셀).
  String _plansCsvText() {
    final buf = StringBuffer();
    buf.writeln('번호,아이템,기획자,가격,제출일,진행상황,신청,최소');
    for (var i = 0; i < _plans.length; i++) {
      final p = _plans[i];
      final apps = (p['applicants'] as List?) ?? [];
      final minQty = (p['minQty'] as num?)?.toInt() ?? 0;
      buf.writeln(
        '${i + 1},${p['name'] ?? ''},${p['maker'] ?? ''},'
        '${(p['price'] as num?)?.toInt() ?? 0},${p['submittedAt'] ?? ''},'
        '${p['progress'] ?? ''},${apps.length},$minQty',
      );
    }
    return buf.toString();
  }

  /// 기획안 목록 → PPT/워드 붙여넣기용 텍스트.
  String _plansPlainText(TsakOutputFormat format) {
    final buf = StringBuffer();
    buf.writeln(
      format == TsakOutputFormat.ppt ? '수품 기획안 목록 (슬라이드용)' : '수품 기획안 목록 (문서용)',
    );
    buf.writeln('한국범스카우트중앙회 · 기획실');
    buf.writeln();
    for (var i = 0; i < _plans.length; i++) {
      final p = _plans[i];
      final apps = (p['applicants'] as List?) ?? [];
      final minQty = (p['minQty'] as num?)?.toInt() ?? 0;
      buf.writeln(
        '${i + 1}. ${p['name'] ?? ''} / ${p['maker'] ?? ''} / '
        '${_won((p['price'] as num?)?.toInt() ?? 0)} / '
        '신청 ${apps.length}명${minQty > 0 ? ' (최소 $minQty)' : ''} / '
        '${p['progress'] ?? ''}',
      );
    }
    buf.writeln();
    buf.writeln('총 ${_plans.length}건');
    return buf.toString();
  }
}
