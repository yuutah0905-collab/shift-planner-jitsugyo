import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/day_entry.dart';
import '../models/employee.dart';

/// Handles local persistence of the in-progress shift form
/// so users don't lose data if they close the app before submitting.
class LocalStorageService {
  static const _key = 'shift_form_state_v1';
  static const _verifiedNamesKey = 'pin_verified_names_v1';
  // Hourly wage is stored per-employee-name on this device only. It is
  // the staff member's own private wage info, never sent to Firestore /
  // visible to admins - used solely by the personal salary calculator
  // on the shift-request screen.
  static const _hourlyWageKey = 'hourly_wage_v1';
  // Tracks which app version this device has last "seen" (i.e. opened
  // the update-history screen for), so we can show a "NEW" badge next
  // to the version label whenever a newer version is deployed.
  static const _lastSeenVersionKey = 'last_seen_app_version_v1';

  Future<void> saveState({
    required String name,
    required String department,
    required String monthMemo,
    required Map<String, DayEntry> days,
    required String targetMonth,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'name': name,
      'department': department,
      'monthMemo': monthMemo,
      'targetMonth': targetMonth,
      'days': days.map((k, v) => MapEntry(k, v.toMap())),
    };
    await prefs.setString(_key, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Marks [employeeName] (normalized) as PIN-verified on this device, so
  /// future name selections skip the PIN prompt - PIN verification is a
  /// one-time-per-device check, not a per-session login.
  Future<void> markNameVerified(String employeeName) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_verifiedNamesKey) ?? []).toSet();
    set.add(Employee.normalizeName(employeeName));
    await prefs.setStringList(_verifiedNamesKey, set.toList());
  }

  /// Whether [employeeName] (normalized) has already been PIN-verified on
  /// this device.
  Future<bool> isNameVerified(String employeeName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_verifiedNamesKey) ?? [];
    return list.contains(Employee.normalizeName(employeeName));
  }

  /// Saves [hourlyWage] (yen per hour) for [employeeName] on this device
  /// only. Stored per-name so that if multiple people share a device,
  /// each person's wage stays separate. Never synced to Firestore.
  Future<void> saveHourlyWage(String employeeName, double hourlyWage) async {
    if (employeeName.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hourlyWageKey);
    final Map<String, dynamic> map = raw != null
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : {};
    map[Employee.normalizeName(employeeName)] = hourlyWage;
    await prefs.setString(_hourlyWageKey, jsonEncode(map));
  }

  /// Loads the previously-saved hourly wage for [employeeName] on this
  /// device, or null if none has been saved yet.
  Future<double?> loadHourlyWage(String employeeName) async {
    if (employeeName.trim().isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hourlyWageKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final v = map[Employee.normalizeName(employeeName)];
      if (v == null) return null;
      return (v is num) ? v.toDouble() : double.tryParse(v.toString());
    } catch (_) {
      return null;
    }
  }

  /// The app version this device last acknowledged (opened the update
  /// history screen for). Returns null if never opened before (e.g. a
  /// brand-new device/browser).
  Future<String?> loadLastSeenVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSeenVersionKey);
  }

  /// Marks [version] as seen on this device, so the "NEW" badge for it
  /// (and older versions) stops showing.
  Future<void> markVersionSeen(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenVersionKey, version);
  }
}
