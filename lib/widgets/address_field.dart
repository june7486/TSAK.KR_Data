import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nas_api.dart';
import '../theme/app_theme.dart';

/// 도로명주소 검색 필드.
/// - 우측 "주소검색" 버튼 → 검색 다이얼로그(자동완성 목록)
/// - 입력 중 debounce 자동완성 (선택 시 도로명 주소로 채움)
class AddressField extends StatefulWidget {
  const AddressField({
    super.key,
    required this.controller,
    this.label = '주소',
    this.hint = '주소 입력',
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String _) {
    // 자동완성은 검색 다이얼로그에서 제공 (입력 필드 자체는 자유입력 허용)
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {});
  }

  Future<void> _openSearch() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressSearchSheet(initial: widget.controller.text),
    );
    if (picked != null && picked.isNotEmpty) {
      widget.controller.text = picked;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: widget.controller,
        maxLines: 2,
        minLines: 1,
        onChanged: _onChanged,
        validator: widget.required
            ? (v) => (v == null || v.trim().isEmpty) ? '주소를 입력하세요' : null
            : null,
        decoration: InputDecoration(
          labelText: widget.label + (widget.required ? ' *' : ''),
          hintText: widget.hint,
          isDense: true,
          suffixIcon: IconButton(
            tooltip: '주소검색',
            icon: const Icon(Icons.search, size: 20),
            onPressed: _openSearch,
          ),
        ),
      ),
    );
  }
}

class _AddressSearchSheet extends StatefulWidget {
  const _AddressSearchSheet({this.initial = ''});
  final String initial;

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  late final TextEditingController _q =
      TextEditingController(text: widget.initial);
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.initial.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final kw = _q.text.trim();
    if (kw.length < 2) {
      setState(() {
        _items = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final nas = context.read<NasApi>();
    final items = await nas.addrSearch(kw);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      if (items.isEmpty) _error = '검색 결과가 없습니다';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textGray.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, color: AppColors.purple),
                const SizedBox(width: 6),
                const Text('도로명주소 검색',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            TextField(
              controller: _q,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '도로명·건물명·지번 (예: 세종대로, 강남대로12길)',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text(
                        _error ?? '주소를 검색해 주세요',
                        style: const TextStyle(color: AppColors.textGray),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        final road = '${it['road'] ?? ''}';
                        final road2 = '${it['roadPart2'] ?? ''}';
                        final jibun = '${it['jibun'] ?? ''}';
                        final zip = '${it['zip'] ?? ''}';
                        final full = '$road $road2'.trim();
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined,
                              color: AppColors.purple, size: 20),
                          title: Text(full,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            jibun + (zip.isNotEmpty ? '  ·  우편번호 $zip' : ''),
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textGray),
                          ),
                          onTap: () => Navigator.pop(
                              context, zip.isNotEmpty ? '[$zip] $full' : full),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
