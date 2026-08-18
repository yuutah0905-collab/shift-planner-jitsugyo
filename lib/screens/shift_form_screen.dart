import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import '../models/day_entry.dart';
import '../models/employee.dart';
import '../models/shift_code.dart';
import '../models/shift_submission.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/day_cell.dart';
import '../widgets/summary_card.dart';
import 'admin_login_screen.dart';
import 'help_screen.dart';

const List<String> _dowJp = ['日', '月', '火', '水', '木', '金', '土'];
const List<String> _dowJpHeader = ['日', '月', '火', '水', '木', '金', '土'];

class ShiftFormScreen extends StatefulWidget {
  const ShiftFormScreen({super.key});

  @override
  State<ShiftFormScreen> createState() => _ShiftFormScreenState();
}

class _ShiftFormScreenState extends State<ShiftFormScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final LocalStorageService _localStorage = LocalStorageService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _monthMemoController = TextEditingController();
  String? _selectedDepartment;

  AppConfig? _config;
  Map<String, DayEntry> _days = {};
  bool _loading = true;
  bool _submitting = false;

  // 一括入力（bulk input）モード: 有効化すると日付セルをタップして
  // 複数選択でき、選択した日にまとめて同じ記号を適用できる。
  bool _bulkMode = false;
  final Set<String> _selectedDates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final config = await _firestoreService.fetchConfig();
    _buildDays(config);
    await _restoreLocalState(config);
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  /// Pull-to-refresh: re-fetch the admin config (target month, holidays,
  /// deadline, notice, departments) without showing the full-screen loader.
  Future<void> _refresh() async {
    final config = await _firestoreService.fetchConfig();
    _buildDays(config);
    await _restoreLocalState(config);
    if (!mounted) return;
    setState(() {
      _config = config;
    });
    if (mounted) {
      _showSnack('最新の設定を取得しました');
    }
  }

  /// Builds a padded list of days (including leading blanks) so the
  /// calendar can be rendered as a proper 7-column (Sun-Sat) weekly grid.
  List<DayEntry?> _paddedDays(List<DayEntry> sortedDays) {
    if (sortedDays.isEmpty) return [];
    final firstDate = DateTime.parse(sortedDays.first.date);
    final leadingBlanks = firstDate.weekday % 7; // Sun=0 ... Sat=6
    final List<DayEntry?> padded = [
      ...List<DayEntry?>.filled(leadingBlanks, null),
      ...sortedDays,
    ];
    final remainder = padded.length % 7;
    if (remainder != 0) {
      padded.addAll(List<DayEntry?>.filled(7 - remainder, null));
    }
    return padded;
  }

  void _buildDays(AppConfig config) {
    final parts = config.targetMonth.split('-');
    if (parts.length != 2) {
      _days = {};
      return;
    }
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final lastDay = DateTime(year, month + 1, 0).day;
    final holidaySet = config.holidays.toSet();

    final Map<String, DayEntry> map = {};
    for (int d = 1; d <= lastDay; d++) {
      final date = DateTime(year, month, d);
      final jpIndex = date.weekday % 7; // Mon=1..Sun=7 -> Sun=0
      final dow = _dowJp[jpIndex];
      final isWeekend = jpIndex == 0 || jpIndex == 6;
      final dateStr =
          '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final isHoliday = isWeekend || holidaySet.contains(dateStr);
      map[dateStr] = DayEntry(
        date: dateStr,
        dayOfWeek: dow,
        isHoliday: isHoliday,
      );
    }
    _days = map;
  }

  Future<void> _restoreLocalState(AppConfig config) async {
    final saved = await _localStorage.loadState();
    if (saved == null) return;
    if (saved['targetMonth'] != config.targetMonth) {
      // Different month than last time - don't restore day data
      _nameController.text = saved['name']?.toString() ?? '';
      final dept = saved['department']?.toString();
      if (dept != null &&
          dept.isNotEmpty &&
          config.departments.contains(dept)) {
        _selectedDepartment = dept;
      }
      return;
    }
    _nameController.text = saved['name']?.toString() ?? '';
    _monthMemoController.text = saved['monthMemo']?.toString() ?? '';
    final dept = saved['department']?.toString();
    if (dept != null && dept.isNotEmpty && config.departments.contains(dept)) {
      _selectedDepartment = dept;
    }
    final savedDays = saved['days'] as Map<String, dynamic>?;
    if (savedDays != null) {
      savedDays.forEach((key, value) {
        if (_days.containsKey(key) && !_days[key]!.isHoliday) {
          final v = Map<String, dynamic>.from(value as Map);
          _days[key]!.hours = v['hours']?.toString() ?? '';
          _days[key]!.code = v['code']?.toString() ?? '';
          _days[key]!.memo = v['memo']?.toString() ?? '';
        }
      });
    }
  }

  Future<void> _saveLocal() async {
    if (_config == null) return;
    await _localStorage.saveState(
      name: _nameController.text,
      department: _selectedDepartment ?? '',
      monthMemo: _monthMemoController.text,
      days: _days,
      targetMonth: _config!.targetMonth,
    );
  }

  void _onDayChanged() {
    setState(() {});
    _saveLocal();
  }

  /// Employees registered (via admin settings) under the currently
  /// selected department, in the order the admin added them.
  List<Employee> get _employeesInSelectedDepartment {
    if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
      return [];
    }
    return _config!.employees
        .where((e) => e.department == _selectedDepartment)
        .toList();
  }

  /// Opens a bottom sheet listing registered employee names for the
  /// selected department (in admin-registration order) so staff can tap
  /// their own name instead of typing it. If the department hasn't been
  /// selected yet, or the roster for it is empty (e.g. new hires not yet
  /// registered), staff can just type their name in the field as before -
  /// tapping "手入力する" or dismissing the sheet keeps the field editable.
  Future<void> _openNamePicker() async {
    if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
      _showSnack('先に部署を選択すると、名前の一覧から選べます');
      return;
    }
    final roster = _employeesInSelectedDepartment;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NamePickerSheet(
        department: _selectedDepartment!,
        roster: roster,
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() => _nameController.text = picked);
      _saveLocal();
    }
  }

  void _toggleBulkMode() {
    setState(() {
      _bulkMode = !_bulkMode;
      _selectedDates.clear();
    });
  }

  void _toggleDateSelection(String date) {
    setState(() {
      if (_selectedDates.contains(date)) {
        _selectedDates.remove(date);
      } else {
        _selectedDates.add(date);
      }
    });
  }

  Future<void> _openBulkApplySheet() async {
    if (_selectedDates.isEmpty) {
      _showSnack('日にちを1つ以上選択してください');
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BulkApplySheet(count: _selectedDates.length),
    ).then((code) {
      if (code == null) return; // cancelled
      setState(() {
        for (final date in _selectedDates) {
          final entry = _days[date];
          if (entry == null || entry.isHoliday) continue;
          if (code == _bulkClearSentinel) {
            entry.code = '';
            entry.hours = '';
          } else {
            entry.code = code;
            final h = ShiftCode.hoursForCode(code);
            entry.hours = h != null ? h.toStringAsFixed(2) : '';
          }
        }
        _bulkMode = false;
        _selectedDates.clear();
      });
      _saveLocal();
      _showSnack('一括で入力しました');
    });
  }

  double get _totalHours {
    double total = 0;
    for (final d in _days.values) {
      final h = double.tryParse(d.hours);
      if (h != null) total += h;
    }
    return total;
  }

  int get _filledDays =>
      _days.values.where((d) => d.hours.isNotEmpty || d.code.isNotEmpty).length;

  int get _memoCount => _days.values.where((d) => d.memo.isNotEmpty).length;

  int get _holidayCount => _days.values.where((d) => d.isHoliday).length;

  String _fmtMonthJp(String ym) {
    final parts = ym.split('-');
    if (parts.length != 2) return ym;
    return '${parts[0]}年${int.parse(parts[1])}月';
  }

  static const String _bulkClearSentinel = '__clear__';

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('氏名を入力してください');
      return;
    }
    if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
      _showSnack('部署を選択してください');
      return;
    }

    setState(() => _submitting = true);
    try {
      final sortedDays = _days.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      final submission = ShiftSubmission(
        name: _nameController.text.trim(),
        department: _selectedDepartment!,
        targetMonth: _config!.targetMonth,
        monthMemo: _monthMemoController.text.trim(),
        days: sortedDays,
        totalHours: _totalHours,
      );
      await _firestoreService.submitShift(submission);
      // NOTE: We intentionally do NOT clear local storage or rebuild the
      // form here. Part-time staff need to be able to review exactly what
      // they submitted, so the entered name/department/days/memo must
      // remain visible on screen after a successful submission.
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Submit error: $e');
      if (mounted) {
        _showSnack('送信に失敗しました。通信環境を確認して再度お試しください。');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 8),
            Text('送信完了'),
          ],
        ),
        content: const Text(
          'シフト希望が管理人に送信されました。\n'
          '入力内容はこのまま画面に残りますので、いつでも見返せます。\n'
          'ご協力ありがとうございました！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final config = _config!;
    final sortedDays = _days.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final paddedDays = _paddedDays(sortedDays);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/icon/jitsugyo_logo.png',
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_fmtMonthJp(config.targetMonth)} シフト希望',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使い方ガイド',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: '管理者',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (config.notice.isNotEmpty ||
                          config.deadline.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (config.deadline.isNotEmpty)
                                Text(
                                  '受付締切: ${config.deadline}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDeep,
                                  ),
                                ),
                              if (config.notice.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    config.notice,
                                    style: const TextStyle(
                                      color: AppColors.inkSoft,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '基本情報',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDeep,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedDepartment,
                                decoration: const InputDecoration(
                                  labelText: '部署',
                                ),
                                items: config.departments
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text(d),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedDepartment = val;
                                    // 部署を変えたら、前の部署の名簿から選んだ
                                    // 氏名が混在しないよう手入力扱いのままにする
                                    // （氏名自体はクリアしない＝入力し直す手間を防ぐ）
                                  });
                                  _saveLocal();
                                },
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: '氏名',
                                  hintText: '氏名を入力、または一覧から選択',
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.people_alt_outlined),
                                    tooltip: '名前を一覧から選ぶ',
                                    onPressed: _openNamePicker,
                                  ),
                                ),
                                onChanged: (_) => _saveLocal(),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '記号（A〜Y）を選ぶと労働時間が自動で入ります。'
                                '「有」は有給休暇の希望です（水色で表示されます）',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkMute,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fmtMonthJp(config.targetMonth),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDeep,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SummaryCard(
                                filledDays: _filledDays,
                                totalHours: _totalHours,
                                memoCount: _memoCount,
                                holidayCount: _holidayCount,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _toggleBulkMode,
                                      icon: Icon(
                                        _bulkMode
                                            ? Icons.close
                                            : Icons.playlist_add_check,
                                      ),
                                      label: Text(
                                        _bulkMode ? '一括入力を終了' : '一括入力',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _bulkMode
                                            ? Colors.redAccent
                                            : AppColors.primaryDeep,
                                        side: BorderSide(
                                          color: _bulkMode
                                              ? Colors.redAccent
                                              : AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_bulkMode) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _selectedDates.isEmpty
                                            ? null
                                            : _openBulkApplySheet,
                                        icon: const Icon(Icons.check),
                                        label: Text(
                                          '${_selectedDates.length}日に適用',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_bulkMode)
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text(
                                    '一括で記号を入力したい日にちをタップして選択してください',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.inkMute,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              // Weekday header row (日〜土), matching the
                              // admin settings calendar layout.
                              Row(
                                children: List.generate(7, (i) {
                                  final color = i == 0
                                      ? AppColors.sun
                                      : i == 6
                                      ? AppColors.sat
                                      : AppColors.inkMute;
                                  return Expanded(
                                    child: Center(
                                      child: Text(
                                        _dowJpHeader[i],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 6),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 7,
                                      childAspectRatio: 0.85,
                                      crossAxisSpacing: 4,
                                      mainAxisSpacing: 4,
                                    ),
                                itemCount: paddedDays.length,
                                itemBuilder: (context, index) {
                                  final entry = paddedDays[index];
                                  if (entry == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return DayCell(
                                    entry: entry,
                                    onChanged: _onDayChanged,
                                    selectionMode: _bulkMode,
                                    selected: _selectedDates.contains(
                                      entry.date,
                                    ),
                                    onSelectToggle: () =>
                                        _toggleDateSelection(entry.date),
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'タップして記号・メモを入力できます（🟢=メモあり）',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMute,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '今月のメモ（任意）',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDeep,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _monthMemoController,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  hintText: '例：来月は忙しいので調整お願いします',
                                ),
                                onChanged: (_) => _saveLocal(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_submitting ? '送信中...' : 'シフト送信'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _monthMemoController.dispose();
    super.dispose();
  }
}

/// Bottom sheet that lists registered employee names for the currently
/// selected department (in the order the admin registered them), so
/// staff can tap their own name instead of typing it. If a name isn't
/// in the list yet (e.g. a new hire not registered in time), staff can
/// tap "手入力する" to close the sheet and type their name directly in
/// the field - nothing is forced.
class _NamePickerSheet extends StatelessWidget {
  final String department;
  final List<Employee> roster;

  const _NamePickerSheet({required this.department, required this.roster});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$department の氏名一覧から選択',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDeep,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: roster.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'この部署にはまだ名簿が登録されていません。\n'
                        '下の欄にそのまま氏名を入力してください。',
                        style: TextStyle(color: AppColors.inkMute),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: roster.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final e = roster[index];
                        return ListTile(
                          title: Text(e.name),
                          onTap: () => Navigator.of(context).pop(e.name),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('一覧にない場合は手入力する'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet used by the bulk-input feature: lets the admin/staff pick
/// a single code (A~Y or 有) to apply to every currently-selected day at
/// once, or clear the selected days entirely. Returns the chosen code
/// string via Navigator.pop, or `_ShiftFormScreenState._bulkClearSentinel`
/// when "選択日をクリア" is chosen, or null if dismissed without a choice.
class _BulkApplySheet extends StatefulWidget {
  final int count;

  const _BulkApplySheet({required this.count});

  @override
  State<_BulkApplySheet> createState() => _BulkApplySheetState();
}

class _BulkApplySheetState extends State<_BulkApplySheet> {
  String? _code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '選択した${widget.count}日に一括で適用',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDeep,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _code,
            decoration: const InputDecoration(labelText: '記号（希望時間）'),
            hint: const Text('記号を選択'),
            items: [
              DropdownMenuItem(
                value: ShiftCode.paidLeaveCode,
                child: Text(
                  '${ShiftCode.paidLeaveCode} (${ShiftCode.paidLeaveFullLabel})',
                  style: const TextStyle(
                    color: AppColors.paidLeave,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...ShiftCode.codes.map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(ShiftCode.labelFor(e.key, e.value)),
                ),
              ),
            ],
            onChanged: (val) => setState(() => _code = val),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.clear),
              label: const Text('選択日の入力をクリア'),
              onPressed: () => Navigator.of(
                context,
              ).pop(_ShiftFormScreenState._bulkClearSentinel),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _code == null
                  ? null
                  : () => Navigator.of(context).pop(_code),
              child: const Text('適用'),
            ),
          ),
        ],
      ),
    );
  }
}
