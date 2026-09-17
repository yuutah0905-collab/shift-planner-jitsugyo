import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/day_entry.dart';
import '../theme/app_theme.dart';
import 'tick_sound_stub.dart';

/// Result of [showTimeRangeDialPicker]: the selected start/end time as
/// "HH:MM" (24h) strings, plus whether a 10-minute break was selected,
/// or null if the user cancelled.
class TimeRangeResult {
  final String startTime; // "HH:MM"
  final String endTime; // "HH:MM"
  final bool hasBreak;

  const TimeRangeResult({
    required this.startTime,
    required this.endTime,
    this.hasBreak = false,
  });
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
  bool initialHasBreak = false,
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
      initialHasBreak: initialHasBreak,
    ),
  );
}

class _TimeRangeDialSheet extends StatefulWidget {
  final String initialStart;
  final String initialEnd;
  final bool initialHasBreak;

  const _TimeRangeDialSheet({
    required this.initialStart,
    required this.initialEnd,
    this.initialHasBreak = false,
  });

  @override
  State<_TimeRangeDialSheet> createState() => _TimeRangeDialSheetState();
}

class _TimeRangeDialSheetState extends State<_TimeRangeDialSheet> {
  // NOTE: these are NOT plain State fields updated via setState() - see
  // _startHourN/_startMinuteN/_endHourN/_endMinuteN below. Scrolling a wheel
  // fires onSelectedItemChanged once per notch (many times per second during
  // a fast flick); if each of those called setState() on this State, EVERY
  // notch would re-run build() for the ENTIRE sheet - all 4 dial columns,
  // the summary text, the break chips and the confirm button - even though
  // visually nothing but the summary text actually needs to change. That
  // extra rebuild work is pure waste, and while cheap enough on Android's
  // native Skia engine to go unnoticed, it's far more expensive under
  // Flutter Web's CanvasKit-on-WebAssembly execution on iOS Safari - which
  // matches exactly what was reported ("Androidはスムーズ、iPhoneはカクカク"
  // after two earlier tick-sound/controller fixes that didn't touch this).
  // Fix: hold the four wheel values in ValueNotifiers instead, updated with
  // NO setState() call at all during scrolling, and rebuild only the small
  // summary Text via AnimatedBuilder/Listenable.merge - the dial columns
  // themselves never rebuild while scrolling.
  late final ValueNotifier<int> _startHourN;
  late final ValueNotifier<int> _startMinuteN; // in 5-minute steps (0,5,...,55)
  late final ValueNotifier<int> _endHourN;
  late final ValueNotifier<int> _endMinuteN;
  late bool _hasBreak;

  // One FixedExtentScrollController per wheel, created ONCE in initState
  // and reused for the lifetime of this sheet - NOT recreated on every
  // build(). Each notch change calls setState() (to update the
  // "09:00〜17:00" summary text etc.), which re-runs build(); if the
  // wheel's controller were instead created inline in build() (as it
  // used to be: `FixedExtentScrollController(initialItem: ...)` passed
  // straight into ListWheelScrollView.useDelegate), every one of those
  // rebuilds handed the ListWheelScrollView a brand-new controller
  // mid-gesture. On iOS Safari in particular this repeatedly tore down
  // and rebuilt the scrollable's internal ballistic/inertia scroll
  // simulation while the user's finger was still dragging, producing
  // the reported "カクつく" (janky/stuttering) feel - Android/desktop
  // Chrome's scroll physics happened to be more forgiving of this and
  // masked the bug. Keeping a single stable controller per wheel fixes
  // this at the root.
  late final FixedExtentScrollController _startHourController;
  late final FixedExtentScrollController _startMinuteController;
  late final FixedExtentScrollController _endHourController;
  late final FixedExtentScrollController _endMinuteController;

  // A pool of several pre-loaded AudioPlayers for the tick sound, rather
  // than a single shared player. Rapid dial scrolling can fire many
  // ticks per second (one per notch, via onSelectedItemChanged); reusing
  // ONE player by calling seek(0) + resume() on it back-to-back caused a
  // race on Web (each call replaces the previous, unfinished play()
  // request on the underlying <audio> element, which the browser then
  // rejects with an unhandled "play() request was interrupted" error) -
  // the sound silently stopped playing while haptic feedback (a separate,
  // synchronous platform channel call) kept working, which is exactly
  // the "振動だけになる" symptom this pool-based approach fixes: each tick
  // grabs its own available player from the pool instead of fighting
  // over a single one.
  TickSoundPool? _tickPool;

  @override
  void initState() {
    super.initState();
    TickSoundPool.create(assetPath: 'sounds/dial_tick.mp3').then((pool) {
      if (mounted) {
        _tickPool = pool;
      } else {
        pool.dispose();
      }
    });

    _hasBreak = widget.initialHasBreak;

    final startParts = widget.initialStart.split(':');
    final int initStartHour;
    final int initStartMinute;
    if (startParts.length == 2) {
      initStartHour = int.tryParse(startParts[0]) ?? 9;
      initStartMinute = (int.tryParse(startParts[1]) ?? 0) ~/ 5 * 5;
    } else {
      initStartHour = 9;
      initStartMinute = 0;
    }
    final endParts = widget.initialEnd.split(':');
    final int initEndHour;
    final int initEndMinute;
    if (endParts.length == 2) {
      initEndHour = int.tryParse(endParts[0]) ?? 17;
      initEndMinute = (int.tryParse(endParts[1]) ?? 0) ~/ 5 * 5;
    } else {
      initEndHour = 17;
      initEndMinute = 0;
    }

    _startHourN = ValueNotifier(initStartHour);
    _startMinuteN = ValueNotifier(initStartMinute);
    _endHourN = ValueNotifier(initEndHour);
    _endMinuteN = ValueNotifier(initEndMinute);

    _startHourController = FixedExtentScrollController(
      initialItem: initStartHour,
    );
    _startMinuteController = FixedExtentScrollController(
      initialItem: initStartMinute ~/ 5,
    );
    _endHourController = FixedExtentScrollController(initialItem: initEndHour);
    _endMinuteController = FixedExtentScrollController(
      initialItem: initEndMinute ~/ 5,
    );
  }

