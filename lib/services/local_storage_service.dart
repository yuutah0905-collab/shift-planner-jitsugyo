import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/day_entry.dart';

/// Handles local persistence of the in-progress shift form
/// so users don't lose data if they close the app before submitting.
class LocalStorageService {
  static const _key = 'shift_form_state_v1';

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
}
