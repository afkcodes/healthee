/// One running breathing session: the clock, the pattern in use, and what is
/// logged when it ends.
///
/// Finishing logs the planned minutes. Ending early logs the whole minutes
/// actually breathed, and nothing under one. A session from a plan item is also
/// marked done for today when it logs. A failed save is shown with a retry, not
/// dropped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_done.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_session_log.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/features/coach/v02/breathing_ink_button.dart';
import 'package:healthee/features/coach/v02/breathing_orb.dart';
import 'package:healthee/features/coach/v02/breathing_pattern_chips.dart';
import 'package:healthee/features/coach/v02/breathing_phase_bar.dart';
import 'package:healthee/features/coach/v02/breathing_player_head.dart';
import 'package:healthee/features/coach/v02/breathing_progress_lines.dart';
import 'package:healthee/features/coach/v02/breathing_session_spec.dart';
import 'package:healthee/features/coach/v02/breathing_timer.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:solar_icons/solar_icons.dart';

/// The session.
class BreathingSession extends ConsumerStatefulWidget {
  /// Runs [spec], starting at once.
  const BreathingSession({required this.spec, super.key});

  /// What to run.
  final BreathingSessionSpec spec;

  @override
  ConsumerState<BreathingSession> createState() => _BreathingSessionState();
}

class _BreathingSessionState extends ConsumerState<BreathingSession>
    with SingleTickerProviderStateMixin {
  late final BreathingTimer _timer = BreathingTimer(
    vsync: this,
    pattern: widget.spec.pattern,
    minutes: widget.spec.minutes,
    onFinished: () => _over(finished: true),
  );
  late BreathPattern _pattern = widget.spec.pattern;
  bool _paused = false;
  String? _overWord;
  int? _logged;
  int? _unsaved;

  bool get _isOver => _overWord != null;

  @override
  void initState() {
    super.initState();
    _timer.start();
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  Future<void> _over({required bool finished}) async {
    final minutes = minutesToLog(
      plannedMinutes: widget.spec.minutes,
      finished: finished,
      elapsed: _timer.elapsed,
    );
    _timer.pause();
    setState(() => _overWord = finished ? 'Done' : 'Ended');
    await _record(minutes);
  }

  Future<void> _record(int minutes) async {
    if (minutes < 1) return;
    try {
      final kind = widget.spec.kind;
      if (kind != null) {
        await ref.read(breathingDoneProvider.notifier).mark(kind);
      }
      final log = await ref.read(breathingSessionLogProvider.future);
      await log.logSession(minutes);
      if (mounted) {
        setState(() {
          _logged = minutes;
          _unsaved = null;
        });
      }
    } on Exception catch (error, stack) {
      AppLog.failure('breathing', 'saving a breathing session', error, stack);
      if (mounted) {
        setState(() => _unsaved = minutes);
      }
    }
  }

  Future<void> _requestEnd() async {
    if (_isOver) {
      leaveDetail(context);
      return;
    }
    final wasRunning = _timer.isRunning;
    _timer.pause();
    final minutes = minutesToLog(
      plannedMinutes: widget.spec.minutes,
      finished: false,
      elapsed: _timer.elapsed,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: Text(
          minutes >= 1
              ? 'This logs $minutes min of meditation.'
              : 'It has not reached a minute, so nothing is logged.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      await _over(finished: false);
      if (mounted && _unsaved == null) leaveDetail(context);
    } else if (wasRunning && !_paused) {
      _timer.start();
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _paused ? _timer.pause() : _timer.start();
  }

  void _pick(BreathPattern pattern) {
    if (pattern == _pattern || _isOver) return;
    setState(() {
      _pattern = pattern;
      _paused = false;
    });
    _timer.restart(pattern);
  }

  List<BreathPattern> get _choices {
    final custom = ref.watch(breathingSettingsControllerProvider).value?.custom;
    return <BreathPattern>[...kBreathPresets, ?custom];
  }

  String get _caption {
    if (_unsaved != null) {
      return "Couldn't save this to your journal.";
    }
    if (_logged != null) {
      return 'Logged $_logged min to your journal as meditation.';
    }
    if (_isOver) {
      return 'Under a minute, so nothing was logged.';
    }
    return 'Logs ${widget.spec.minutes} min of meditation when you finish. '
        'Ending early logs what you did.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final sections = <Widget Function(BuildContext)>[
      (_) => BreathingPlayerHead(
        title: widget.spec.title,
        subtitle: widget.spec.subtitle,
        onBack: _requestEnd,
      ),
      (_) => Padding(
        padding: const EdgeInsets.only(top: Insets.sm),
        child: BreathingPatternChips(
          patterns: _choices,
          selected: _pattern,
          onSelect: _pick,
        ),
      ),
      (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xl),
        child: Center(
          child: LayoutBuilder(
            builder: (context, box) => BreathingOrb(
              diameter: box.maxWidth.clamp(0, 300).toDouble(),
              progress: _timer.progress,
              scale: reduced ? null : _timer.scale,
              doneWord: _overWord,
            ),
          ),
        ),
      ),
      (_) => BreathingPhaseBar(pattern: _pattern, progress: _timer.progress),
      (_) => Padding(
        padding: const EdgeInsets.only(top: Insets.lg),
        child: BreathingProgressLines(progress: _timer.progress),
      ),
      (_) => Padding(
        padding: const EdgeInsets.only(top: Insets.xl),
        child: _isOver ? _afterControls() : _controls(),
      ),
      (_) => Padding(
        padding: const EdgeInsets.only(top: Insets.lg),
        child: Text(
          _caption,
          textAlign: TextAlign.center,
          style: TypeLadder.callout.copyWith(color: colors.ink2),
        ),
      ),
    ];
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestEnd();
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              Insets.sm,
              Insets.gutter,
              Insets.section,
            ),
            itemCount: sections.length,
            itemBuilder: (context, i) => sections[i](context),
          ),
        ),
      ),
    );
  }

  Widget _controls() => Row(
    children: <Widget>[
      const Expanded(child: SizedBox.shrink()),
      InkCircleButton(
        icon: _paused ? SolarIconsBold.play : SolarIconsBold.pause,
        label: _paused ? 'Resume' : 'Pause',
        onPressed: _togglePause,
      ),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _requestEnd,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.ink2,
              minimumSize: const Size(44, 44),
              textStyle: TypeLadder.body,
            ),
            child: const Text('End'),
          ),
        ),
      ),
    ],
  );

  Widget _afterControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (_unsaved case final int minutes) ...<Widget>[
        InkButton(label: 'Try again', onPressed: () => _record(minutes)),
        const SizedBox(height: Insets.sm),
      ],
      TextButton(
        onPressed: () => leaveDetail(context),
        child: const Text('Close'),
      ),
    ],
  );
}
