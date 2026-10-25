/// 출금계좌 선택 도우미 — 대표 3계좌 중 선택 또는 직접입력.
///
/// (요구) "지출은 출금계좌(대표 3계좌 중 선택)도 선택 또는 직접입력할 수 있도록"
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/event_settlement.dart';

class EventAccountPicker extends StatelessWidget {
  const EventAccountPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDirect = true,
  });

  /// 현재 선택된 계좌 표기('행사비 · 우리은행 1005-003-886274') 또는 직접입력 값.
  final String value;

  /// 선택/입력 결과 콜백.
  final ValueChanged<String> onChanged;

  /// 직접입력 허용 여부.
  final bool allowDirect;

  @override
  Widget build(BuildContext context) {
    // AppState 설정의 대표 계좌 목록(대표·수품구매·행사비).
    final accounts = context
        .watch<AppState>()
        .donations
        .map(
          (d) => EventAccount(
            label: '${d['label'] ?? ''}'.split('(').first.trim(),
            bank: '${d['bank'] ?? ''}',
            account: '${d['account'] ?? ''}',
          ),
        )
        .where((a) => a.isValid)
        .toList();

    final isPreset = accounts.any((a) => a.pickLabel == value);
    final sel = isPreset ? value : '__direct__';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: sel,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '출금계좌', isDense: true),
          items: [
            for (final a in accounts)
              DropdownMenuItem(
                value: a.pickLabel,
                child: Text(
                  a.pickLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            if (allowDirect)
              const DropdownMenuItem(
                value: '__direct__',
                child: Text('직접입력', style: TextStyle(fontSize: 12.5)),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v == '__direct__' ? '' : v);
          },
        ),
        if (!isPreset && allowDirect)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextFormField(
              initialValue: value,
              decoration: const InputDecoration(
                labelText: '출금계좌 직접입력',
                hintText: '예: 국민은행 123-456-789',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12.5),
              onChanged: onChanged,
            ),
          ),
      ],
    );
  }
}

/// 후원 분류 선택 도우미 — 식사/물품/차량/기타(직접입력).
///
/// (요구) "후원항목 세분화할 것: 식사후원, 물품후원, 차량후원, 기타후원(직접입력)"
class DonationKindPicker extends StatelessWidget {
  const DonationKindPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.itemController,
  });

  /// 현재 분류 라벨('식사후원' 등).
  final String value;
  final ValueChanged<String> onChanged;

  /// 기타후원일 때 '내역 직접입력' 컨트롤러.
  final TextEditingController? itemController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '후원 항목', isDense: true),
          items: [
            for (final k in DonationKindOptions.all)
              DropdownMenuItem(
                value: k,
                child: Text(
                  k,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ],
    );
  }
}

/// 후원 분류 라벨 목록(순서 고정).
class DonationKindOptions {
  const DonationKindOptions._();

  static const List<String> all = ['후원금', '식사후원', '물품후원', '차량후원', '기타후원'];

  /// 후원(현물)만 — 후원금 제외.
  static const List<String> sponsors = ['식사후원', '물품후원', '차량후원', '기타후원'];
}
