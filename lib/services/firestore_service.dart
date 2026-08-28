import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import '../models/shift_submission.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetch app-wide config (target month, holidays, deadline, notice, etc.)
  ///
  /// IMPORTANT: bounded with a timeout. Without one, a flaky/unreachable
  /// network path to the Firestore backend (which uses a long-lived
  /// WebChannel/streaming connection, not a plain quick HTTP request) can
  /// leave the returned Future neither resolved nor rejected for a very
  /// long time - which showed up as the app being stuck on the loading
  /// splash screen forever, since the try/catch here never even got a
  /// chance to run (nothing was thrown yet, the await just never returned).
  Future<AppConfig> fetchConfig() async {
    try {
      final doc = await _db
          .collection('app_settings')
          .doc('config')
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      if (doc.exists && doc.data() != null) {
        return AppConfig.fromMap(doc.data()!);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchConfig error: $e');
    }
    return AppConfig.fallback();
  }

  /// Submit a shift request to Firestore
  Future<void> submitShift(ShiftSubmission submission) async {
    final data = submission.toMap();
    data['submittedAt'] = FieldValue.serverTimestamp();
    await _db.collection('shift_submissions').add(data);
  }

  /// Fetch all shift submissions for a given target month (admin view)
  /// Uses a simple query (no orderBy) then sorts in memory to avoid
  /// composite index requirements. Multiple submissions from the same
  /// person/department/month are grouped: only the newest is returned
  /// at the top level, with older ones nested in `previousVersions` so
  /// admins can see resubmission history without duplicate list rows.
  Future<List<ShiftSubmission>> fetchSubmissionsForMonth(
    String targetMonth,
  ) async {
    final querySnapshot = await _db
        .collection('shift_submissions')
        .where('targetMonth', isEqualTo: targetMonth)
        .get();

    final list = querySnapshot.docs
        .map((doc) => ShiftSubmission.fromMap(doc.id, doc.data()))
        .toList();

    return _groupByPerson(list);
  }

  /// Fetch all shift submissions (used when admin wants to see everything)
  Future<List<ShiftSubmission>> fetchAllSubmissions() async {
    final querySnapshot = await _db.collection('shift_submissions').get();
    final list = querySnapshot.docs
        .map((doc) => ShiftSubmission.fromMap(doc.id, doc.data()))
        .toList();

    // Group per (name, department, targetMonth) so resubmissions across
    // different months are NOT collapsed together, only same-month ones.
    final Map<String, List<ShiftSubmission>> byKey = {};
    for (final s in list) {
      final key = '${s.name}|${s.department}|${s.targetMonth}';
      byKey.putIfAbsent(key, () => []).add(s);
    }
    final result = <ShiftSubmission>[];
    for (final group in byKey.values) {
      result.addAll(_groupByPerson(group));
    }
    result.sort((a, b) {
      final at = a.submittedAt;
      final bt = b.submittedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return result;
  }

  /// Groups a flat list of submissions (already narrowed to a single
  /// target month) by (name, department): keeps only the newest doc per
  /// person at the top level, attaching any older docs as
  /// `previousVersions` (newest-first) for resubmission history.
  List<ShiftSubmission> _groupByPerson(List<ShiftSubmission> list) {
    final sorted = [...list]
      ..sort((a, b) {
        final at = a.submittedAt;
        final bt = b.submittedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at); // newest first
      });

    final Map<String, List<ShiftSubmission>> byPerson = {};
    for (final s in sorted) {
      final key = '${s.name}|${s.department}';
      byPerson.putIfAbsent(key, () => []).add(s);
    }

    final result = <ShiftSubmission>[];
    for (final group in byPerson.values) {
      final newest = group.first;
      final older = group.length > 1 ? group.sublist(1) : <ShiftSubmission>[];
      result.add(
        ShiftSubmission(
          id: newest.id,
          name: newest.name,
          department: newest.department,
          targetMonth: newest.targetMonth,
          monthMemo: newest.monthMemo,
          days: newest.days,
          totalHours: newest.totalHours,
          submittedAt: newest.submittedAt,
          previousVersions: older,
        ),
      );
    }
    result.sort((a, b) {
      final at = a.submittedAt;
      final bt = b.submittedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return result;
  }

  Future<void> deleteSubmission(String id) async {
    await _db.collection('shift_submissions').doc(id).delete();
  }

  /// Persists an admin's manual correction to an existing submission's
  /// day entries (hours/code) plus its recomputed `totalHours`, made from
  /// the monthly shift matrix screen's tap-to-edit-hours feature. Only
  /// `days` and `totalHours` are touched - everything else on the
  /// submission document (name, department, targetMonth, submittedAt,
  /// etc.) is left untouched.
  Future<void> updateSubmission(ShiftSubmission submission) async {
    if (submission.id == null) return;
    await _db.collection('shift_submissions').doc(submission.id).update({
      'days': submission.days.map((d) => d.toMap()).toList(),
      'totalHours': submission.totalHours,
    });
  }

  /// Update the app-wide config (admin settings screen)
  Future<void> updateConfig(AppConfig config) async {
    await _db.collection('app_settings').doc('config').set({
      'targetMonth': config.targetMonth,
      'holidays': config.holidays,
      'deadline': config.deadline,
      'notice': config.notice,
      'departments': config.departments,
      'adminPassword': config.adminPassword,
      'employees': config.employees.map((e) => e.toMap()).toList(),
    }, SetOptions(merge: true));
  }
}
