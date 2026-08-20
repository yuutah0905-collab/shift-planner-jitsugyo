import 'package:flutter/material.dart';
import '../models/day_entry.dart';
import '../models/employee.dart';
import '../models/shift_code.dart';
import '../models/shift_submission.dart';
import '../theme/app_theme.dart';

/// One person's shift entry for a single day, resolved for display.
class _DayAttendance {
  final String name;
  final String department;
  final DayEntry entry;

  _DayAttendance({required this.name, required this.department, required this.entry});

  double get hours => double.tryParse(entry.hours) ?? 0.0;
  bool get isPaidLeave => ShiftCode.isPaidLeave(entry.code);
}

/// Admin screen: "今日、誰が出勤して合計何時間か" at a glance, filterable by
/// department tab (linked to whichever department the admin had selected
/// on the dashboard). Shows one date at a time (with prev/next day
/// navigation and a date picker), so the admin can quickly check any day
/// in the target month without hunting through each person's individual
/// submission.
class DailyAttendanceScreen extends StatefulWidget {
  final List<ShiftSubmission> submissions;
  final String targetMonth; // "YYYY-MM"

  /// Department tab labels in display order (already sorted by the
  /// dashboard's fixed department order), NOT including "すべて".
  final List<String> availableDepartments;

  /// '' means "すべて" (all departments) - matches the dashboard's own
  /// _selectedDepartment convention so the two screens stay in sync.
  final String initialDepartment;

  /// Registered employee roster (in the order registered in 設定 >
  /// 従業員名簿). Used to sort the attendance list by roster order
  /// instead of alphabetically by name, so the list order matches the
  /// staff list the admin is used to. Names not found in the roster
  /// (e.g. someone who submitted but was removed from the roster) are
  /// appended at the end in name order.
  final List<Employee> employees;

  const DailyAttendanceScreen({
    super.key,
    required this.submissions,
    required this.targetMonth,
    required this.availableDepartments,
    this.initialDepartment = '',
    this.employees = const [],
  });

  @override
  State<DailyAttendanceScreen> createState() => _DailyAttendanceScreenState();
}

class _DailyAttendanceScreenState extends State<DailyAttendanceScreen> {
  late DateTime _selectedDate;
  late DateTime _firstDay;
  late DateTime _lastDay;

  /// '' = すべて（全部署）。Selecting a department tab filters the list to
  /// just that department, mirroring the dashboard's own department tabs.
  late String _selectedDepartment;

  @override
  void initState() {
    super.initState();
    _buildRosterOrder();
    // "すべて" tab has been removed - always land on a real department tab.
    // Use initialDepartment if it's a valid department, otherwise fall
    // back to the first available department.
    if (widget.initialDepartment.isNotEmpty &&
        widget.availableDepartments.contains(widget.initialDepartment)) {
      _selectedDepartment = widget.initialDepartment;
    } else if (widget.availableDepartments.isNotEmpty) {
      _selectedDepartment = widget.availableDepartments.first;
    } else {
      _selectedDepartment = '';
    }
    final parts = widget.targetMonth.split('-');
    final year = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? DateTime.now().year;
    final month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
    _firstDay = DateTime(year, month, 1);
    _lastDay = DateTime(year, month + 1, 0);

    // Default to today if it falls within the target month, otherwise
    // the 1st of the target month.
    final today = DateTime.now();
    final todayInRange = DateTime(today.year, today.month, today.day);
    if (!todayInRange.isBefore(_firstDay) && !todayInRange.isAfter(_lastDay)) {
      _selectedDate = todayInRange;
    } else {
      _selectedDate = _firstDay;
    }
  }

  String get _dateKey =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  static const List<String> _dowJp = ['日', '月', '火', '水', '木', '金', '土'];

  String get _dateLabel {
    final dow = _dowJp[_selectedDate.weekday % 7];
    return '${_selectedDate.month}月${_selectedDate.day}日（$dow）';
  }

  bool get _isToday {
    final today = DateTime.now();
    return _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
  }

