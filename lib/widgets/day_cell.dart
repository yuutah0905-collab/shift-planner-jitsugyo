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

  /// When true, tapping the cell toggles selection (via [onSelectToggle])
  /// instead of opening the normal edit sheet. Used by the "一括入力"
  /// (bulk input) feature in ShiftFormScreen.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectToggle;

  const DayCell({
    super.key,
    required this.entry,
    required this.onChanged,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectToggle,
  });

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
    final canSelect = selectionMode && !entry.isHoliday;

    return InkWell(
      onTap: entry.isHoliday
          ? null
          : selectionMode
          ? onSelectToggle
          : () => _openEditSheet(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.20) : bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (hasInput ? accentColor : AppColors.line),
            width: selected ? 2 : (hasInput ? 1.4 : 1),
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
            // Memo indicator: placed in the top-left corner (bulk-select
            // mode uses the top-right corner for its checkbox, so this
            // moves here to avoid overlapping with it).
            if (hasMemo)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            // Selection checkbox indicator shown only in bulk-select mode.
            // Placed in the top-right corner so it no longer overlaps the
            // day number, which is centered near the top of the cell.
            if (canSelect)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 1.3),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 11, color: Colors.white)
                      : null,
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

  /// The A〜Y symbol selected for the paid-leave hours (used only for the
  /// personal salary estimate, not sent to the admin as work hours).
  /// Derived from the stored [DayEntry.paidLeaveHours] value by matching
  /// it back to its corresponding shift code, so re-opening the sheet
  /// shows the previously selected symbol instead of a raw number.
  String _paidLeaveCode = '';

  @override
  void initState() {
    super.initState();
    _code = widget.entry.code;
    _memoController = TextEditingController(text: widget.entry.memo);
    final storedHours = double.tryParse(widget.entry.paidLeaveHours);
    if (storedHours != null) {
      for (final e in ShiftCode.codes) {
        if ((e.value - storedHours).abs() < 0.001) {
          _paidLeaveCode = e.key;
          break;
        }
      }
    }
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
                // Paid leave doesn't clear paidLeaveHours - the user may
                // want to re-select '有' after briefly picking something
                // else, and shouldn't have to re-select the hours symbol.
                if (!ShiftCode.isPaidLeave(_code)) {
                  entry.paidLeaveHours = '';
                  _paidLeaveCode = '';
                }
              });
              widget.onChanged();
            },
          ),
          if (ShiftCode.isPaidLeave(_code)) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _paidLeaveCode.isEmpty ? null : _paidLeaveCode,
              decoration: const InputDecoration(labelText: '有給の時間（給料計算用）'),
              hint: const Text('記号を選択'),
              items: ShiftCode.codes
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(ShiftCode.labelFor(e.key, e.value)),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _paidLeaveCode = val ?? '';
                  final h = val != null ? ShiftCode.hoursForCode(val) : null;
                  entry.paidLeaveHours = h != null ? h.toStringAsFixed(2) : '';
                });
                widget.onChanged();
              },
            ),
            const SizedBox(height: 4),
            const Text(
              '※ここで入力した時間は「自分の給料計算」にのみ使われます。'
              '管理者側の集計時間には影響しません。',
              style: TextStyle(fontSize: 11, color: AppColors.inkMute),
            ),
          ],
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
                    entry.paidLeaveHours = '';
                    _paidLeaveCode = '';
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
