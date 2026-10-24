/// The biological-age sphere: a slowly turning ball of accent-coloured dots with
/// the reading sitting in a clear patch at its centre.
///
/// ## What goes in [AgeSphere.centre]
///
/// The hero builds it, this widget only centres it above the dots: the Display
/// number (`TypeLadder.display`, ink), an 8 px gap, then the verdict in
/// `TypeLadder.bodyStrong`: "1.7 years younger" in `fav`, "2.1 years older" in
/// `unf`, "About your age" in `ink2` when the gap is under half a year. The
/// number must be scaled down if it would be wider than 1.4 R so a large text
/// scale never clips; the hero passes the painted half-width as
/// [AgeSphere.clearHalfWidth] so the dots clear exactly that much room.
///
/// ## Motion costs nothing it does not have to
///
/// The sphere turns once per 120 s, repainting at most 30 times a second, and
/// only the painter repaints: the centre is a separate widget above it. The
/// ticker stops when the sphere is scrolled off screen, when the app is not in
/// the foreground, when a route covers it (`TickerMode`), under reduced motion,
/// and when the reading is withheld. It resumes from the angle it stopped at.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:healthee/core/theme/motion.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/instruments/age_sphere_lattice.dart';
import 'package:healthee/shared/v02/instruments/age_sphere_painter.dart';

/// The entry scale the sphere grows from.
const double kEntryScale = 0.94;

/// The shortest gap between two repaints: 30 frames a second.
const Duration kSphereFrameGap = Duration(milliseconds: 33);

/// Without a scroll observer, visibility is re-checked every this many frames.
const int kVisibilityFrames = 30;

/// Without a scroll observer, a stopped sphere re-checks this often.
const Duration kVisibilityPoll = Duration(seconds: 1);

/// The turning ball, with [centre] above it.
class AgeSphere extends StatefulWidget {
  /// [canvas] is the square's edge in logical px: 330 on the detail screen, 300
  /// on Today. The sphere's radius is 0.425 of it; the rest is glow room.
  const AgeSphere({
    required this.canvas,
    required this.centre,
    this.clearHalfWidth,
    this.withheld = false,
    this.revealId,
    this.reveals,
    this.breath,
    this.useFamily = false,
    super.key,
  });

  /// The square's edge, in logical px.
  final double canvas;

  /// The number and verdict, centred above the points.
  final Widget centre;

  /// Half the painted width of the number, in px; null clears 0.35 R.
  final double? clearHalfWidth;

  /// No rotation ever, a still frame, every alpha at 0.35.
  final bool withheld;

  /// With [reveals], the entry plays once per screen visit for this id.
  final Object? revealId;

  /// The screen's registry of reveals already played.
  final RevealRegistry? reveals;

  /// With a listenable, the dots are drawn at its value as a scale about the
  /// centre, so the ball can breathe: 1 is the size it is drawn at. The
  /// [centre] is not scaled. Null draws the dots as they always were.
  final ValueListenable<double>? breath;

  /// Draws the dots in the enclosing `ToneScope`'s family hue instead of the
  /// app accent. No colour is passed in: the scope decides it.
  final bool useFamily;

  @override
  State<AgeSphere> createState() => _AgeSphereState();
}

