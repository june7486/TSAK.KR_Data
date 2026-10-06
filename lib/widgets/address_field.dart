import 'package:flutter/material.dart';

import '../services/web_nav.dart';
import '../theme/app_theme.dart';

/// 주소 입력 필드 — 카카오 우편번호(Postcode) API 기반.
///
/// - 우측 "주소검색" 버튼 → 카카오 우편번호 팝업
///   (`//t1.kakaocdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js`)
/// - 도로명주소(userSelectedType==='R')를 우선 사용, 없으면 지번주소
/// - 선택 결과를 `[우편번호] 도로명주소` 형태로 컨트롤러에 채운다.
/// - 이어서 상세주소를 입력받아 뒤에 덧붙인다. (선택)
///
/// 웹이 아닌 네이티브 환경에서는 카카오 스크립트를 쓸 수 없으므로
/// 직접 입력 다이얼로그로 대체한다.
class AddressField extends StatefulWidget {
  const AddressField({
    super.key,
    required this.controller,
    this.label = '주소',
    this.hint = '주소검색 버튼으로 검색하세요',
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
  bool _busy = false;

  Future<void> _openSearch() async {
    if (_busy) return;
    setState(() => _busy = true);

    String? picked;
    try {
      if (isWebRuntime) {
        picked = await openKakaoPostcode();
      } else {
        picked = await _manualEntry();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted || picked == null || picked.trim().isEmpty) return;

    widget.controller.text = picked.trim();

    // 상세주소를 추가로 입력받아 덧붙인다. (카카오 예제와 동일한 흐름)
    final detail = await _askDetail();
    if (detail != null && detail.trim().isNotEmpty) {
      widget.controller.text = '${widget.controller.text} ${detail.trim()}';
    }
    if (mounted) setState(() {});
  }

  Future<String?> _askDetail() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('상세주소 입력'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '예) 101동 1203호 / 3층',
            isDense: true,
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('건너뛰기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return ok == true ? c.text : null;
  }

  Future<String?> _manualEntry() async {
    final c = TextEditingController(text: widget.controller.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
        scrollable: true,
        title: const Text('주소 입력'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: '[우편번호] 도로명주소 상세주소',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return ok == true ? c.text : null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: widget.controller,
        maxLines: 2,
        minLines: 1,
        validator: widget.required
            ? (v) => (v == null || v.trim().isEmpty) ? '주소를 입력하세요' : null
            : null,
        decoration: InputDecoration(
          labelText: widget.label + (widget.required ? ' *' : ''),
          hintText: widget.hint,
          isDense: true,
          suffixIcon: _busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: '주소검색 (카카오)',
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: _openSearch,
                ),
        ),
      ),
    );
  }
}

/// 카카오 스타일 주소검색 버튼 (다른 화면에서 재사용 가능).
class KakaoAddressButton extends StatelessWidget {
  const KakaoAddressButton({
    super.key,
    required this.onPicked,
    this.current = '',
    this.label = '주소 검색',
  });

  final ValueChanged<String> onPicked;
  final String current;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: () async {
          String? picked;
          if (isWebRuntime) {
            picked = await openKakaoPostcode();
          }
          if (picked != null && picked.trim().isNotEmpty) {
            onPicked(picked.trim());
          }
        },
        icon: const Icon(Icons.search, size: 18, color: Colors.white),
        label: Text(label),
      ),
    );
  }
}
