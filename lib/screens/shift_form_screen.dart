import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../app_version.dart';
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
import 'monthly_shift_matrix_screen.dart';
import 'update_history_screen.dart';

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

  // Whether the app has been updated since this device last opened the
  // update-history screen - shows a red "NEW" badge next to the version
  // label so people actually notice updates instead of missing them.
  bool _hasNewUpdate = false;

  // Whether the salary-calculator card is expanded. Starts collapsed so
  // wage/salary info stays hidden if a coworker glances at this screen.
  bool _salaryExpanded = false;

  // Used to auto-scroll the salary card fully into view once it expands,
  // so the wage input + estimated salary are visible without the user
  // having to manually scroll down.
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _salaryCardKey = GlobalKey();

  // Live-updates the config (target month, holidays, deadline, notice,
  // and crucially `publishedDepartments`) so the "シフト配布" banner
  // appears immediately once an admin publishes - no pull-to-refresh or
  // app restart needed while this screen is open.
  StreamSubscription<AppConfig>? _configSub;
  // Tracks whether OUR department was published the last time we received
  // a config update, so we can detect the false -> true transition and
  // pop up a one-time notification (in addition to the persistent banner)
  // the moment the admin publishes - rather than relying on the banner
  // silently appearing, which is easy to miss.
  bool? _wasPublished;

  // Live-updates the list of shift submissions for the CURRENT department
  // + target month, so the "送信済み/未送信" status banner below always
  // reflects the true Firestore state (e.g. if staff submit from a
  // different device, or an admin deletes a submission) without needing
  // a manual refresh. Re-subscribed only when the department or target
  // month changes (NOT on every keystroke while typing a name) - the
  // actual name match against this list happens in [_mySubmission],
  // which re-evaluates on every build as the user types.
  StreamSubscription<List<ShiftSubmission>>? _submissionsSub;
  List<ShiftSubmission> _monthSubmissions = [];
  // Tracks the (department, targetMonth) pair we're currently subscribed
  // for, so we don't tear down/recreate the stream subscription on every
  // unrelated rebuild - only when one of these two actually changes.
  String? _submissionsSubKey;

  // 一括入力（bulk input）モード: 有効化すると日付セルをタップして
  // 複数選択でき、選択した日にまとめて同じ記号を適用できる。
  bool _bulkMode = false;
  final Set<String> _selectedDates = {};

  // 自分の給料計算（時給 x 今月の合計時間）用。時給は端末にのみ保存され、
  // Firestore（管理者側）には送信されない - あくまでパートさん本人が
  // 自分の給料を見積もるためのローカル機能。
  final TextEditingController _hourlyWageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final config = await _firestoreService.fetchConfig();
    _buildDays(config);
    await _restoreLocalState(config);
    await _loadWageForCurrentName();
    final lastSeen = await _localStorage.loadLastSeenVersion();
    if (lastSeen == null) {
      // First-ever visit on this device - there's nothing "new" to
      // compare against, so just record the current version as seen
      // and don't show the badge.
      await _localStorage.markVersionSeen(AppVersion.currentVersion);
    }
    _wasPublished = _selectedDepartment != null &&
        _selectedDepartment!.isNotEmpty &&
        config.isDepartmentPublished(_selectedDepartment!);
    setState(() {
      _config = config;
      _loading = false;
      // Show the "NEW" badge only if this device previously saw an
      // OLDER version than the one currently running.
      _hasNewUpdate = lastSeen != null && lastSeen != AppVersion.currentVersion;
    });
    // Start listening for real-time config changes AFTER the initial load
    // + local-state restore above have settled `_selectedDepartment`, so
    // the very first snapshot's publish-transition check (in
    // _onConfigUpdate) compares against the correct baseline instead of
    // a default/empty department.
    _configSub = _firestoreService.watchConfig().listen(_onConfigUpdate);
    _updateSubmissionsSubscription();
  }

  /// (Re)subscribes to a real-time stream of shift submissions for
  /// whichever (department, targetMonth) pair is currently active, so the
  /// "送信済み/未送信" status banner (see [_mySubmission]) always reflects
  /// the true Firestore state. No-ops if department or target month
  /// hasn't actually changed since the last subscription, so this can be
  /// called freely (e.g. from every _onConfigUpdate tick) without
  /// constantly tearing down and recreating the stream.
  void _updateSubmissionsSubscription() {
    final dept = _selectedDepartment;
    final month = _config?.targetMonth;
    if (dept == null || dept.isEmpty || month == null || month.isEmpty) {
      _submissionsSub?.cancel();
      _submissionsSub = null;
      _submissionsSubKey = null;
      if (_monthSubmissions.isNotEmpty) {
        setState(() => _monthSubmissions = []);
      }
      return;
    }
    final key = '$dept|$month';
    if (_submissionsSubKey == key) return; // already subscribed
    _submissionsSubKey = key;
    _submissionsSub?.cancel();
    _submissionsSub = _firestoreService
        .watchSubmissionsForMonth(month)
        .listen((list) {
          if (!mounted) return;
          setState(() {
            _monthSubmissions = list.where((s) => s.department == dept).toList();
          });
        });
  }

  /// This device's own submission for the currently-selected name +
  /// department + target month, if one exists in the live-streamed
  /// [_monthSubmissions] list - used to render the "送信済み/未送信"
  /// status banner. Name matching uses the same normalization as the PIN
  /// safety-net check in [_submit] (ignores whitespace/case differences),
  /// so e.g. "山田 太郎" typed with an extra space still matches.
  ShiftSubmission? get _mySubmission {
    final typedName = _nameController.text.trim();
    if (typedName.isEmpty) return null;
    final normalized = Employee.normalizeName(typedName);
    for (final s in _monthSubmissions) {
      if (Employee.normalizeName(s.name) == normalized) return s;
    }
    return null;
  }

  /// Called on every real-time config update (admin edits settings,
  /// toggles "シフト配布" for a department, etc.). Rebuilds the day grid
  /// only if the target month actually changed (to avoid clobbering the
  /// user's in-progress input on every unrelated config write), and shows
  /// a one-time SnackBar notification the moment OUR department's publish
  /// state flips from not-published to published - so the user finds out
  /// without needing to pull-to-refresh or notice the banner appearing.
  void _onConfigUpdate(AppConfig config) {
    if (!mounted) return;
    final monthChanged = _config != null && _config!.targetMonth != config.targetMonth;
    if (monthChanged) {
      _buildDays(config);
    }
    final nowPublished = _selectedDepartment != null &&
        _selectedDepartment!.isNotEmpty &&
        config.isDepartmentPublished(_selectedDepartment!);
    final justPublished = _wasPublished == false && nowPublished;
    setState(() {
      _config = config;
    });
    _wasPublished = nowPublished;
    if (justPublished) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('シフトが配布されました。下の「月間シフト一覧表を見る」から確認できます。'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    if (monthChanged) {
      // Target month changed (admin advanced to a new month) - re-point
      // the submissions stream at the new month so the 送信済み/未送信
      // banner reflects the new month instead of stale data.
      _updateSubmissionsSubscription();
    }
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
    _updateSubmissionsSubscription();
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
          _days[key]!.paidLeaveHours = v['paidLeaveHours']?.toString() ?? '';
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
  ///
  /// If the selected employee has a PIN set by the admin AND this device
  /// hasn't verified that name before, a PIN prompt is shown first (see
  /// _verifyPinFor). This is a one-time-per-device check, not a
  /// per-session login - once verified, this device will never be asked
  /// again for that name.
  Future<void> _openNamePicker() async {
    if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
      _showSnack('先に部署を選択すると、名前の一覧から選べます');
      return;
    }
    final roster = _employeesInSelectedDepartment;
    final picked = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          _NamePickerSheet(department: _selectedDepartment!, roster: roster),
    );
    if (picked == null || picked.name.isEmpty) return;

    final ok = await _verifyPinFor(picked);
    if (!ok) return;

    setState(() => _nameController.text = picked.name);
    _saveLocal();
    await _loadWageForCurrentName();
  }

  /// Loads this device's saved hourly wage for whichever name is
  /// currently in [_nameController] (if any was saved before), so the
  /// salary estimate keeps working across app restarts without the user
  /// needing to re-type their wage every time.
  Future<void> _loadWageForCurrentName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final wage = await _localStorage.loadHourlyWage(name);
    if (wage != null && mounted) {
      setState(() {
        _hourlyWageController.text = wage % 1 == 0
            ? wage.toInt().toString()
            : wage.toString();
      });
    }
  }

  /// Saves the currently-typed hourly wage to this device, tied to the
  /// currently-typed name. Called whenever the wage field changes.
  Future<void> _saveWage() async {
    final name = _nameController.text.trim();
    final wage = double.tryParse(_hourlyWageController.text.trim());
    if (name.isEmpty || wage == null) return;
    await _localStorage.saveHourlyWage(name, wage);
  }

  /// After expanding the salary calculator card, scroll it fully into
  /// view so the wage field and estimated salary are visible right away
  /// without the user having to manually scroll down.
  void _scrollSalaryCardIntoView() {
    // Wait for the expand animation (AnimatedSize, 200ms) to finish so the
    // card's final height is known before we measure/scroll to it.
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final ctx = _salaryCardKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: 1.0, // align the bottom of the card to the viewport
      );
    });
  }

  /// Sum of all hours counted toward the personal salary estimate: normal
  /// worked hours (from A〜Y codes) PLUS any user-entered paid-leave
  /// hours. This is intentionally separate from [_totalHours] (which
  /// feeds the admin-facing submission/summary) so that paid-leave time
  /// only affects this personal calculator, never the admin's records.
  double get _salaryHours {
    double total = 0;
    for (final d in _days.values) {
      final h = double.tryParse(d.hours);
      if (h != null) total += h;
      // Defensive check: only count paid-leave hours for days whose code
      // is actually '有'. This guards against stale paidLeaveHours values
      // left over from a day that was previously '有' and later changed/
      // cleared via some other path (e.g. bulk-apply, restored local
      // state from an older app version) without properly resetting it.
      if (ShiftCode.isPaidLeave(d.code)) {
        final pl = double.tryParse(d.paidLeaveHours);
        if (pl != null) total += pl;
      }
    }
    return total;
  }

  /// Estimated salary = hourly wage x [_salaryHours]. Returns null if no
  /// valid hourly wage has been entered yet.
  double? get _estimatedSalary {
    final wage = double.tryParse(_hourlyWageController.text.trim());
    if (wage == null) return null;
    return wage * _salaryHours;
  }

  /// Ensures the staff member selecting [employee]'s name is really them,
  /// by checking a 4-digit PIN the admin set for that person - but only
  /// the FIRST time this device selects that name. Returns true if it's
  /// OK to proceed (no PIN set, already verified on this device, or PIN
  /// just entered correctly); false if the user cancelled or entered the
  /// wrong PIN.
  Future<bool> _verifyPinFor(Employee employee) async {
    if (employee.pin.isEmpty) return true; // no PIN set by admin yet
    if (await _localStorage.isNameVerified(employee.name)) return true;
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PinEntryDialog(employee: employee),
    );
    if (result == true) {
      await _localStorage.markNameVerified(employee.name);
      return true;
    }
    return false;
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
            // Also clear any leftover paid-leave hours entered for the
            // salary calculator - otherwise bulk-clearing a day that was
            // previously '有' leaves stale hours counted toward the
            // personal salary estimate even though the day is now blank.
            entry.paidLeaveHours = '';
          } else {
            entry.code = code;
            final h = ShiftCode.hoursForCode(code);
            entry.hours = h != null ? h.toStringAsFixed(2) : '';
            // Bulk-applying a normal A〜Y code (not '有') also needs to
            // clear any previously-entered paid-leave hours for the same
            // reason as above - the day is no longer a paid-leave day.
            if (!ShiftCode.isPaidLeave(code)) {
              entry.paidLeaveHours = '';
            }
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

  /// True once today's date (device-local) is AFTER the admin-configured
  /// [AppConfig.deadline] day. The deadline day itself still counts as
  /// "before/at the deadline" (inclusive) - only once the calendar date
  /// has moved past it does submission get blocked. An empty deadline
  /// means the admin hasn't set one, so it never blocks submission.
  bool get _isPastDeadline {
    final deadline = _config?.deadline;
    if (deadline == null || deadline.isEmpty) return false;
    final parts = deadline.split('-');
    if (parts.length != 3) return false;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return false;
    final deadlineDate = DateTime(y, m, d);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.isAfter(deadlineDate);
  }

  static const String _bulkClearSentinel = '__clear__';

  Future<void> _submit() async {
    if (_isPastDeadline) {
      _showSnack('受付締切（${_config?.deadline}）を過ぎているため、送信できません');
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _showSnack('氏名を入力してください');
      return;
    }
    if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
      _showSnack('部署を選択してください');
      return;
    }

    // Confirm before actually submitting - this button sits near the
    // hourly-wage field for the salary calculator, so a confirmation
    // step helps prevent accidental taps while typing/editing wage info.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('シフトを送信しますか？'),
        content: Text(
          '${_nameController.text.trim()}さん（$_selectedDepartment）の'
          '${_fmtMonthJp(_config?.targetMonth ?? '')}のシフト希望を送信します。'
          'よろしいですか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('送信する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Safety net: even if the name was typed by hand (not picked from the
    // roster list), if it matches a registered employee with a PIN set,
    // still require PIN verification before submitting - otherwise
    // someone could bypass the picker's PIN check by just typing the
    // name themselves.
    final typedName = _nameController.text.trim();
    Employee? match;
    for (final e in _employeesInSelectedDepartment) {
      if (Employee.normalizeName(e.name) == Employee.normalizeName(typedName)) {
        match = e;
        break;
      }
    }
    if (match != null) {
      final ok = await _verifyPinFor(match);
      if (!ok) return;
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

  /// Opens the admin-published monthly shift matrix in read-only mode, so
  /// part-time staff can see their OWN department's confirmed shift for
  /// the target month. Publishing is per-department (each department has
  /// its own admin/manager), so this fetches the full submission list for
  /// the month, then narrows both the submissions AND the department-tab
  /// list down to just [_selectedDepartment] - staff cannot switch tabs
  /// to view other departments' shift matrices. There's a brief loading
  /// spinner while the fetch request is in flight.
  Future<void> _openMonthlyMatrix() async {
    if (_config == null) return;
    final dept = _selectedDepartment;
    if (dept == null || dept.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
    try {
      final allSubmissions = await _firestoreService.fetchSubmissionsForMonth(
        _config!.targetMonth,
      );
      final submissions = allSubmissions
          .where((s) => s.department == dept)
          .toList();
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MonthlyShiftMatrixScreen(
            submissions: submissions,
            targetMonth: _config!.targetMonth,
            availableDepartments: [dept],
            initialDepartment: dept,
            employees: _config!.employees,
            readOnly: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      _showSnack('一覧表の取得に失敗しました');
    }
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

  /// Short label for the compact "送信ステータス" row inside the summary
  /// stat card (see [SummaryCard.submissionStatusLabel]) - intentionally
  /// terse ("送信済み" / "未送信" / "再提出2回") rather than a full
  /// sentence, since it now shares space with the 2x2 stat grid instead
  /// of being its own full-width banner. Backed by [_mySubmission],
  /// which is kept in sync in real time via [_submissionsSub].
  /// Returns null if no name/department has been entered yet, meaning
  /// there's nothing meaningful to check submission status against.
  String? get _submissionStatusLabel {
    if (_selectedDepartment == null ||
        _selectedDepartment!.isEmpty ||
        _nameController.text.trim().isEmpty) {
      return null;
    }
    final submission = _mySubmission;
    if (submission == null) return '未送信';
    if (submission.isResubmission) {
      return '再提出${submission.submissionCount - 1}回';
    }
    return '送信済み';
  }

  /// Color paired with [_submissionStatusLabel] - orange for "未送信",
  /// the app's success-green for anything already submitted.
  Color get _submissionStatusColor {
    return _mySubmission == null ? Colors.orange : AppColors.success;
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
        titleSpacing: 16,
        toolbarHeight: 64,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_fmtMonthJp(config.targetMonth)} シフト希望',
                      maxLines: 1,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 1),
                  // Small, unobtrusive version label - tap to see full
                  // update history (date + what changed for each
                  // version). A red "NEW" dot appears whenever a version
                  // newer than the one this device last opened is
                  // available, so updates don't go unnoticed.
                  InkWell(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const UpdateHistoryScreen(),
                        ),
                      );
                      await _localStorage.markVersionSeen(
                        AppVersion.currentVersion,
                      );
                      if (mounted) setState(() => _hasNewUpdate = false);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ver${AppVersion.currentVersion}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                          if (_hasNewUpdate) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使い方ガイド',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HelpScreen()));
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
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectedDepartment != null &&
                          _selectedDepartment!.isNotEmpty &&
                          config.isDepartmentPublished(_selectedDepartment!))
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _openMonthlyMatrix,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.table_chart_outlined,
                                      color: AppColors.success,
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'シフトが確定しました。月間シフト一覧表を見る',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppColors.success,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (config.notice.isNotEmpty ||
                          config.deadline.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            // Turn the whole notice box red once past the
                            // deadline, so staff notice immediately why
                            // the submit button below is now disabled -
                            // rather than just quietly failing.
                            color: (_isPastDeadline
                                    ? Colors.red
                                    : AppColors.primary)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (config.deadline.isNotEmpty)
                                Text(
                                  _isPastDeadline
                                      ? '受付締切: ${config.deadline}（受付終了しました）'
                                      : '受付締切: ${config.deadline}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _isPastDeadline
                                        ? Colors.red
                                        : AppColors.primaryDeep,
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
                                  // Re-baseline the publish-transition tracker
                                  // for the newly selected department, so
                                  // switching TO an already-published
                                  // department doesn't spuriously trigger the
                                  // "配布されました" SnackBar on the next
                                  // unrelated config update.
                                  _wasPublished = _config != null &&
                                      val != null &&
                                      val.isNotEmpty &&
                                      _config!.isDepartmentPublished(val);
                                  // Re-point the submissions stream at the
                                  // newly selected department, so the
                                  // 送信済み/未送信 banner checks the right
                                  // department's data.
                                  _updateSubmissionsSubscription();
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
                                onChanged: (_) {
                                  // setState so the 送信済み/未送信 status
                                  // banner (which matches against
                                  // _nameController.text) re-evaluates as
                                  // the user types, not just when a name
                                  // is picked from the roster sheet.
                                  setState(() {});
                                  _saveLocal();
                                  _loadWageForCurrentName();
                                },
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
                                submissionStatusLabel: _submissionStatusLabel,
                                submissionStatusColor: _submissionStatusColor,
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
                      Card(
                        key: _salaryCardKey,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Tap the header to expand/collapse the salary
                              // calculator. Kept collapsed by default so
                              // wage/salary info isn't visible at a glance if
                              // a coworker happens to see this screen.
                              InkWell(
                                onTap: () {
                                  setState(
                                    () => _salaryExpanded = !_salaryExpanded,
                                  );
                                  if (_salaryExpanded) {
                                    _scrollSalaryCardIntoView();
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          '自分の給料計算（任意）',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryDeep,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        _salaryExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color: AppColors.primaryDeep,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                alignment: Alignment.topCenter,
                                child: _salaryExpanded
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 8),
                                          const Text(
                                            '時給を入力すると、今月の希望時間から給料を自動計算します。'
                                            '入力した時給はこの端末にのみ保存され、管理者には送信されません。',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.inkMute,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          TextField(
                                            controller: _hourlyWageController,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: '時給',
                                              hintText: '例：1200',
                                              suffixText: '円',
                                            ),
                                            onChanged: (_) {
                                              setState(() {});
                                              _saveWage();
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: AppColors.background,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: AppColors.line,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Text(
                                                      '対象時間（労働＋有給）',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            AppColors.inkMute,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      '${_salaryHours.toStringAsFixed(2)} h',
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: AppColors.ink,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    const Text(
                                                      '今月の給料（見積り）',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: AppColors
                                                            .primaryDeep,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      _estimatedSalary != null
                                                          ? '${_estimatedSalary!.toStringAsFixed(0)} 円'
                                                          : '時給を入力してください',
                                                      style: TextStyle(
                                                        fontSize:
                                                            _estimatedSalary !=
                                                                null
                                                            ? 20
                                                            : 13,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            _estimatedSalary !=
                                                                null
                                                            ? AppColors
                                                                  .primaryDeep
                                                            : AppColors
                                                                  .inkMute,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            '※有給（有）の日は、日付をタップして時間を入力すると'
                                            '給料計算に含まれます。',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.inkMute,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox(
                                        width: double.infinity,
                                        height: 0,
                                      ),
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
                  // Disabled entirely once past the admin-set deadline -
                  // prevents submission client-side rather than just
                  // discouraging it, since staff could otherwise ignore
                  // the notice text and tap through anyway.
                  onPressed: (_submitting || _isPastDeadline)
                      ? null
                      : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isPastDeadline ? Icons.lock_outline : Icons.send,
                        ),
                  label: Text(
                    _submitting
                        ? '送信中...'
                        : (_isPastDeadline ? '受付終了しました' : 'シフト送信'),
                  ),
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
    _configSub?.cancel();
    _submissionsSub?.cancel();
    _nameController.dispose();
    _monthMemoController.dispose();
    _hourlyWageController.dispose();
    _scrollController.dispose();
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
                          trailing: e.pin.isNotEmpty
                              ? const Icon(
                                  Icons.lock_outline,
                                  size: 16,
                                  color: AppColors.inkMute,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(e),
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

/// Dialog that asks the user to enter [employee]'s 4-digit PIN, shown only
/// the first time this device selects that person's name (see
/// _ShiftFormScreenState._verifyPinFor). Returns true via Navigator.pop if
/// the correct PIN was entered, false/null otherwise. If the PIN is wrong,
/// shows an inline error and lets the user retry without closing.
class _PinEntryDialog extends StatefulWidget {
  final Employee employee;

  const _PinEntryDialog({required this.employee});

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final TextEditingController _pinController = TextEditingController();
  String? _error;

  void _confirm() {
    if (_pinController.text.trim() == widget.employee.pin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'PINが正しくありません');
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.primaryDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.employee.name} さんの確認',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本人確認のため、4桁のPINを入力してください。\n'
            '（この端末では次回から不要になります）',
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 4),
          const Text(
            'PINが分からない場合は管理者にご確認ください。',
            style: TextStyle(fontSize: 11, color: AppColors.inkMute),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('確認')),
      ],
    );
  }
}
