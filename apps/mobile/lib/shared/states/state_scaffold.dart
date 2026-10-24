/// The shared loading / error / empty states, and the card frame they sit in.
///
/// Engineering Standards §3: "Every async consumer renders all three states —
/// loading, error (with retry), and empty/no-data — using the shared-state
/// widgets. An error state that renders as a blank card is a bug."
///
/// They live together in one file because they are one decision: three answers to
/// "there is nothing to draw yet", which must look like siblings. Split across
/// three files they drift apart, and the version a screen forgot to update is the
/// one the owner sees on the worst day.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/shared/states/caveat_disclosure.dart';
import 'package:healthee/shared/states/caveat_scope.dart';

/// The card every state renders inside — a hairline frame, generous radius.
///
/// "Flat, hairline `line`/`line-2` dividers, generous radii, almost no shadow.
/// Depth from spacing and contrast." (`docs/APP_DESIGN_BRIEF.md` §2.)
///
/// ## The corner is a superellipse, and it costs nothing
///
/// The legacy design used the `smooth_corner` package for squircle cards, and
/// that shape is part of the language this screen is matching. It is NOT worth a
/// dependency — but since Flutter 3.35 the framework draws it natively, so
/// [RoundedSuperellipseBorder] buys the corner for one class name and no package.
/// At [Radii.card] the difference from a circular corner is small and cumulative:
/// it is what stops a grid of seven cards reading as seven rounded rectangles.
class StateCard extends StatelessWidget {
  /// Wraps [child] in the app's card frame.
  const StateCard({required this.child, this.border, this.fill, super.key});

  /// The card's contents.
  final Widget child;

  /// Overrides the frame colour.
  ///
  /// Exists for the illness banner, which the design draws as a solid `alert`
  /// border over an `alertSoft` fill. Default is the hairline
  /// [HealtheeColors.line]. It is not a decoration hook — brief §2 forbids
  /// colouring a card to decorate it, so anything but the default is a claim
  /// about the owner's body.
  final Color? border;

  /// Overrides the fill. Pairs with [border]; default is [HealtheeColors.surface].
  final Color? fill;

  /// The one card shape, so a grid module and a detail card share a corner.
  /// The one card corner in the app — legacy's `hSquircle` at [Radii.card].
  ///
  /// It used to be Flutter's own `RoundedSuperellipseBorder`, which draws Apple's
  /// continuous corner and is very close to what this returns. It now delegates
  /// to `shapes.dart` so there is a single definition of the corner, and so that
  /// definition is the one legacy actually drew against (`smooth_corner` at
  /// smoothness 0.6).
  ///
  /// **No edge unless [border] is given.** A card has no border; only a genuine
  /// status card (an alert) passes one.
  static ShapeBorder shapeOf([Color? border]) => hSquircle(
    Radii.card,
    side: border == null
        ? BorderSide.none
        : BorderSide(color: border, width: hairline),
  );

  /// ## It claims an enclosing [CaveatScope]
  ///
  /// A `ReadingView` that wraps a whole card used to draw the card's caveat
  /// signpost as a sibling BENEATH it, which put the sentence in the gutter
  /// between two cards where it names neither. `caveat_scope.dart` carries the
  /// argument. `InstrumentModule` claims the scope on the ported screens; this
  /// claims it everywhere else a card is drawn, so the fix is not per-screen.
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = CaveatScope.of(context);
    final disclosed = scope?.caveats ?? const <Disclosure>[];
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fill ?? colors.surface,
        shape: shapeOf(border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(Insets.card),
          // Shadowed for the subtree, so a card inside a card cannot render the
          // same disclosure twice.
          child: CaveatScope(
            caveats: const <Disclosure>[],
            child: disclosed.isEmpty
                ? child
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      child,
                      CaveatNote(caveats: disclosed, label: scope?.label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Waiting on data.
///
/// Deliberately quiet: a prominent spinner over a card that will usually fill
/// from the local store in milliseconds reads as slowness that is not there.
class LoadingState extends StatelessWidget {
  /// Shows a subdued progress indicator.
  const LoadingState({this.label, super.key});

  /// What is being loaded, for screen readers and for slow paths.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return StateCard(
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.ink2,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              label ?? 'Loading…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Something failed — OUR fault, and retryable.
///
/// Distinct from a withheld value, and the distinction is structural rather than
/// chromatic. A withhold has a `ValueHole` where the number would be; this has a
/// button. Neither is tinted: brief §2 reserves the product's one red for the
/// illness flag, and a dead request is not a fact about the owner's health.
///
/// [onRetry] is required rather than optional, so "error with no way forward"
/// cannot be built by omission.
class ErrorState extends StatelessWidget {
  /// Shows a failure with a retry affordance.
  const ErrorState({
    required this.message,
    required this.onRetry,
    this.detail,
    super.key,
  });

  /// What went wrong, in plain words the owner can act on.
  final String message;

  /// Optional context — shown small, never instead of [message].
  final String? detail;

  /// Tries again. Required: see the class docstring.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return StateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: text.titleSmall),
          if (detail case final String detailText) ...[
            const SizedBox(height: Insets.sm),
            Text(
              detailText,
              style: text.bodySmall?.copyWith(color: colors.ink2),
            ),
          ],
          const SizedBox(height: Insets.md),
          Align(
            alignment: Alignment.centerLeft,
            // Outlined rather than accent-filled: the accent marks the owner's own
            // data line and the primary path through the app, and a failed request
            // should not out-shout the numbers around it.
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

/// There is genuinely nothing here yet, and here is how to change that.
///
/// Brief §2 and `docs/APP_DESIGN.md` §1: "Empty states, not '—'. Graceful 'no
/// data yet / here's how to get it' degradation." The [hint] is that second half
/// and is required for the same reason [ErrorState.onRetry] is.
class EmptyState extends StatelessWidget {
  /// Shows an honest empty card.
  const EmptyState({required this.message, required this.hint, super.key});

  /// What is absent.
  final String message;

  /// What would make it appear.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return StateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: text.titleSmall),
          const SizedBox(height: Insets.sm),
          Text(hint, style: text.bodySmall?.copyWith(color: colors.ink2)),
        ],
      ),
    );
  }
}
