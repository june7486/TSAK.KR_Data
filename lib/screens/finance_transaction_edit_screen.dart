import 'package:flutter/material.dart';

import '../models/finance_transaction.dart';
import '../models/member.dart';
import '../services/finance_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_home_emblem.dart';
import '../widgets/tsak_app_bar.dart';

/// 입금/지출 직접 입력·수정 화면
class FinanceTransactionEditScreen extends StatefulWidget {
  const FinanceTransactionEditScreen({
    super.key,
    required this.finance,
    required this.members,
    this.existing,
  });

  final FinanceService finance;
  final List<Member> members;
  final FinanceTransaction? existing;

  @override
  State<FinanceTransactionEditScreen> createState() =>
      _FinanceTransactionEditScreenState();
}

class _FinanceTransactionEditScreenState
    extends State<FinanceTransactionEditScreen> {
  late TextEditingController _date;
  late TextEditingController _payer;
  late TextEditingController _amount;
  late TextEditingController _event;
  late TextEditingController _memo;
  late String _type;
  late String _category;
  Member? _member;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = TextEditingController(
      text:
          e?.date ??
          DateTime.now().toString().split(' ').first.replaceAll('-', '.'),
    );
    _payer = TextEditingController(text: e?.payer ?? '');
    _amount = TextEditingController(
      text: e == null || e.amount == 0 ? '' : '${e.amount}',
    );
    _event = TextEditingController(text: e?.event ?? '');
    _memo = TextEditingController(text: e?.memo ?? '');
    _type = e?.type ?? 'income';
    _category = e?.category ?? '후원';
    if (e != null && e.number.isNotEmpty) {
      _member = widget.members
          .where(
            (m) =>
                m.number.replaceAll(RegExp(r'[^0-9]'), '') ==
                e.number.replaceAll(RegExp(r'[^0-9]'), ''),
          )
          .cast<Member?>()
          .firstWhere((m) => true, orElse: () => null);
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _payer.dispose();
    _amount.dispose();
    _event.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    final cats = _type == 'expense'
        ? widget.finance.expenseCategories
        : widget.finance.incomeCategories;
    return Scaffold(
      appBar: TsakAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(e == null ? '입금/지출 입력' : '내역 수정'),
        titleSpacing: 0,
        actions: [
          const AppHomeEmblem(size: 24),
          TextButton(
            onPressed: _save,
            child: const Text(
              '저장',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'income',
                label: Text('입금'),
                icon: Icon(Icons.south_west),
              ),
              ButtonSegment(
                value: 'expense',
                label: Text('지출'),
                icon: Icon(Icons.north_east),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _category = _type == 'expense' ? '행사비' : '후원';
            }),
          ),
          const SizedBox(height: 14),
          _label('일자'),
          TextField(
            controller: _date,
            decoration: const InputDecoration(hintText: '예: 2024.05.01'),
          ),
          const SizedBox(height: 12),
          _label('입금자 원문 (이름 앞뒤 내용 포함 가능)'),
          TextField(
            controller: _payer,
            onChanged: (_) => _autoMatch(),
            decoration: const InputDecoration(hintText: '예: 홍길동 제405단 후원'),
          ),
          if (_member != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 15,
                    color: AppColors.scoutGreen,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '인식: ${_member!.name} (${_member!.numberLabel})',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.scoutGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton(
                    onPressed: _pickMember,
                    child: const Text('변경', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickMember,
                icon: const Icon(Icons.person_search, size: 16),
                label: const Text('인가자 직접 연결', style: TextStyle(fontSize: 12)),
              ),
            ),
          const SizedBox(height: 12),
          _label('금액 (원)'),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '예: 100000'),
          ),
          const SizedBox(height: 12),
          _label('분류'),
          Wrap(
            spacing: 6,
            children: [
              for (final c in cats)
                ChoiceChip(
                  label: Text(c, style: const TextStyle(fontSize: 12)),
                  selected: _category == c,
                  selectedColor: AppColors.purple,
                  labelStyle: TextStyle(
                    color: _category == c ? Colors.white : AppColors.textDark,
                  ),
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _label('행사명 (선택 — 동일 행사 결산용)'),
          TextField(
            controller: _event,
            decoration: const InputDecoration(hintText: '예: 2024 정기총회'),
          ),
          const SizedBox(height: 12),
          _label('메모'),
          TextField(controller: _memo, maxLines: 2),
          const SizedBox(height: 20),
          if (e != null)
            OutlinedButton.icon(
              onPressed: () {
                widget.finance.removeTransaction(e.id);
                widget.finance.save();
                Navigator.pop(context);
              },
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.taegeukRed,
              ),
              label: const Text(
                '삭제',
                style: TextStyle(color: AppColors.taegeukRed),
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 5, left: 2),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      ),
    ),
  );

  void _autoMatch() {
    final text = _payer.text.trim();
    if (text.isEmpty) {
      setState(() => _member = null);
      return;
    }
    Member? best;
    for (final m in widget.members) {
      final mn = m.name.trim();
      if (mn.length >= 2 && text.contains(mn)) {
        if (best == null || mn.length > best.name.trim().length) best = m;
      }
    }
    setState(() => _member = best);
  }

  Future<void> _pickMember() async {
    final picked = await showModalBottomSheet<Member>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemberPickerSheet(members: widget.members),
    );
    if (picked != null) setState(() => _member = picked);
  }

  void _save() {
    final amount =
        int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9\-]'), '')) ?? 0;
    final payer = _payer.text.trim();
    final event = _event.text.trim();
    final no = _member?.number.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final t = FinanceTransaction(
      id: widget.existing?.id ?? '',
      date: _date.text.trim(),
      type: _type,
      payer: payer,
      name: _member?.name.isNotEmpty == true ? _member!.name : payer,
      number: no,
      memberId: _member?.id ?? '',
      amount: amount,
      category: _category,
      event: event,
      context: event.isNotEmpty ? event : '',
      memo: _memo.text.trim(),
      status: no.isNotEmpty ? 'matched' : 'unmatched',
      year: RegExp(r'(20\d{2})').firstMatch(_date.text)?.group(1) ?? '',
      source: widget.existing?.source.isNotEmpty == true
          ? widget.existing!.source
          : 'manual',
    );
    if (widget.existing != null) {
      widget.finance.updateTransaction(t);
    } else {
      widget.finance.addTransaction(t);
    }
    widget.finance.save();
    Navigator.pop(context);
  }
}

class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.members});
  final List<Member> members;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.members
        .where((m) => _q.isEmpty || m.searchText.contains(_q.toLowerCase()))
        .take(80)
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: '이름/번호 검색',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              itemCount: list.length,
              itemBuilder: (_, i) {
                final m = list[i];
                return ListTile(
                  dense: true,
                  title: Text('${m.name} (${m.numberLabel})'),
                  subtitle: Text(
                    '${m.league} ${m.unit}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(context, m),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
