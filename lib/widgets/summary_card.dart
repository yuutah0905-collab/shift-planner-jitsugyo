import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SummaryCard extends StatelessWidget {
  final int filledDays;
  final double totalHours;
  final int memoCount;
  final int holidayCount;

  /// Optional "送信ステータス" row shown below the main 2x2 stat grid,
  /// inside the SAME gradient card (kept compact - just a label + short
  /// value, not a separate full-size banner). Null/empty = not shown
  /// (e.g. before a department/name has been entered).
  final String? submissionStatusLabel;
  final Color? submissionStatusColor;

  const SummaryCard({
    super.key,
    required this.filledDays,
    required this.totalHours,
    required this.memoCount,
    required this.holidayCount,
    this.submissionStatusLabel,
    this.submissionStatusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ink, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 4,
            children: [
              _stat('$filledDays', '入力日数'),
              _stat('${totalHours.toStringAsFixed(2)} h', '希望合計時間'),
              _stat('$memoCount', 'メモ件数'),
              _stat('$holidayCount', '休業日(設定済)'),
            ],
          ),
          if (submissionStatusLabel != null &&
              submissionStatusLabel!.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Colors.white24, height: 1),
            ),
            Row(
              children: [
                const Text(
                  '送信ステータス',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (submissionStatusColor ?? Colors.white)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    submissionStatusLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: submissionStatusColor ?? Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ],
    );
  }
}