class _AgeSphereState extends State<AgeSphere>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ValueNotifier<double> _angle = ValueNotifier<double>(kStillAngle);
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: HMotion.slow,
  );
  late final Animation<double> _entryCurve = CurvedAnimation(
    parent: _entry,
    curve: HMotion.curve,
  );

  SphereFrame? _frame;
  ScrollNotificationObserverState? _observer;
  Timer? _poll;
  bool _reduced = false;
  bool _resumed = true;
  bool _visible = true;
  bool _entryDecided = false;
  bool _recheckQueued = false;
  double _angleAtStart = kStillAngle;
  Duration _lastNotified = Duration.zero;
  int _frames = 0;

  bool get _wantsMotion => !_reduced && !widget.withheld;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _recheck());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    final ScrollNotificationObserverState? observer =
        ScrollNotificationObserver.maybeOf(context);
    if (observer != _observer) {
      _observer?.removeListener(_onScroll);
      _observer = observer?..addListener(_onScroll);
    }
    if (!_entryDecided) {
      _entryDecided = true;
      final RevealRegistry? registry = widget.reveals;
      final Object? id = widget.revealId;
      final bool first =
          registry == null || id == null || registry.markSeen(id);
      if (first && !_reduced) {
        _entry.forward();
      } else {
        _entry.value = 1;
      }
    } else if (_reduced) {
      _entry.value = 1;
    }
    _sync();
  }

  @override
  void didUpdateWidget(AgeSphere old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observer?.removeListener(_onScroll);
    _poll?.cancel();
    _ticker.dispose();
    _entry.dispose();
    _angle.dispose();
    super.dispose();
  }

  /// A scroll notification can arrive in the middle of a layout, when a render
  /// box may not read its size, so the check waits for the frame to finish.
  void _onScroll(ScrollNotification _) {
    if (_recheckQueued) return;
    _recheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckQueued = false;
      _recheck();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _recheck() {
    if (!mounted) return;
    _visible = _isOnScreen();
    _sync();
  }

  /// Whether the sphere's box intersects the screen right now.
  bool _isOnScreen() {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return true;
    final Size screen =
        View.of(context).physicalSize / View.of(context).devicePixelRatio;
    final Rect rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.overlaps(Offset.zero & screen);
  }

  /// Starts or stops the ticker to match what the sphere should be doing.
  void _sync() {
    if (!_wantsMotion) {
      _stop();
      _angle.value = kStillAngle;
      _angleAtStart = kStillAngle;
      _poll?.cancel();
      _poll = null;
      return;
    }
    if (_resumed && _visible) {
      _poll?.cancel();
      _poll = null;
      if (!_ticker.isActive) {
        _lastNotified = Duration.zero;
        _ticker.start();
      }
    } else {
      _stop();
      // Without a scroll observer nothing tells us it came back: poll.
      if (_resumed && _observer == null) {
        _poll ??= Timer.periodic(kVisibilityPoll, (_) => _recheck());
      }
    }
  }

  void _stop() {
    if (_ticker.isActive) {
      _angleAtStart = _angle.value;
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastNotified < kSphereFrameGap) return;
    _lastNotified = elapsed;
    _angle.value =
        _angleAtStart +
        elapsed.inMicroseconds / kSpherePeriod.inMicroseconds * 2 * math.pi;
    if (_observer == null && ++_frames % kVisibilityFrames == 0) _recheck();
  }

  SphereFrame _frameFor(int count) {
    final SphereFrame? have = _frame;
    if (have != null && have.count == count) return have;
    return _frame = SphereFrame(count);
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final double canvas = widget.canvas;
    final double radius = canvas * kSphereRadiusShare;
    final int count = sphereDotCount(canvas, dark: dark);
    final double clear = widget.clearHalfWidth == null
        ? kDefaultClearWidth
        : (widget.clearHalfWidth! / radius).clamp(
            kMinClearWidth,
            kMaxClearWidth,
          );
    final Widget dots = ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(canvas),
          painter: AgeSpherePainter(
            angle: _angle,
            lattice: SphereLattice.forCount(count),
            frame: _frameFor(count),
            accent: widget.useFamily ? context.family : context.colors.accent,
            dark: dark,
            clearWidth: clear,
            withheld: widget.withheld,
          ),
        ),
      ),
    );
    final ValueListenable<double>? breath = widget.breath;
    return SizedBox.square(
      dimension: canvas,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          FadeTransition(
            opacity: _entryCurve,
            child: ScaleTransition(
              scale: Tween<double>(
                begin: kEntryScale,
                end: 1,
              ).animate(_entryCurve),
              child: breath == null
                  ? dots
                  : ValueListenableBuilder<double>(
                      valueListenable: breath,
                      builder: (_, double scale, Widget? child) =>
                          Transform.scale(scale: scale, child: child),
                      child: dots,
                    ),
            ),
          ),
          widget.centre,
        ],
      ),
    );
  }
}
