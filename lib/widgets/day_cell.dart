import 'package:flutter/material.dart';
import '../models/day_entry.dart';
import '../models/shift_code.dart';
import '../theme/app_theme.dart';

/// A compact calendar-style day cell (used in a 7-column weekly grid).
/// Tapping a non-holiday cell opens a bottom sheet to edit the shift
/// code and memo for that day.
class DayCell extends StatelessWidget {
  final DayEntry entry;
  final VoidCallback onChanged;

  const DayCell({super.key, required this.entry, required this.onChanged});

  Color _dowColor(String dow) {
    if (dow == '日') return AppColors.sun;
    if (dow == '土') return AppColors.sat;
    return AppColors.ink;
  }

  void _openEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _DayEditSheet(entry: entry, onChanged: onChanged);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeekend = entry.dayOfWeek == '日' || entry.dayOfWeek == '土';
    final hasInput = entry.code.isNotEmpty || entry.hours.isNotEmpty;
    final hasMemo = entry.memo.isNotEmpty;
    final isPaidLeave = ShiftCode.isPaidLeave(entry.code);

    Color bg = AppColors.surface;
    if (entry.isHoliday) {
      bg = AppColors.holidayBg;
    } else if (isWeekend) {
      bg = AppColors.weekendBg;
    } else if (isPaidLeave) {
      bg = AppColors.paidLeaveBg;
    } else if (hasInput) {
      bg = AppColors.primary.withValues(alpha: 0.10);
    }

    final accentColor = isPaidLeave ? AppColors.paidLeave : AppColors.primary;

    return InkWell(
      onTap: entry.isHoliday ? null : () => _openEditSheet(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasInput ? accentColor : AppColors.line,
            width: hasInput ? 1.4 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${entry.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: entry.isHoliday
                        ? AppColors.inkMute
                        : _dowColor(entry.dayOfWeek),
                  ),
                ),
                const SizedBox(height: 3),
                if (entry.isHoliday)
                  const Text(
                    '休',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.inkMute,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (isPaidLeave)
                  // Paid-leave days show the "有" tag only once, in the
                  // bottom-left corner (see Positioned widget below) - so
                  // here we just reserve the same vertical space instead
                  // of duplicating the badge in the center.
                  const SizedBox(height: 16)
                else if (hasInput)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.code.isNotEmpty ? entry.code : '${entry.hours}h',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  const Text(
                    '－',
                    style: TextStyle(fontSize: 11, color: AppColors.inkMute),
                  ),
              ],
            ),
            // Memo indicator: placed in the top-right corner so it stays
            // visible even on small mobile screens (previously it was below
            // the code badge and got clipped/hard to see on phones).
            if (hasMemo)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            // Paid-leave indicator: "有" badge in the bottom-left corner,
            // using the exact same pill shape (rounded rectangle) as the
            // normal code badge shown for other symbols, just placed in
            // the corner instead of the center - so it's visually
            // consistent with how every other symbol is displayed.
            if (isPaidLeave)
              Positioned(
                bottom: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '有',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayEditSheet extends StatefulWidget {
  final DayEntry entry;
  final VoidCallback onChanged;

  const _DayEditSheet({required this.entry, required this.onChanged});

  @override
  State<_DayEditSheet> createState() => _DayEditSheetState();
}

class _DayEditSheetState extends State<_DayEditSheet> {
  late TextEditingController _memoController;
  late String _code;

  @override
  void initState() {
    super.initState();
    _code = widget.entry.code;
    _memoController = TextEditingController(text: widget.entry.memo);
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final dateParts = entry.date.split('-');
    final dayLabel = dateParts.length == 3
        ? '${int.parse(dateParts[1])}月${int.parse(dateParts[2])}日'
        : entry.date;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$dayLabel（${entry.dayOfWeek}）',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDeep,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _code.isEmpty ? null : _code,
            decoration: const InputDecoration(labelText: '記号（希望時間）'),
            hint: const Text('記号を選択'),
            items: [
              DropdownMenuItem(
                value: ShiftCode.paidLeaveCode,
                child: Text(
                  '${ShiftCode.paidLeaveCode} (${ShiftCode.paidLeaveFullLabel})',
                  style: const TextStyle(
                    color: AppColors.paidLeave,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...ShiftCode.codes.map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(ShiftCode.labelFor(e.key, e.value)),
                ),
              ),
            ],
            onChanged: (val) {
              setState(() {
                _code = val ?? '';
                entry.code = _code;
                if (val != null) {
                  final h = ShiftCode.hoursForCode(val);
                  entry.hours = h != null ? h.toStringAsFixed(2) : '';
                } else {
                  entry.hours = '';
                }
              });
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _memoController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'この日のメモ（任意）',
              hintText: '例：午後から通院希望',
            ),
            onChanged: (val) {
              entry.memo = val;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 16),
          if (_code.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('この日の入力をクリア'),
                onPressed: () {
                  setState(() {
                    _code = '';
                    entry.code = '';
                    entry.hours = '';
                    entry.memo = '';
                    _memoController.clear();
                  });
                  widget.onChanged();
                },
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完了'),
            ),
          ),
        ],
      ),
    );
  }
}
