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
  // Per-department "シフト配布" (publish) state: department name -> the
  // "YYYY-MM" target month whose completed monthly shift matrix the
  // admin has published for that department's part-time staff to view
  // from their own shift-request screen. A department not present in
  // this map (or whose value != the current `targetMonth`) is treated
  // as not published. Kept per-department (rather than one app-wide
  // flag) because each department has its own admin/manager who
  // publishes independently of the others.
  final Map<String, String> publishedDepartments;

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
    publishedDepartments:
        (map['publishedDepartments'] as Map<dynamic, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
  );

  AppConfig copyWith({
    String? targetMonth,
    List<String>? holidays,
    String? deadline,
    String? notice,
    List<String>? departments,
    String? adminPassword,
    List<Employee>? employees,
    Map<String, String>? publishedDepartments,
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
  /// published for THIS config's `targetMonth` (i.e. still current, not
  /// a stale publish left over from a previous target month).
  bool isDepartmentPublished(String department) =>
      publishedDepartments[department] == targetMonth &&
      targetMonth.isNotEmpty;

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