  void _changeDay(int delta) {
    final next = _selectedDate.add(Duration(days: delta));
    if (next.isBefore(_firstDay) || next.isAfter(_lastDay)) return;
    setState(() => _selectedDate = next);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _firstDay,
      lastDate: _lastDay,
      locale: const Locale('ja', 'JP'),
      helpText: '日付を選択',
      cancelText: 'キャンセル',
      confirmText: '選択',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  /// All (name, department, entry) rows for the currently selected date,
  /// across every submission - only rows that actually have a code/hours
  /// entered (not blank days) are included. Not yet filtered by department.
  List<_DayAttendance> get _allAttendanceForSelectedDate {
    final key = _dateKey;
    final result = <_DayAttendance>[];
    for (final s in widget.submissions) {
      for (final d in s.days) {
        if (d.date != key) continue;
        if (d.hours.isEmpty && d.code.isEmpty) continue;
        result.add(_DayAttendance(name: s.name, department: s.department, entry: d));
      }
    }
    return result;
  }

  /// Maps a normalized employee name to its registration order (index in
  /// 設定 > 従業員名簿). Built once from widget.employees so the
  /// attendance list can be sorted by roster order instead of
  /// alphabetically - matching the order the admin registered staff in,
  /// regardless of the order shifts happened to be submitted.
  late Map<String, int> _rosterOrder;

  void _buildRosterOrder() {
    _rosterOrder = {};
    for (int i = 0; i < widget.employees.length; i++) {
      _rosterOrder[Employee.normalizeName(widget.employees[i].name)] = i;
    }
  }

  /// Same as above, but filtered to [_selectedDepartment] ('' = all),
  /// sorted by roster registration order (falling back to name order for
  /// anyone not found in the roster, placed after all roster members).
  List<_DayAttendance> get _attendanceForSelectedDate {
    final all = _allAttendanceForSelectedDate;
    final filtered = _selectedDepartment.isEmpty
        ? all
        : all.where((a) => a.department == _selectedDepartment).toList();
    filtered.sort((a, b) {
      final orderA = _rosterOrder[Employee.normalizeName(a.name)];
      final orderB = _rosterOrder[Employee.normalizeName(b.name)];
      if (orderA != null && orderB != null) return orderA.compareTo(orderB);
      if (orderA != null) return -1; // a is in roster, b is not -> a first
      if (orderB != null) return 1; // b is in roster, a is not -> b first
      return a.name.compareTo(b.name); // neither in roster -> name order
    });
    return filtered;
  }

  /// Count of attendees per department for the selected date, used as the
  /// "(N)" badge on each department tab chip. Key '' represents the total
  /// across all departments (すべて).
  Map<String, int> get _countByDepartment {
    final all = _allAttendanceForSelectedDate;
    final map = <String, int>{'': all.length};
    for (final d in widget.availableDepartments) {
      map[d] = all.where((a) => a.department == d).length;
    }
    return map;
  }

  double get _grandTotalHours =>
      _attendanceForSelectedDate.fold(0.0, (sum, a) => sum + a.hours);

  int get _grandTotalCount => _attendanceForSelectedDate.length;

  @override
  Widget build(BuildContext context) {
    final attendanceList = _attendanceForSelectedDate;
    final counts = _countByDepartment;
    final canGoPrev = !_selectedDate.isBefore(_firstDay.add(const Duration(days: 1)));
    final canGoNext = !_selectedDate.isAfter(_lastDay.subtract(const Duration(days: 1)));

    return Scaffold(
      appBar: AppBar(title: const Text('日別出勤状況')),
      body: SafeArea(
        child: Column(
          children: [
            // Date navigator
            Container(
              color: AppColors.primary,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: canGoPrev ? () => _changeDay(-1) : null,
                    disabledColor: Colors.white38,
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _dateLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.calendar_today,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ),
                            if (_isToday)
                              Container(
                                margin: const EdgeInsets.only(top: 3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '今日',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: canGoNext ? () => _changeDay(1) : null,
                    disabledColor: Colors.white38,
                  ),
                ],
              ),
            ),
            // Grand total summary
            Container(
              width: double.infinity,
              color: AppColors.primaryDeep,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _summaryStat(Icons.groups, '$_grandTotalCount名', '出勤人数'),
                  Container(
                    width: 1,
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  _summaryStat(
                    Icons.schedule,
                    '${_grandTotalHours.toStringAsFixed(2)}h',
                    '合計労働時間',
                  ),
                ],
              ),
            ),
            // Department tabs, linked to the dashboard's own department
            // selection (initialDepartment) but independently switchable
            // here so the admin can flip between departments without
            // leaving this screen. No "すべて" (all) tab - only real
            // departments are shown, one of which is always selected.
            if (widget.availableDepartments.isNotEmpty)
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < widget.availableDepartments.length; i++)
                          Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                            child: _deptTab(
                              widget.availableDepartments[i],
                              widget.availableDepartments[i],
                              counts[widget.availableDepartments[i]] ?? 0,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: attendanceList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 48,
                            color: AppColors.inkMute.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedDepartment.isEmpty
                                ? 'この日の出勤予定はありません'
                                : 'この日・この部署の出勤予定はありません',
                            style: const TextStyle(color: AppColors.inkMute),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                      children: [
                        _attendanceListCard(attendanceList),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
        ),
      ],
    );
  }

  Widget _deptTab(String label, String value, int count) {
    final selected = _selectedDepartment == value;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _selectedDepartment = value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.background,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.ink,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
    );
  }

  Widget _attendanceListCard(List<_DayAttendance> list) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < list.length; i++)
            _attendanceRow(
              list[i],
              isLast: i == list.length - 1,
              // Only show the department tag inline when viewing "すべて",
              // since a single-department tab already makes it obvious.
              showDepartment: _selectedDepartment.isEmpty,
            ),
        ],
      ),
    );
  }

  Widget _attendanceRow(
    _DayAttendance a, {
    required bool isLast,
    bool showDepartment = false,
  }) {
    final accent = a.isPaidLeave ? AppColors.paidLeave : AppColors.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.line, width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    a.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showDepartment && a.department.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '（${a.department}）',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkMute,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (a.entry.memo.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.sticky_note_2_outlined, size: 15, color: AppColors.success),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              a.isPaidLeave ? ShiftCode.paidLeaveCode : a.entry.code,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: a.isPaidLeave ? AppColors.paidLeave : AppColors.primaryDeep,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
            child: Text(
              '${a.hours.toStringAsFixed(2)}h',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
