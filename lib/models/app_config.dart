import 'employee.dart';

/// Represents the app-wide configuration set by admin (app_settings/config)
class AppConfig {
  final String targetMonth; // "YYYY-MM"
  final List<String> holidays; // list of "YYYY-MM-DD"
  final String deadline; // "YYYY-MM-DD"
  final String notice;
  final List<String> departments;
  final String adminPassword;
  // Registered employee roster (name + department), used to compute
  // who has NOT yet submitted their shift request for the target month.
  // Optional feature: if empty, the "未提出者" admin section is hidden.
  final List<Employee> employees;
  // Per-department "シフト配布" (publish) history: department name -> the
  // list of "YYYY-MM" target months whose completed monthly shift matrix
  // the admin has published for that department's part-time staff to
  // view from their own shift-request screen. Unlike a single "currently
  // published month" flag, this is a HISTORY - once a month is published
  // it stays in the list (so staff can always look it up later via the
  // "シフト確認" button), even after the admin advances `targetMonth` to
  // a new month. The persistent on-screen banner (which announces the
  // CURRENT month's shift as newly confirmed) still only shows for the
  // one month that equals `targetMonth` - see [isDepartmentPublished] -
  // it naturally disappears once the admin moves on to the next month,
  // even though that past month's entry is never removed from this list.
  // Kept per-department (rather than one app-wide list) because each
  // department has its own admin/manager who publishes independently of
  // the others.
  final Map<String, List<String>> publishedDepartments;

  AppConfig({
    required this.targetMonth,
    required this.holidays,
    required this.deadline,
    required this.notice,
    required this.departments,
    required this.adminPassword,
    this.employees = const [],
    this.publishedDepartments = const {},
  });

  factory AppConfig.fromMap(Map<String, dynamic> map) => AppConfig(
    targetMonth: map['targetMonth']?.toString() ?? '',
    holidays: (map['holidays'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    deadline: map['deadline']?.toString() ?? '',
    notice: map['notice']?.toString() ?? '',
    departments: (map['departments'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    adminPassword: map['adminPassword']?.toString() ?? '',
    employees: (map['employees'] as List<dynamic>? ?? [])
        .map((e) => Employee.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    publishedDepartments: _parsePublishedDepartments(
      map['publishedDepartments'],
    ),
  );

  /// Parses the `publishedDepartments` field, supporting BOTH the current
  /// shape (department -> list of "YYYY-MM" months) and the OLD shape
  /// from before the "past published shifts" history feature (department
  /// -> a single "YYYY-MM" string) - so existing Firestore data written
  /// by an older app version doesn't get silently dropped/crash on load.
  /// A single old-style string value is simply wrapped into a one-element
  /// list.
  static Map<String, List<String>> _parsePublishedDepartments(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, List<String>>{};
    raw.forEach((k, v) {
      final key = k.toString();
      if (v is List) {
        result[key] = v.map((e) => e.toString()).toList();
      } else if (v != null) {
        // Old shape: a single "YYYY-MM" string.
        final month = v.toString();
        if (month.isNotEmpty) result[key] = [month];
      }
    });
    return result;
  }

  AppConfig copyWith({
    String? targetMonth,
    List<String>? holidays,
    String? deadline,
    String? notice,
    List<String>? departments,
    String? adminPassword,
    List<Employee>? employees,
    Map<String, List<String>>? publishedDepartments,
  }) {
    return AppConfig(
      targetMonth: targetMonth ?? this.targetMonth,
      holidays: holidays ?? this.holidays,
      deadline: deadline ?? this.deadline,
      notice: notice ?? this.notice,
      departments: departments ?? this.departments,
      adminPassword: adminPassword ?? this.adminPassword,
      employees: employees ?? this.employees,
      publishedDepartments: publishedDepartments ?? this.publishedDepartments,
    );
  }

  /// True if [department] currently has its monthly shift matrix
  /// published for THIS config's `targetMonth` (i.e. the CURRENT month
  /// is in that department's publish history) - used to show the
  /// persistent "〇〇月のシフトが確定しました" banner. This intentionally
  /// does NOT reflect past months still sitting in the publish history -
  /// those are only reachable via the "シフト確認" button/screen (see
  /// [publishedMonthsFor]), so the banner naturally disappears once the
  /// admin advances to a new target month even though the previous
  /// month's entry is kept for history.
  bool isDepartmentPublished(String department) =>
      targetMonth.isNotEmpty &&
      (publishedDepartments[department] ?? const []).contains(targetMonth);

  /// All "YYYY-MM" months ever published for [department], newest first -
  /// used by the "シフト確認" screen so part-time staff can look up any
  /// past confirmed shift, not just the current month's.
  List<String> publishedMonthsFor(String department) {
    final months = List<String>.from(publishedDepartments[department] ?? const []);
    months.sort((a, b) => b.compareTo(a)); // "YYYY-MM" sorts lexically = chronologically
    return months;
  }

  static AppConfig fallback() {
    final now = DateTime.now();
    final nextMonth = now.month == 12
        ? DateTime(now.year + 1, 1)
        : DateTime(now.year, now.month + 1);
    final ym =
        '${nextMonth.year.toString().padLeft(4, '0')}-${nextMonth.month.toString().padLeft(2, '0')}';
    return AppConfig(
      targetMonth: ym,
      holidays: [],
      deadline: '',
      notice: '',
      departments: ['出庫', '入庫', '小分け', '梱包', 'その他'],
      adminPassword: 'shift2024',
      employees: [],
      publishedDepartments: {},
    );
  }
}
