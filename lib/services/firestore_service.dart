import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import '../models/shift_submission.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetch app-wide config (target month, holidays, deadline, notice, etc.)
  Future<AppConfig> fetchConfig() async {
    try {
      final doc = await _db.collection('app_settings').doc('config').get();
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
  /// composite index requirements.
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

    list.sort((a, b) {
      final at = a.submittedAt;
      final bt = b.submittedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at); // newest first
    });
    return list;
  }

  /// Fetch all shift submissions (used when admin wants to see everything)
  Future<List<ShiftSubmission>> fetchAllSubmissions() async {
    final querySnapshot = await _db.collection('shift_submissions').get();
    final list = querySnapshot.docs
        .map((doc) => ShiftSubmission.fromMap(doc.id, doc.data()))
        .toList();
    list.sort((a, b) {
      final at = a.submittedAt;
      final bt = b.submittedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  Future<void> deleteSubmission(String id) async {
    await _db.collection('shift_submissions').doc(id).delete();
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
    }, SetOptions(merge: true));
  }
}
