import 'package:flutter/foundation.dart';

import '../models/member.dart';
import 'member_repository.dart';

/// 전역 앱 상태 (Provider)
class AppState extends ChangeNotifier {
  AppState(this.repo) {
    repo.revision.addListener(_onRepoChanged);
  }

  final MemberRepository repo;

  List<Member> _members = [];
  String _query = '';
  String _leagueFilter = '';
  String _yearFilter = '';
  bool _onlyLifetime = false;

  List<Member> get members => _members;
  String get query => _query;
  String get leagueFilter => _leagueFilter;
  String get yearFilter => _yearFilter;
  bool get onlyLifetime => _onlyLifetime;

  Map<String, int> get leagues => repo.leaguesWithCount();
  List<String> get feeYears => repo.feeYearOptions();
  List<String> get events => repo.eventOptions();

  int get total => repo.count;
  int get lifetimeCount => _filterBase().where((m) => m.lifetimeMember).length;

  void _onRepoChanged() {
    refresh();
  }

  void refresh() {
    var list = _filterBase();
    if (_leagueFilter.isNotEmpty) {
      if (_leagueFilter == '(미지정)') {
        list = list.where((m) => m.league.trim().isEmpty).toList();
      } else {
        list = list.where((m) => m.league == _leagueFilter).toList();
      }
    }
    if (_yearFilter.isNotEmpty) {
      list = list.where((m) => m.feeYears[_yearFilter] == true).toList();
    }
    if (_onlyLifetime) {
      list = list.where((m) => m.lifetimeMember).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      final parts = q.split(RegExp(r'\s+'));
      list = list
          .where((m) => parts.every((p) => m.searchText.contains(p)))
          .toList();
    }
    _members = list;
    notifyListeners();
  }

  List<Member> _filterBase() => repo.all();

  void setQuery(String q) {
    _query = q;
    refresh();
  }

  void setLeague(String l) {
    _leagueFilter = l;
    refresh();
  }

  void setYear(String y) {
    _yearFilter = y;
    refresh();
  }

  void setOnlyLifetime(bool v) {
    _onlyLifetime = v;
    refresh();
  }

  void clearFilters() {
    _query = '';
    _leagueFilter = '';
    _yearFilter = '';
    _onlyLifetime = false;
    refresh();
  }

  Member? byId(String id) => repo.byId(id);

  Future<void> save(Member m) async {
    await repo.save(m);
  }

  Future<void> delete(String id) async {
    await repo.delete(id);
  }

  Future<int> nextNumber() => repo.nextNumber();

  // 통계
  Map<int, int> get yearDistribution {
    final map = <int, int>{};
    for (final v in repo.all()) {
      final y = int.tryParse(v.date.replaceAll('.', '-').split('-').first);
      if (y != null && y > 1900) map[y] = (map[y] ?? 0) + 1;
    }
    return map;
  }

  @override
  void dispose() {
    repo.revision.removeListener(_onRepoChanged);
    super.dispose();
  }
}