  @override
  void dispose() {
    _tickPool?.dispose();
    _startHourController.dispose();
    _startMinuteController.dispose();
    _endHourController.dispose();
    _endMinuteController.dispose();
    _startHourN.dispose();
    _startMinuteN.dispose();
    _endHourN.dispose();
    _endMinuteN.dispose();
    super.dispose();
  }

  /// Plays a short mechanical "click" sound for each notch the dial
  /// passes, mimicking the feel of a physical ratchet/rotary dial.
  /// Also fires a tiny haptic tick on platforms that support it, so the
  /// feedback isn't purely audio-only (e.g. if the device is muted).
  void _playTick() {
    // Fire-and-forget: AudioPool.start() hands back a per-tick player
    // from the pool (creating a new one if all are busy), so rapid
    // scrolling never has two ticks fighting over the same player's
    // play()/seek() state - each tick's sound is free to finish (or be
    // cut off by the pool reclaiming it) independently of the others.
    // volume is explicit (not just relying on the 1.0 default) because
    // the original tick audio asset turned out to be a very quiet,
    // mostly-silence 1s clip - too faint to notice on Web even with a
    // fully-connected, error-free playback path. It's been replaced with
    // a short (~80ms), louder synthesized click, and volume is pinned to
    // 1.0 here so this never silently regresses if the default changes.
    _tickPool?.play();
    HapticFeedback.selectionClick();
  }

  static String _fmt(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get _startLabel => _fmt(_startHourN.value, _startMinuteN.value);
  String get _endLabel => _fmt(_endHourN.value, _endMinuteN.value);

  /// Duration in hours between start and end, treating end <= start as
  /// spanning into the next day (e.g. a night shift 22:00〜翌6:00) and
  /// subtracting a 10-minute break if selected - matches how the rest of
  /// the app has no concept of an explicit "next day" flag, so this is
  /// the most intuitive interpretation for a single-day shift form.
  double get _durationHours => DayEntry.durationHoursBetween(
    _startLabel,
    _endLabel,
    hasBreak: _hasBreak,
  );

  void _confirm() {
    if (_durationHours <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('終了時刻は開始時刻より後にしてください')));
      return;
    }
    Navigator.of(context).pop(
      TimeRangeResult(
        startTime: _startLabel,
        endTime: _endLabel,
        hasBreak: _hasBreak,
      ),
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
                  hourController: _startHourController,
                  minuteController: _startMinuteController,
                  // IMPORTANT: no setState() here - see the comment on the
                  // ValueNotifier fields above. Updating the notifier's
                  // .value does NOT rebuild this sheet; only the small
                  // AnimatedBuilder-wrapped summary Text below listens for
                  // it, so a fast flick through many notches never re-runs
                  // this whole build() method.
                  onHourChanged: (v) => _startHourN.value = v,
                  onMinuteChanged: (v) => _startMinuteN.value = v,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, color: AppColors.inkMute),
              ),
              Expanded(
                child: _timeDialColumn(
                  label: '終了',
                  hourController: _endHourController,
                  minuteController: _endMinuteController,
                  onHourChanged: (v) => _endHourN.value = v,
                  onMinuteChanged: (v) => _endMinuteN.value = v,
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
            alignment: Alignment.center,
            // Only this Text rebuilds as the dials scroll (via the merged
            // ValueNotifiers below) - the rest of the sheet (dial columns,
            // break chips, confirm button) is untouched by scrolling.
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _startHourN,
                _startMinuteN,
                _endHourN,
                _endMinuteN,
              ]),
              builder: (context, _) => Text(
                '${_fmt(_startHourN.value, _startMinuteN.value)} 〜 ${_fmt(_endHourN.value, _endMinuteN.value)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDeep,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.free_breakfast_outlined,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '10分休憩',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('なし'),
                  selected: !_hasBreak,
                  onSelected: (_) => setState(() => _hasBreak = false),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('あり'),
                  selected: _hasBreak,
                  onSelected: (_) => setState(() => _hasBreak = true),
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
    required FixedExtentScrollController hourController,
    required FixedExtentScrollController minuteController,
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
                      controller: hourController,
                      itemCount: 24,
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
                      controller: minuteController,
                      itemCount: 12, // 0,5,10,...,55 (5-minute steps)
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
    required FixedExtentScrollController controller,
    required int itemCount,
    required ValueChanged<int> onChanged,
    required String Function(int) labelBuilder,
  }) {
    // onSelectedItemChanged fires exactly once per item the wheel settles
    // on/passes through as it's dragged (a discrete "notch" event, not a
    // continuous per-pixel callback), which is exactly the granularity we
    // want for a single click-tick per detent.
    //
    // `controller` is passed in from the parent State (created once in
    // initState, see _TimeRangeDialSheetState) rather than created here -
    // this widget itself has no State of its own, so creating the
    // controller inline here would still mean a fresh instance every
    // time _timeDialColumn()/_wheel() re-runs as part of the parent's
    // build(), which is exactly the mid-gesture controller churn that
    // caused the iOS jank this fixes.
    return ListWheelScrollView.useDelegate(
      controller: controller,
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
