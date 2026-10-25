import 'dart:async';

import 'package:flutter/material.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// '범스카우트 인가정보 연동' 선택창 (요구).
///
/// 멘토·페런츠 인적사항을 **수동 입력**할 때, 이미 등록된 범스카우트 인가자의
/// 정보(인가번호·이름·소속연맹·소속단위대·전화번호·스카우트번호)를 검색해
/// 불러와 자동으로 채운다. (선택 사항 — 직접 입력도 가능)
///
/// 사용 위치:
///  · 개인정보 수정/상세의 멘토·페런츠 입력창(LinkCodeField)
///  · 수품구매(각인 메달) 개인정보 입력창(MerchCheckoutScreen)
///
/// 반환: 선택한 회원 정보 Map {number,name,league,unit,phone,scoutNo,corps}
///       또는 취소 시 null.
Future<Map<String, dynamic>?> showLinkMemberPicker(
  BuildContext context, {
  required NasApi nas,
  String kind = 'mentor',
  String hint = '',
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _LinkMemberPickerDialog(nas: nas, kind: kind, hint: hint),
  );
}

class _LinkMemberPickerDialog extends StatefulWidget {
  const _LinkMemberPickerDialog({
    required this.nas,
    required this.kind,
    required this.hint,
  });

  final NasApi nas;
  final String kind; // 'mentor' | 'parent'
  final String hint;

  @override
  State<_LinkMemberPickerDialog> createState() =>
      _LinkMemberPickerDialogState();
}

class _LinkMemberPickerDialogState extends State<_LinkMemberPickerDialog> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  Color get _accent =>
      widget.kind == 'parent' ? AppColors.taegeukBlue : AppColors.purple;

  String get _kindLabel => widget.kind == 'parent' ? '페런츠(범을 배출한 부모님)' : '멘토';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.nas.linkSearchMembers(q.trim(), limit: 30);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '검색에 실패했습니다: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return AlertDialog(
      // (요구) 키보드가 올라오면 창이 줄어들어 목록·입력이 잘리던 문제 →
      //  창을 키보드만큼 올리고, 내용을 스크롤 가능하게 한다.
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      title: Row(
        children: [
          Icon(Icons.link, size: 20, color: _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '범스카우트 인가정보 연동',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      content: SizedBox(
        width: 460,
        height: h * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '등록된 범스카우트 인가자(인가번호·이름·전화)를 검색해 '
              '$_kindLabel 인적사항을 자동으로 채웁니다. (선택 사항)'
              '${widget.hint.isNotEmpty ? '\n${widget.hint}' : ''}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textGray,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _q,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: '인가번호 / 이름 / 전화번호',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => _search(_q.text),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _results()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소 (직접 입력)'),
        ),
      ],
    );
  }

  Widget _results() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.taegeukRed),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          '검색 결과가 없습니다.\n직접 입력해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textGray, fontSize: 12.5),
        ),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = _items[i];
        final num = '${m['number'] ?? ''}';
        final name = '${m['name'] ?? ''}';
        final league = '${m['league'] ?? ''}';
        final unit = '${m['unit'] ?? ''}';
        final phone = '${m['phone'] ?? ''}';
        final scout = '${m['scoutNo'] ?? ''}';
        final org = [
          league,
          unit,
        ].where((e) => e.trim().isNotEmpty).join(' · ');
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: _accent.withValues(alpha: 0.12),
            child: Text(
              num.isNotEmpty ? num : '?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
          ),
          title: Text(
            name.isNotEmpty ? '$name  범#$num' : '범#$num',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Text(
            [
              if (org.isNotEmpty) org,
              if (phone.isNotEmpty) phone,
              if (scout.isNotEmpty) '스카우트번호 $scout',
            ].join('  ·  '),
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 13),
          onTap: () => Navigator.pop(context, m),
        );
      },
    );
  }
}
