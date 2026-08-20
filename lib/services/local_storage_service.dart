import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/day_entry.dart';
import '../models/employee.dart';

/// Handles local persistence of the in-progress shift form
/// so users don't lose data if they close the app before submitting.
class LocalStorageService {
  static const _key = 'shift_form_state_v1';
  static const _verifiedNamesKey = 'pin_verified_names_v1';

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
}
