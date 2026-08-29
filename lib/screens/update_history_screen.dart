import 'package:flutter/material.dart';
import '../app_version.dart';
import '../theme/app_theme.dart';

/// Shows the app's version history so all staff (part-timers and admins)
/// can see what changed and when - reached by tapping the small version
/// label on the shift-request screen.
class UpdateHistoryScreen extends StatelessWidget {
  const UpdateHistoryScreen({super.key});

  String _fmtDate(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return ymd;
    return '${parts[0]}年${int.parse(parts[1])}月${int.parse(parts[2])}日';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アップデート情報')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.ink, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.system_update_alt,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '現在のバージョン',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      Text(
                        'ver${AppVersion.currentVersion}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ...AppVersion.updateHistory.asMap().entries.map((entry) {
              final isLatest = entry.key == 0;
              final u = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isLatest
                                    ? AppColors.primary
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                                border: isLatest
                                    ? null
                                    : Border.all(color: AppColors.line),
                              ),
                              child: Text(
                                'ver${u.version}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isLatest
                                      ? Colors.white
                                      : AppColors.inkMute,
                                ),
                              ),
                            ),
                            if (isLatest) ...[
                              const SizedBox(width: 6),
                              const Text(
                                '最新',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDeep,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              _fmtDate(u.date),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.inkMute,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...u.notes.map(
                          (note) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    note,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.ink,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
