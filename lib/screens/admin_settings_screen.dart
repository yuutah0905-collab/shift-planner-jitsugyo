import 'dart:math';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'admin_help_screen.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _noticeController = TextEditingController();
  final TextEditingController _deptInputController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _empNameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // 対象年月
  int _targetYear = DateTime.now().year;
  int _targetMonth = DateTime.now().month;

  // 提出締切
  DateTime? _deadline;

  // 休業日カレンダー表示中の年月（対象年月と別に前後移動できる）
  int _calYear = DateTime.now().year;
  int _calMonth = DateTime.now().month;

  List<String> _holidays = [];
  List<String> _departments = [];
  List<Employee> _employees = [];
  String? _empDept;

  static const List<String> _dow = ['日', '月', '火', '水', '木', '金', '土'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _noticeController.dispose();
    _deptInputController.dispose();
    _passwordController.dispose();
    _empNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _firestoreService.fetchConfig();
      final parts = config.targetMonth.split('-');
      if (parts.length == 2) {
        _targetYear = int.tryParse(parts[0]) ?? _targetYear;
        _targetMonth = int.tryParse(parts[1]) ?? _targetMonth;
      }
      _calYear = _targetYear;
      _calMonth = _targetMonth;
      if (config.deadline.isNotEmpty) {
        final dParts = config.deadline.split('-');
        if (dParts.length == 3) {
          _deadline = DateTime(
            int.tryParse(dParts[0]) ?? _targetYear,
            int.tryParse(dParts[1]) ?? 1,
            int.tryParse(dParts[2]) ?? 1,
          );
        }
      }
      _noticeController.text = config.notice;
      _passwordController.text = config.adminPassword;
      _holidays = List<String>.from(config.holidays);
      _departments = List<String>.from(config.departments);
      _employees = List<Employee>.from(config.employees);
      // 既存メンバーでPINが未設定の人には、考える手間をなくすため
      // 自動でランダムな4桁PINを割り当てる（保存を押すまでは確定しない）。
      final missing = _employees.where((e) => e.pin.isEmpty).length;
      if (missing > 0) {
        _employees = _employees
            .map(
              (e) => e.pin.isEmpty
                  ? Employee(
                      name: e.name,
                      department: e.department,
                      pin: _generateRandomPin(),
                    )
                  : e,
            )
            .toList();
      }
      _empDept = _departments.isNotEmpty ? _departments.first : null;
      setState(() => _loading = false);
      if (missing > 0 && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PIN未設定だった$missing名に自動でランダムなPINを設定しました。保存すると確定します。',
              ),
            ),
          );
        });
      }
    } catch (e) {
      setState(() {
        _error = '設定の取得に失敗しました';
        _loading = false;
      });
    }
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
  String get _targetMonthStr =>
      '${_targetYear.toString().padLeft(4, '0')}-${_pad2(_targetMonth)}';
  String get _deadlineStr => _deadline == null
      ? ''
      : '${_deadline!.year.toString().padLeft(4, '0')}-${_pad2(_deadline!.month)}-${_pad2(_deadline!.day)}';

  void _shiftTargetMonth(int delta) {
    setState(() {
      int m = _targetMonth + delta;
      int y = _targetYear;
      if (m < 1) {
        m = 12;
        y -= 1;
      } else if (m > 12) {
        m = 1;
        y += 1;
      }
      _targetMonth = m;
      _targetYear = y;
    });
  }

  void _shiftCalMonth(int delta) {
    setState(() {
      int m = _calMonth + delta;
      int y = _calYear;
      if (m < 1) {
        m = 12;
        y -= 1;
      } else if (m > 12) {
        m = 1;
        y += 1;
      }
      _calMonth = m;
      _calYear = y;
    });
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(_targetYear, _targetMonth, 1),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _deadline = picked);
    }
  }

  void _toggleHoliday(String key) {
    setState(() {
      if (_holidays.contains(key)) {
        _holidays.remove(key);
      } else {
        _holidays.add(key);
      }
    });
  }

  void _clearHolidays() {
    setState(() => _holidays.clear());
  }

  void _addDepartment() {
    final v = _deptInputController.text.trim();
    if (v.isEmpty) return;
    if (_departments.contains(v)) {
      _deptInputController.clear();
      return;
    }
    setState(() {
      _departments.add(v);
      _deptInputController.clear();
    });
  }

  void _removeDepartment(String v) {
    setState(() => _departments.remove(v));
  }

  /// ランダムな4桁PIN（0000〜9999）を生成する。既存の従業員PINと重複しないよう
  /// になるべく配慮するが、万一重複しても本人名で識別するため実害はない。
  String _generateRandomPin() {
    final rnd = Random();
    String pin;
    var attempts = 0;
    do {
      pin = rnd.nextInt(10000).toString().padLeft(4, '0');
      attempts++;
    } while (_employees.any((e) => e.pin == pin) && attempts < 20);
    return pin;
  }

  void _addEmployee() {
    final v = _empNameController.text.trim();
    if (v.isEmpty) return;
    final dept =
        _empDept ?? (_departments.isNotEmpty ? _departments.first : '');
    final normalizedV = Employee.normalizeName(v);
    if (_employees.any(
      (e) =>
          Employee.normalizeName(e.name) == normalizedV && e.department == dept,
    )) {
      _empNameController.clear();
      return;
    }
    setState(() {
      // 追加時に自動でランダムPINを割り当てる（管理者が個別に考える必要をなくす）。
      _employees.add(
        Employee(name: v, department: dept, pin: _generateRandomPin()),
      );
      _empNameController.clear();
    });
  }

  void _removeEmployee(Employee e) {
    setState(() => _employees.remove(e));
  }

  /// Reorders the roster when the admin drags a row to a new position.
  /// This list order is what drives the "登録順" sorting used on the
  /// 月間シフト一覧表 / 日別出勤状況 screens (see [_buildRosterOrder] in
  /// those screens), so dragging here directly changes the display order
  /// shown to the admin elsewhere once saved.
  void _reorderEmployee(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _employees.removeAt(oldIndex);
      _employees.insert(newIndex, item);
    });
  }

  /// Opens a dialog to view the current PIN (masked, revealable) and/or
  /// set a new 4-digit PIN for [employee]. Used both for initial PIN
  /// setup on existing rosters and for "PINを忘れた" resets.
  Future<void> _editEmployeePin(Employee employee) async {
    final controller = TextEditingController(text: employee.pin);
    bool obscure = employee.pin.isEmpty ? false : true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('${employee.name} さんのPIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'パートさんが名前を初めて選ぶ際に入力する4桁の確認番号です。\n'
                '本人がPINを忘れた場合は、ここで確認・再設定できます。',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 6),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '未設定',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final newPin = _generateRandomPin();
                    controller.text = newPin;
                    setDialogState(() => obscure = false);
                  },
                  icon: const Icon(Icons.casino_outlined, size: 16),
                  label: const Text('ランダムに再生成'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isNotEmpty &&
                    (v.length != 4 || int.tryParse(v) == null)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('PINは4桁の数字で入力してください')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      final idx = _employees.indexOf(employee);
      if (idx != -1) {
        _employees[idx] = Employee(
          name: employee.name,
          department: employee.department,
          pin: result,
        );
      }
    });
  }

  int get _holidayCountThisCalMonth {
    final prefix =
        '${_calYear.toString().padLeft(4, '0')}-${_pad2(_calMonth)}-';
    return _holidays.where((h) => h.startsWith(prefix)).length;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config = AppConfig(
        targetMonth: _targetMonthStr,
        holidays: _holidays,
        deadline: _deadlineStr,
        notice: _noticeController.text.trim(),
        departments: _departments,
        adminPassword: _passwordController.text.trim().isEmpty
            ? 'shift2024'
            : _passwordController.text.trim(),
        employees: _employees,
      );
      await _firestoreService.updateConfig(config);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('設定を保存しました')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('シフト希望表 設定'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使い方ガイド・ヘルプ',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminHelpScreen()),
              );
            },
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
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _sectionCard(
                    title: '① 対象年月',
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => _shiftTargetMonth(-1),
                        ),
                        Expanded(
                          child: Text(
                            '$_targetYear年$_targetMonth月',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDeep,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => _shiftTargetMonth(1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: '② 提出締切・案内文',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickDeadline,
                          icon: const Icon(Icons.event),
                          label: Text(
                            _deadline == null
                                ? '締切日を選択'
                                : '締切: ${_deadline!.year}年${_deadline!.month}月${_deadline!.day}日',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noticeController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'パートさんへの案内文（任意）',
                            hintText: '例：今月分は月末までに提出してください',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: '③ 部署一覧',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _departments
                              .map(
                                (d) => Chip(
                                  label: Text(d),
                                  onDeleted: () => _removeDepartment(d),
                                  backgroundColor: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  labelStyle: const TextStyle(
                                    color: AppColors.primaryDeep,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _deptInputController,
                                decoration: const InputDecoration(
                                  labelText: '部署を追加',
                                  hintText: '例：出庫',
                                ),
                                onSubmitted: (_) => _addDepartment(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _addDepartment,
                              child: const Text('追加'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: '④ 休業日（タップで切替）',
                    child: _buildHolidayCalendar(),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: '⑤ 管理者パスワード',
                    child: TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: '管理者ログインパスワード',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: '⑥ 従業員名簿（未提出者チェック用）',
                    child: _buildEmployeeRoster(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('設定を保存'),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
      ),
    );
  }

  Widget _buildEmployeeRoster() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ここに登録した人が「提出済みかどうか」の一覧チェック対象になります。\n'
          'PINを設定すると、その人が初めて名前を選ぶ端末で本人確認が入り、'
          'なりすまし提出を防げます（PINは鍵アイコンから確認・変更できます）。\n'
          '右端の「☰」を長押し・ドラッグすると並び順を変更できます（月間シフト一覧表・'
          '日別出勤状況の表示順に反映されます）。',
          style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 10),
        if (_employees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'まだ従業員が登録されていません',
              style: TextStyle(fontSize: 12, color: AppColors.inkMute),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _reorderEmployee,
            itemCount: _employees.length,
            itemBuilder: (context, index) {
              final e = _employees[index];
              return Container(
                key: ValueKey('${e.name}_${e.department}'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (e.department.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          e.department,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primaryDeep,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        e.pin.isNotEmpty
                            ? Icons.lock
                            : Icons.lock_open_outlined,
                        size: 18,
                        color: e.pin.isNotEmpty
                            ? AppColors.primaryDeep
                            : AppColors.inkMute,
                      ),
                      tooltip: 'PINを確認・設定',
                      onPressed: () => _editEmployeePin(e),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _removeEmployee(e),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 6),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Icon(
                        Icons.drag_handle,
                        size: 20,
                        color: AppColors.inkMute,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _empNameController,
                decoration: const InputDecoration(
                  labelText: '氏名を追加',
                  hintText: '例：山田太郎',
                ),
                onSubmitted: (_) => _addEmployee(),
              ),
            ),
            const SizedBox(width: 8),
            if (_departments.isNotEmpty)
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _departments.contains(_empDept)
                      ? _empDept
                      : null,
                  decoration: const InputDecoration(labelText: '部署'),
                  items: _departments
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setState(() => _empDept = v),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '※ PINは追加時に自動でランダムな4桁が割り当てられます（鍵アイコンから確認・変更できます）。',
          style: TextStyle(fontSize: 11, color: AppColors.inkMute),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addEmployee,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('従業員を追加'),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDeep,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildHolidayCalendar() {
    final firstWeekday = DateTime(_calYear, _calMonth, 1).weekday % 7; // Sun=0
    final lastDay = DateTime(_calYear, _calMonth + 1, 0).day;
    final totalCells = firstWeekday + lastDay;
    final rows = (totalCells / 7).ceil();
    final cellCount = rows * 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftCalMonth(-1),
            ),
            Expanded(
              child: Text(
                '$_calYear年$_calMonth月',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shiftCalMonth(1),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '設定 ${_holidays.length}件 ／ 当月 $_holidayCountThisCalMonth件',
              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
            TextButton(
              onPressed: _holidays.isEmpty ? null : _clearHolidays,
              child: const Text('全消去', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (int i = 0; i < 7; i++)
              Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _dow[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: i == 0
                        ? AppColors.sun
                        : i == 6
                        ? AppColors.sat
                        : AppColors.inkMute,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (int i = 0; i < cellCount; i++)
              _buildDayCell(i, firstWeekday, lastDay),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legend(AppColors.surface, '通常', border: true),
            _legend(AppColors.primary.withValues(alpha: 0.18), '休業日'),
            _legend(AppColors.weekendBg, '土日'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color color, String label, {bool border = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: border ? Border.all(color: AppColors.line) : null,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
        ),
      ],
    );
  }

  Widget _buildDayCell(int index, int firstWeekday, int lastDay) {
    final dayNum = index - firstWeekday + 1;
    if (dayNum < 1 || dayNum > lastDay) {
      return const SizedBox.shrink();
    }
    final dow = (firstWeekday + dayNum - 1) % 7;
    final isWeekend = dow == 0 || dow == 6;
    final key =
        '${_calYear.toString().padLeft(4, '0')}-${_pad2(_calMonth)}-${_pad2(dayNum)}';
    final isHoliday = _holidays.contains(key);

    Color bg = AppColors.surface;
    if (isHoliday) {
      bg = AppColors.primary.withValues(alpha: 0.18);
    } else if (isWeekend) {
      bg = AppColors.weekendBg;
    }

    return InkWell(
      onTap: () => _toggleHoliday(key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '$dayNum',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: dow == 0
                ? AppColors.sun
                : dow == 6
                ? AppColors.sat
                : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
