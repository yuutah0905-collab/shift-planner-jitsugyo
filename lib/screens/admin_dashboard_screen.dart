import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/shift_submission.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'submission_detail_screen.dart';
import 'admin_settings_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<ShiftSubmission> _submissions = [];
  List<String> _departments = [];
  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;
  String _filterMonth = '';

  /// '' means "すべての部署" (no filter)
  String _selectedDepartment = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _firestoreService.fetchConfig();
      _filterMonth = config.targetMonth;
      _departments = config.departments;
      _employees = config.employees;
      final list = await _firestoreService.fetchSubmissionsForMonth(
        _filterMonth,
      );
      setState(() {
        _submissions = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'データの取得に失敗しました';
        _loading = false;
      });
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _firestoreService.fetchAllSubmissions();
      setState(() {
        _submissions = list;
        _filterMonth = '';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'データの取得に失敗しました';
        _loading = false;
      });
    }
  }

  String _fmtMonthJp(String ym) {
    final parts = ym.split('-');
    if (parts.length != 2) return ym;
    return '${parts[0]}年${int.parse(parts[1])}月';
  }

  /// All department labels that should appear as filter chips:
  /// configured departments + any department actually used in the
  /// submissions (in case old/unlisted department names exist).
  List<String> get _availableDepartments {
    final set = <String>{..._departments};
    for (final s in _submissions) {
      if (s.department.isNotEmpty) set.add(s.department);
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  /// Registered employees who have NOT submitted a shift request for the
  /// currently filtered month. Only meaningful when a specific month is
  /// selected (i.e. not in "すべて表示" mode), matched by name+department.
  ///
  /// Names are normalized (whitespace removed, case-insensitive) before
  /// comparison so that spacing differences between how the admin
  /// registered the roster and how staff typed their own name when
  /// submitting (e.g. "山田 太郎" vs "山田太郎") don't cause a false
  /// "not submitted" result.
  List<Employee> get _unsubmittedEmployees {
    if (_filterMonth.isEmpty) return [];
    final submittedKeys = _submissions
        .map((s) => '${Employee.normalizeName(s.name)}|${s.department}')
        .toSet();
    return _employees
        .where(
          (e) => !submittedKeys.contains(
            '${Employee.normalizeName(e.name)}|${e.department}',
          ),
        )
        .toList();
  }

  List<ShiftSubmission> get _filteredSubmissions {
    if (_selectedDepartment.isEmpty) return _submissions;
    return _submissions
        .where((s) => s.department == _selectedDepartment)
        .toList();
  }

  /// Groups filtered submissions by department, preserving each group's
  /// original (already-sorted) order. Only used when no department
  /// filter is selected, so admins can see a department-sorted overview.
  Map<String, List<ShiftSubmission>> get _groupedByDepartment {
    final Map<String, List<ShiftSubmission>> map = {};
    for (final s in _filteredSubmissions) {
      final key = s.department.isEmpty ? '未設定' : s.department;
      map.putIfAbsent(key, () => []).add(s);
    }
    final sortedKeys = map.keys.toList()..sort();
    return {for (final k in sortedKeys) k: map[k]!};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filterMonth.isEmpty
              ? '全員のシフト希望一覧'
              : '${_fmtMonthJp(_filterMonth)} シフト希望一覧',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '希望表の設定',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
              );
              if (mounted) _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _filterMonth.isEmpty ? _loadAll : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: const Text('再試行')),
                  ],
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _load,
                            child: const Text('今月のみ表示'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loadAll,
                            child: const Text('すべて表示'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_filterMonth.isNotEmpty && _employees.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: _buildUnsubmittedBanner(),
                    ),
                  if (_availableDepartments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _deptChip('すべて', ''),
                              ..._availableDepartments.map(
                                (d) => Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _deptChip(d, d),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: _filteredSubmissions.isEmpty
                        ? Center(
                            child: Text(
                              _submissions.isEmpty
                                  ? 'まだ提出はありません'
                                  : 'この部署の提出はありません',
                              style: const TextStyle(color: AppColors.inkMute),
                            ),
                          )
                        : _selectedDepartment.isEmpty
                        ? _buildGroupedList()
                        : _buildFlatList(_filteredSubmissions),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildUnsubmittedBanner() {
    final unsubmitted = _unsubmittedEmployees;
    if (unsubmitted.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              '全員提出済みです（${_employees.length}名）',
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      color: Colors.red.withValues(alpha: 0.05),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.redAccent,
        ),
        title: Text(
          '未提出者 ${unsubmitted.length}名 ／ ${_employees.length}名中',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
            fontSize: 13,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unsubmitted
                  .map(
                    (e) => Chip(
                      label: Text(
                        e.department.isEmpty
                            ? e.name
                            : '${e.name}（${e.department}）',
                      ),
                      backgroundColor: Colors.red.withValues(alpha: 0.08),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deptChip(String label, String value) {
    final selected = _selectedDepartment == value;
    final count = value.isEmpty
        ? _submissions.length
        : _submissions.where((s) => s.department == value).length;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _selectedDepartment = value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.ink,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
    );
  }

  Widget _buildGroupedList() {
    final grouped = _groupedByDepartment;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6, left: 2),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${entry.key} （${entry.value.length}件）',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDeep,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ...entry.value.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _submissionCard(s),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFlatList(List<ShiftSubmission> list) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _submissionCard(list[index]),
    );
  }

  Widget _submissionCard(ShiftSubmission s) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: Text(
            s.name.isNotEmpty ? s.name[0] : '?',
            style: const TextStyle(
              color: AppColors.primaryDeep,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (s.isResubmission) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '再提出 ${s.submissionCount}回目',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${s.department} ／ ${_fmtMonthJp(s.targetMonth)} ／ 合計 ${s.totalHours.toStringAsFixed(2)}h',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          // Wait for the detail screen to close (e.g. after a delete),
          // then refresh the list so deleted/edited entries disappear
          // immediately instead of requiring a manual "更新" tap.
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubmissionDetailScreen(submission: s),
            ),
          );
          if (!mounted) return;
          _filterMonth.isEmpty ? _loadAll() : _load();
        },
      ),
    );
  }
}
