import 'package:flutter/material.dart';
import '../models/shift_code.dart';
import '../models/shift_submission.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class SubmissionDetailScreen extends StatelessWidget {
  final ShiftSubmission submission;

  const SubmissionDetailScreen({super.key, required this.submission});

  String _fmtMonthJp(String ym) {
    final parts = ym.split('-');
    if (parts.length != 2) return ym;
    return '${parts[0]}年${int.parse(parts[1])}月';
  }

  @override
  Widget build(BuildContext context) {
    // Show any day that has SOMETHING entered - a code/hours OR a memo.
    // Previously this only checked hours/code, so days where staff only
    // wrote a memo (no symbol) were silently hidden from the admin view.
    final filledDays = submission.days
        .where(
          (d) => d.hours.isNotEmpty || d.code.isNotEmpty || d.memo.isNotEmpty,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                '${submission.name} さんの希望',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (submission.isResubmission) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '再提出 ${submission.submissionCount}回目',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '削除',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('削除しますか？'),
                  content: const Text('この提出データを削除します。この操作は取り消せません。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('キャンセル'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text(
                        '削除',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true && submission.id != null) {
                await FirestoreService().deleteSubmission(submission.id!);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('氏名', submission.name),
                    _row('部署', submission.department),
                    _row('対象月', _fmtMonthJp(submission.targetMonth)),
                    _row(
                      '合計希望時間',
                      '${submission.totalHours.toStringAsFixed(2)} h',
                    ),
                    _row('入力日数', '${submission.filledDaysCount} 日'),
                    if (submission.submittedAt != null)
                      _row(
                        '提出日時',
                        submission.submittedAt!.toLocal().toString(),
                      ),
                  ],
                ),
              ),
            ),
            if (submission.monthMemo.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '今月のメモ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDeep,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(submission.monthMemo),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'シフト希望詳細',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDeep,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (filledDays.isEmpty)
                      const Text(
                        '入力されている日はありません',
                        style: TextStyle(color: AppColors.inkMute),
                      )
                    else
                      ...filledDays.map(
                        (d) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text(
                                  '${d.date.split('-').last}日(${d.dayOfWeek})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Only show the code/hours badge when a
                              // symbol or hours were actually entered.
                              // For memo-only days, show a neutral
                              // "メモのみ" badge instead of an empty " h".
                              // Paid-leave days get a distinct light-blue
                              // badge with no "h" suffix (no fixed hours).
                              if (ShiftCode.isPaidLeave(d.code))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.paidLeave.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    ShiftCode.paidLeaveFullLabel,
                                    style: TextStyle(
                                      color: AppColors.paidLeave,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              else if (d.hours.isNotEmpty || d.code.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${d.code} ${d.hours}h',
                                    style: const TextStyle(
                                      color: AppColors.primaryDeep,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'メモのみ',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (d.memo.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    d.memo,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.inkSoft,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (submission.previousVersions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.history,
                            size: 18,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '過去の提出履歴（${submission.previousVersions.length}件）',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'この方は同じ月に複数回シフト希望を送信しています。'
                        '一番新しい内容が上に表示されている内容です。',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMute,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...submission.previousVersions.asMap().entries.map((
                        entry,
                      ) {
                        final idx = entry.key;
                        final old = entry.value;
                        final versionLabel =
                            submission.submissionCount - idx - 1;
                        return _PreviousVersionTile(
                          submission: old,
                          versionLabel: versionLabel,
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.inkMute),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collapsible row summarizing one OLDER submission from the
/// resubmission history. Tapping it navigates into a read-only detail
/// view of that specific past submission (so admins can compare exactly
/// what changed between versions).
class _PreviousVersionTile extends StatelessWidget {
  final ShiftSubmission submission;
  final int versionLabel;

  const _PreviousVersionTile({
    required this.submission,
    required this.versionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final submittedAt = submission.submittedAt;
    final dateLabel = submittedAt != null
        ? '${submittedAt.toLocal().year}/${submittedAt.toLocal().month}/${submittedAt.toLocal().day} '
              '${submittedAt.toLocal().hour.toString().padLeft(2, '0')}:${submittedAt.toLocal().minute.toString().padLeft(2, '0')}'
        : '日時不明';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.weekendBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: Colors.orange.withValues(alpha: 0.15),
          child: Text(
            '$versionLabel',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
        ),
        title: Text(
          '$versionLabel回目の提出',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$dateLabel ／ 入力 ${submission.filledDaysCount}日 ／ 合計 '
          '${submission.totalHours.toStringAsFixed(2)}h',
          style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubmissionDetailScreen(submission: submission),
            ),
          );
        },
      ),
    );
  }
}
