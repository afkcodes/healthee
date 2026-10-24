/// The ring around the avatar — the whole of Today's connection chrome.
///
/// **Legacy draws this ring** (`app/lib/ui/today_screen.dart`: a 46 px
/// `CircularProgressIndicator` behind `HAvatar` while a sync runs). What it did
/// not draw is the full-width "Connected · Sync now" strip this app had above the
/// scroll, or the 7 px dot beside the date that replaced it. Both are gone; the
/// geometry legacy wrote is unchanged, and the ring now carries three more
/// things than "something is happening".
///
/// ```text
///   idle              a thin ink3 circle          nothing is running, no session
///   connected         a full accent circle        a session is open right now
///   syncing           an accent arc               determinate where the fetch says so
///   needs attention   a full ink circle           something is wrong; the card says what
/// ```
///
/// ## What the ring may and may not claim
///
/// **It is a status indicator, not a control.** Tapping the avatar opens
/// Settings, exactly as before; this widget contributes no gesture. Pull-to-
/// refresh is still the manual sync path.
///
/// **A ring cannot say "your token was rotated" or "22,000 measurements are
/// waiting".** So it is deliberately not the surface a fault is *reported* on —
/// every loud `ConnectionHealth` state is written out in full on the data-health
/// card, which sits four lines below this row in legacy's own section order. The
/// ring's fault state is a pointer to that card, and its semantic label says so.
/// Colour is never the only carrier: `README.md` would be right to call that a
/// claim made in a language with no words.
///
/// ## Why the fault ring is ink and not a warning colour
///
/// `apps/mobile/README.md`: there is exactly one red (`alert`, for illness) and
/// `unf` "is not a warning colour and must never be used as one". A radio that
/// will not connect is not a fact about the owner's body, so it may not spend
/// either. `health_lines.dart` already settled the same question for the card —
/// *"loud and quiet are typography, never colour"* — and this is that rule drawn
/// as a circle: full ink for loud, `ink3` for quiet, the accent for work.
///
/// ## Determinate where the fetch reports it, indeterminate where it does not
///
/// `StrapSyncProgress` is emitted by `StrapSync` per fetch it starts and is null
/// between the handshake and the first one, and during scanning, connecting and
/// authenticating. Those phases genuinely have no fraction, and
/// `ble/strap_progress.dart` is explicit that inventing one is the interface
/// version of a number nobody measured — so they spin, and only a reported
/// fraction is drawn as an arc. *An indeterminate spinner cannot distinguish a
/// working sync from a stalled one*, which is a question that went unanswerable
/// on this project; a determinate arc that stops moving can.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/sync/connection_health.dart';

/// What the ring is saying. Four states, and they are mutually exclusive.
enum SyncRingState {
  /// No session, nothing running, nothing wrong. The resting state.
  idle,

  /// An authenticated session is open right now.
  connected,

  /// Work is in flight. Never an alarm — see `connection_health.dart`.
  syncing,

  /// At least one thing is wrong. The data-health card carries what.
  needsAttention,
}

/// Which state [health] puts the ring in.
///
/// Public so the mapping can be asserted without pumping a frame, and written as
/// a `switch`-free ladder in ONE place so no widget re-derives it.
///
/// **It reads `quiet`, not `alerts.isEmpty`.** `ConnectionHealth.quiet` is the
/// single place the "may this chrome be silent" answer is computed, and going
/// around it here would be a second answer free to disagree with the card's —
/// which is precisely the failure `connection_health.dart` is built to prevent.
SyncRingState ringStateOf(ConnectionHealth health) {
  if (health.busy) {
    return SyncRingState.syncing;
  }
  if (!health.quiet) {
    return SyncRingState.needsAttention;
  }
  return health.live ? SyncRingState.connected : SyncRingState.idle;
}

/// What a screen reader announces for [health].
///
/// The strip's `report.headline` used to carry this, and it is the one thing a
/// collapsing indicator must not lose: the ring's four colours are four colours
/// to anybody who cannot see them.
String ringLabel(ConnectionHealth health) {
  switch (ringStateOf(health)) {
    case SyncRingState.syncing:
      // The phase's own words when there is no fraction; the fetch's own step
      // when there is. Never "in progress" — `strap_progress.dart` earns these.
      final progress = health.progress;
      return progress == null
          ? health.report.headline
          : 'Syncing — ${progress.label}, step ${progress.step} of ${progress.total}';
    case SyncRingState.needsAttention:
      final alerts = health.alerts;
      final rest = alerts.length > 1 ? ', and ${alerts.length - 1} more' : '';
      // It names the fault AND where the sentence is, because the ring is not
      // the surface that can explain it.
      return '${alerts.first.headline}$rest. See Data health below.';
    case SyncRingState.connected:
    case SyncRingState.idle:
      return health.report.headline;
  }
}

/// A 46 px ring around [child], drawn from one [ConnectionHealth].
class SyncRing extends StatelessWidget {
  /// [health] null draws no ring at all — a widget test pumping the header row
  /// on its own has classified nothing, and a reassuring ring over no
  /// classification is the one thing this surface may not do.
  const SyncRing({
    required this.child,
    this.health,
    this.diameter = defaultDiameter,
    this.stroke = defaultStroke,
    super.key,
  });

  /// The classified connection state, or null when nothing has classified one.
  final ConnectionHealth? health;

  /// The avatar. It keeps its own gesture and its own semantics.
  final Widget child;

  /// Legacy's `SizedBox(width: 46, height: 46)`.
  ///
  /// A default rather than a fixed size: the ring has to clear whatever it is
  /// wrapping, and Today's head draws a smaller mark than Actions does.
  static const double defaultDiameter = 46;

  /// This ring's outer size. It must exceed its child by twice the gap you
  /// want, or the stroke lands on the child's own edge.
  final double diameter;

  /// Legacy's `strokeWidth: 2`.
  ///
  /// A default, like [defaultDiameter]: a ring drawn at two thirds the size
  /// keeps two thirds of its weight, or the smaller mark reads as the heavier
  /// one.
  static const double defaultStroke = 2;

  /// This ring's stroke.
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final state = health;
    if (state == null) {
      return child;
    }
    final colors = context.colors;
    final ring = ringStateOf(state);
    return Semantics(
      container: true,
      label: ringLabel(state),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: diameter,
            height: diameter,
            child: CircularProgressIndicator(
              value: _value(ring, state),
              strokeWidth: stroke,
              color: _tint(ring, colors),
              // The unfilled part of a determinate arc. On the three full-circle
              // states it is covered by the ring itself.
              backgroundColor: colors.line2,
            ),
          ),
          child,
        ],
      ),
    );
  }

  /// Null is indeterminate, and it is only ever returned where the fetch has
  /// genuinely reported nothing.
  static double? _value(SyncRingState ring, ConnectionHealth health) =>
      switch (ring) {
        SyncRingState.syncing => health.progress?.fraction,
        // A complete circle: these three are states, not progress.
        _ => 1,
      };

  static Color _tint(SyncRingState ring, HealtheeColors colors) => switch (ring) {
    SyncRingState.syncing || SyncRingState.connected => colors.accent,
    // Full ink, never `unf` or `alert` — see the library docstring.
    SyncRingState.needsAttention => colors.ink,
    SyncRingState.idle => colors.ink2,
  };
}
