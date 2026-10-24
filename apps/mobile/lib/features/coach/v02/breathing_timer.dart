/// The session clock: a pausable stopwatch on a [Ticker].
///
/// Elapsed time is read from the ticker's own clock, not counted in timer
/// callbacks, so it cannot drift and a test drives it with `tester.pump`.
/// Everything the screen shows is `breathProgressAt` of that time.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_progress.dart';

/// Runs one session. [progress] updates every frame while it runs.
class BreathingTimer {
  /// A paused-at-zero timer for [pattern] over [minutes]; [start] runs it.
  BreathingTimer({
    required TickerProvider vsync,
    required this.pattern,
    required this.minutes,
    required this.onFinished,
  }) {
    _ticker = vsync.createTicker(_onTick);
    final first = _at(Duration.zero);
    progress = ValueNotifier<BreathProgress>(first);
    scale = ValueNotifier<double>(first.scale);
  }

  /// The pattern being breathed.
  BreathPattern pattern;

  /// Planned minutes.
  final int minutes;

  /// Called once when the planned time is used up.
  final VoidCallback onFinished;

  late final Ticker _ticker;

  /// Where the session is.
  late final ValueNotifier<BreathProgress> progress;

  /// The sphere's scale, updated with [progress].
  late final ValueNotifier<double> scale;

  void _publish(BreathProgress now) {
    progress.value = now;
    scale.value = now.scale;
  }

  Duration _before = Duration.zero;
  bool _finished = false;

  BreathProgress _at(Duration elapsed) =>
      breathProgressAt(pattern, minutes, elapsed);

  /// Time spent so far, pauses excluded.
  Duration get elapsed =>
      _before + (_ticker.isActive ? _sinceStart : Duration.zero);

  Duration _sinceStart = Duration.zero;

  /// Whether the clock is running.
  bool get isRunning => _ticker.isActive;

  /// Whether the planned time was used up.
  bool get isFinished => _finished;

  void _onTick(Duration sinceStart) {
    _sinceStart = sinceStart;
    final now = _at(elapsed);
    _publish(now);
    if (now.finished && !_finished) {
      _finished = true;
      _before = elapsed;
      _ticker.stop();
      onFinished();
    }
  }

  /// Starts or resumes.
  void start() {
    if (_finished || _ticker.isActive) return;
    _sinceStart = Duration.zero;
    _ticker.start();
  }

  /// Stops the clock where it is.
  void pause() {
    if (!_ticker.isActive) return;
    _before = elapsed;
    _sinceStart = Duration.zero;
    _ticker.stop();
  }

  /// Starts over with [next], running.
  void restart(BreathPattern next) {
    _ticker.stop();
    pattern = next;
    _before = Duration.zero;
    _sinceStart = Duration.zero;
    _finished = false;
    _publish(_at(Duration.zero));
    _ticker.start();
  }

  /// Releases the ticker.
  void dispose() {
    _ticker.dispose();
    progress.dispose();
    scale.dispose();
  }
}
