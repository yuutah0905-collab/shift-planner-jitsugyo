import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import '../models/employee.dart';
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

  /// Streams the app-wide config in real time, so screens like the
  /// shift-request form can react immediately (e.g. show the "シフト配布"
  /// banner) as soon as an admin toggles publish state - without the
  /// part-time staff member needing to pull-to-refresh or reopen the app.
  /// Falls back to a single [AppConfig.fallback] value if the doc doesn't
  /// exist yet; stream errors are swallowed (caller keeps last-known
  /// config) since transient network hiccups shouldn't kick the user back
  /// to a blank/fallback state while they're mid-input.
  Stream<AppConfig> watchConfig() {
    return _db
        .collection('app_settings')
        .doc('config')
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return AppConfig.fromMap(doc.data()!);
          }
          return AppConfig.fallback();
        })
        .handleError((e) {
          if (kDebugMode) debugPrint('watchConfig error: $e');
        });
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

  /// Streams shift submissions for a given target month in real time, so
  /// the monthly shift matrix stays in sync automatically whenever an
  /// admin edits a submission (e.g. corrects hours) - even while it's
  /// already published and part-time staff are viewing it. Without this,
  /// staff only saw the snapshot from the moment they opened the matrix,
  /// and admins had to un-publish/re-publish just to force a refresh.
  /// Uses the same grouping as [fetchSubmissionsForMonth] (newest per
  /// person at the top level, older ones nested in `previousVersions`).
  Stream<List<ShiftSubmission>> watchSubmissionsForMonth(String targetMonth) {
    return _db
        .collection('shift_submissions')
        .where('targetMonth', isEqualTo: targetMonth)
        .snapshots()
        .map((querySnapshot) {
          final list = querySnapshot.docs
              .map((doc) => ShiftSubmission.fromMap(doc.id, doc.data()))
              .toList();
          return _groupByPerson(list);
        })
        .handleError((e) {
          if (kDebugMode) debugPrint('watchSubmissionsForMonth error: $e');
        });
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

  /// Persists ONLY the employee roster (⑥従業員名簿) to Firestore,
  /// independent of the rest of the settings screen's "設定を保存" button.
  /// Used so that roster edits made through their own dedicated dialogs
  /// (rename, PIN edit, add, remove, reorder) take effect immediately -
  /// without requiring the admin to also press the main save button,
  /// which otherwise could discard the roster change if the admin
  /// navigated away, or make it look like the edit "didn't work" until
  /// the unrelated save button was pressed.
  Future<void> updateEmployees(List<Employee> employees) async {
    await _db.collection('app_settings').doc('config').set({
      'employees': employees.map((e) => e.toMap()).toList(),
    }, SetOptions(merge: true));
  }

  /// When an admin renames someone in the employee roster (⑥従業員名簿),
  /// this updates that person's `name` field on every EXISTING
  /// shift_submissions document that matches [oldName] + [department]
  /// (case/whitespace-insensitive match, via [Employee.normalizeName]),
  /// so the rename is reflected immediately in the monthly shift matrix,
  /// daily attendance list, and the staff member's own "送信済み" status -
  /// not just for future submissions. Uses a batched write since there
  /// may be multiple historical submissions (resubmissions) for the same
  /// person. Silently does nothing if no matching submissions exist yet
  /// (e.g. the person hasn't submitted anything this month).
  Future<void> renameEmployeeInSubmissions({
    required String oldName,
    required String department,
    required String newName,
  }) async {
    final normalizedOld = Employee.normalizeName(oldName);
    if (normalizedOld.isEmpty || oldName == newName) return;

    final querySnapshot = await _db
        .collection('shift_submissions')
        .where('department', isEqualTo: department)
        .get();

    final batch = _db.batch();
    var matched = 0;
    for (final doc in querySnapshot.docs) {
      final docName = doc.data()['name']?.toString() ?? '';
      final normalizedDocName = Employee.normalizeName(docName);
      if (normalizedDocName == normalizedOld) {
        batch.update(doc.reference, {'name': newName});
        matched++;
      }
    }
    if (matched > 0) {
      await batch.commit();
    }
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
      'publishedDepartments': config.publishedDepartments,
    }, SetOptions(merge: true));
  }

  /// Toggles the "シフト配布" (publish) flag for a single [department]'s
  /// monthly shift matrix, used by the admin's monthly shift matrix screen.
  /// Each department has its own admin/manager, so publishing is scoped
  /// per-department (not a single app-wide flag): only the map entry for
  /// [department] is touched via dot-notation `update()`, so other
  /// departments' publish states and any other config field are never
  /// clobbered by a concurrent edit on the settings screen.
  Future<void> setDepartmentPublished(
    String department,
    bool published,
    String targetMonth,
  ) async {
    final docRef = _db.collection('app_settings').doc('config');
    if (published) {
      await docRef.set({
        'publishedDepartments': {department: targetMonth},
      }, SetOptions(merge: true));
    } else {
      // Dot-notation update() to remove just this one map key without
      // needing to read the doc first or touching sibling departments.
      await docRef.update({
        'publishedDepartments.$department': FieldValue.delete(),
      });
    }
  }

  /// Doc id for the monthly shift matrix's "備考" (remarks) free-text
  /// box, scoped to one target month + department so different
  /// departments/months don't share the same note.
  String _remarksDocId(String targetMonth, String department) =>
      '${targetMonth}_$department';

  /// Fetches the admin-written remarks text for the monthly shift matrix
  /// (target month + department), used both by the admin's editable view
  /// and by part-time staff's read-only published view - stored in
  /// Firestore (not local shared_preferences) precisely so it's visible
  /// across devices once "シフト配布" is turned on.
  Future<String> fetchMatrixRemarks(
    String targetMonth,
    String department,
  ) async {
    try {
      final doc = await _db
          .collection('matrix_remarks')
          .doc(_remarksDocId(targetMonth, department))
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists && doc.data() != null) {
        return doc.data()!['text']?.toString() ?? '';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchMatrixRemarks error: $e');
    }
    return '';
  }

  /// Saves the admin-written remarks text for the monthly shift matrix.
  Future<void> saveMatrixRemarks(
    String targetMonth,
    String department,
    String text,
  ) async {
    await _db
        .collection('matrix_remarks')
        .doc(_remarksDocId(targetMonth, department))
        .set({
          'targetMonth': targetMonth,
          'department': department,
          'text': text,
        }, SetOptions(merge: true));
  }
}
