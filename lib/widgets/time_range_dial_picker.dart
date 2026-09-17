import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Result of [showTimeRangeDialPicker]: the selected start/end time as
/// "HH:MM" (24h) strings, or null if the user cancelled.
class TimeRangeResult {
  final String startTime; // "HH:MM"
  final String endTime; // "HH:MM"

  const TimeRangeResult({required this.startTime, required this.endTime});
}

/// Shows a bottom sheet with a dial-style (scroll wheel) start/end time
/// picker for entering a custom, non-fixed-code shift time (e.g.
/// "13:15〜18:45") - used when none of the A~Y symbol codes fit.
/// [initialStart]/[initialEnd] are "HH:MM" strings (or empty for no
/// initial selection, defaulting to 09:00〜17:00).
Future<TimeRangeResult?> showTimeRangeDialPicker({
  required BuildContext context,
  String initialStart = '',
  String initialEnd = '',
}) {
  return showModalBottomSheet<TimeRangeResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TimeRangeDialSheet(
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

class _TimeRangeDialSheet extends StatefulWidget {
  final String initialStart;
  final String initialEnd;

  const _TimeRangeDialSheet({
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  State<_TimeRangeDialSheet> createState() => _TimeRangeDialSheetState();
}

class _TimeRangeDialSheetState extends State<_TimeRangeDialSheet> {
  late int _startHour;
  late int _startMinute; // in 5-minute steps (0,5,10...55)
  late int _endHour;
  late int _endMinute;

  // Reused between all 4 wheels rather than one AudioPlayer per wheel -
  // rapid scrolling can fire many ticks per second, and starting a new
  // player for each one would be wasteful. AudioPlayer supports being
  // told to play the same source again while already playing (it just
  // restarts), which is exactly the rapid-fire "dial spinning" behavior
  // we want.
  late final AudioPlayer _tickPlayer;

  @override
  void initState() {
    super.initState();
    _tickPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    // Pre-set the low-latency-friendly source so the very first tick
    // isn't delayed by a network/asset lookup.
    _tickPlayer.setSource(AssetSource('sounds/dial_tick.mp3'));

    final startParts = widget.initialStart.split(':');
    if (startParts.length == 2) {
      _startHour = int.tryParse(startParts[0]) ?? 9;
      _startMinute = (int.tryParse(startParts[1]) ?? 0) ~/ 5 * 5;
    } else {
      _startHour = 9;
      _startMinute = 0;
    }
    final endParts = widget.initialEnd.split(':');
    if (endParts.length == 2) {
      _endHour = int.tryParse(endParts[0]) ?? 17;
      _endMinute = (int.tryParse(endParts[1]) ?? 0) ~/ 5 * 5;
    } else {
      _endHour = 17;
      _endMinute = 0;
    }
  }

  @override
  void dispose() {
    _tickPlayer.dispose();
    super.dispose();
  }

  /// Plays a short mechanical "click" sound for each notch the dial
  /// passes, mimicking the feel of a physical ratchet/rotary dial.
  /// Also fires a tiny haptic tick on platforms that support it, so the
  /// feedback isn't purely audio-only (e.g. if the device is muted).
  void _playTick() {
    // seek(0) + resume() restarts playback from the beginning even if a
    // previous tick's sound is still finishing - important for fast
    // scrolling where ticks can fire faster than the 40ms clip's own
    // length.
    _tickPlayer.seek(Duration.zero);
    _tickPlayer.resume();
    HapticFeedback.selectionClick();
  }

  String get _startLabel =>
      '${_startHour.toString().padLeft(2, '0')}:${_startMinute.toString().padLeft(2, '0')}';
  String get _endLabel =>
      '${_endHour.toString().padLeft(2, '0')}:${_endMinute.toString().padLeft(2, '0')}';

  /// Duration in hours between start and end, treating end <= start as
  /// spanning into the next day (e.g. a night shift 22:00〜翌6:00) -
  /// matches how the rest of the app has no concept of an explicit
  /// "next day" flag, so this is the most intuitive interpretation for
  /// a single-day shift form.
  double get _durationHours {
    final startMinutes = _startHour * 60 + _startMinute;
    var endMinutes = _endHour * 60 + _endMinute;
    if (endMinutes <= startMinutes) endMinutes += 24 * 60;
    return (endMinutes - startMinutes) / 60.0;
  }

  void _confirm() {
    if (_durationHours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('終了時刻は開始時刻より後にしてください')),
      );
      return;
    }
    Navigator.of(context).pop(
      TimeRangeResult(startTime: _startLabel, endTime: _endLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const Expanded(
                child: Text(
                  '任意の時間を選択',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDeep,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'ダイヤルを回して開始・終了時刻を選んでください（5分単位）',
            style: TextStyle(fontSize: 12, color: AppColors.inkMute),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timeDialColumn(
                  label: '開始',
                  hour: _startHour,
                  minute: _startMinute,
                  onHourChanged: (v) => setState(() => _startHour = v),
                  onMinuteChanged: (v) => setState(() => _startMinute = v),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, color: AppColors.inkMute),
              ),
              Expanded(
                child: _timeDialColumn(
                  label: '終了',
                  hour: _endHour,
                  minute: _endMinute,
                  onHourChanged: (v) => setState(() => _endHour = v),
                  onMinuteChanged: (v) => setState(() => _endMinute = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$_startLabel 〜 $_endLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDeep,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '（${_durationHours.toStringAsFixed(2)}h）',
                  style: const TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _confirm,
              child: const Text('この時間で決定'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeDialColumn({
    required String label,
    required int hour,
    required int minute,
    required ValueChanged<int> onHourChanged,
    required ValueChanged<int> onMinuteChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _wheel(
                      itemCount: 24,
                      initialItem: hour,
                      onChanged: onHourChanged,
                      labelBuilder: (i) => i.toString().padLeft(2, '0'),
                    ),
                  ),
                  const Text(
                    ':',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.inkMute,
                    ),
                  ),
                  Expanded(
                    child: _wheel(
                      itemCount: 12, // 0,5,10,...,55 (5-minute steps)
                      initialItem: minute ~/ 5,
                      onChanged: (v) => onMinuteChanged(v * 5),
                      labelBuilder: (i) => (i * 5).toString().padLeft(2, '0'),
                    ),
                  ),
                ],
              ),
              // Center highlight band showing which row is "selected",
              // matching the classic iOS-style wheel picker affordance.
              IgnorePointer(
                child: Center(
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      border: const Border.symmetric(
                        horizontal: BorderSide(
                          color: AppColors.primary,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wheel({
    required int itemCount,
    required int initialItem,
    required ValueChanged<int> onChanged,
    required String Function(int) labelBuilder,
  }) {
    // onSelectedItemChanged fires exactly once per item the wheel settles
    // on/passes through as it's dragged (a discrete "notch" event, not a
    // continuous per-pixel callback), which is exactly the granularity we
    // want for a single click-tick per detent.
    return ListWheelScrollView.useDelegate(
      controller: FixedExtentScrollController(initialItem: initialItem),
      itemExtent: 34,
      diameterRatio: 1.4,
      perspective: 0.003,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) {
        _playTick();
        onChanged(index);
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) => Center(
          child: Text(
            labelBuilder(index),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
