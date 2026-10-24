/// [Fold] — the app's one open/close transition.
///
/// ## Why it exists
///
/// `reasoning_note.dart` and `insight_card.dart` both fold with a bare
/// `if (_open)`, so the body appears and disappears between one frame and the
/// next. The owner, looking at a third surface built to match them: *"then the
/// idiom is wrong we need swift animation"*. They are right — an instant swap
/// gives the reader no signal that the content went somewhere retrievable
/// rather than being replaced, which is the whole difference between a fold and
/// a state change.
///
/// ## ⛔ Not `AnimatedSize` — that is what made it stutter
///
/// `AnimatedSize` animates by **re-measuring its child every frame**. The body
/// behind this fold is a column of markdown paragraphs, so each frame of the
/// transition re-laid-out the whole analysis, and the owner's verdict on the
/// device was *"animation is still not smooth"*.
///
/// [Align.heightFactor] is the cheap reveal, and it is what Material's own
/// `ExpansionTile` uses: the child is laid out **once**, at its natural size,
/// and the parent simply takes a fraction of that height while a [ClipRect]
/// hides the rest. Nothing is measured again mid-flight.
///
/// The clip is not optional either way — without it the paragraphs paint
/// outside the panel and over whatever card is beneath it.
///
/// ## An explicit controller, so there is no animation on arrival
///
/// `TweenAnimationBuilder` animates from its `begin` on the first build, so a
/// panel that starts open would unroll itself every time the screen is built.
/// The controller is seeded at its resting value instead and only ever moves
/// when [open] actually changes.
library;

import 'package:flutter/material.dart';

/// Opens and closes [child] with the app's own timing.
class Fold extends StatefulWidget {
  /// [open] drives it; [child] is what is behind the fold.
  const Fold({
    required this.open,
    required this.child,
    this.duration = Fold.defaultDuration,
    this.curve = Fold.defaultCurve,
    this.fade = false,
    super.key,
  });

  /// Swift. Short enough that a reader tapping twice never waits on it.
  static const Duration defaultDuration = Duration(milliseconds: 160);

  /// Decelerating, so the motion settles rather than stopping.
  static const Curve defaultCurve = Curves.easeOutCubic;

  /// How long the fold takes. Zero is instant (reduced motion).
  final Duration duration;

  /// The easing, in both directions.
  final Curve curve;

  /// Fades the body with the height, so it does not slide out of nowhere.
  final bool fade;

  /// Whether the body is shown.
  final bool open;

  /// The body.
  final Widget child;

  @override
  State<Fold> createState() => _FoldState();
}

class _FoldState extends State<Fold> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    // Seeded at rest, never at zero — see the library docstring.
    value: widget.open ? 1 : 0,
  );

  late final Animation<double> _height = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
    reverseCurve: widget.curve.flipped,
  );

  @override
  void didUpdateWidget(Fold old) {
    super.didUpdateWidget(old);
    _controller.duration = widget.duration;
    if (widget.open != old.open) {
      widget.open ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _height,
        // `child` is built ONCE and handed back on every tick — the point of
        // the whole exercise. Rebuilding it here would restore the cost
        // `AnimatedSize` was paying.
        child: widget.child,
        builder: (context, child) => Align(
          alignment: Alignment.topCenter,
          heightFactor: _height.value,
          child: widget.fade
              ? Opacity(opacity: _height.value.clamp(0.0, 1.0), child: child)
              : child,
        ),
      ),
    );
  }
}
