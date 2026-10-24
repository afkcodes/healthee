/// `Where today's heart rate sat` — the Edwards zones behind the load figure.
///
/// ## Shipped, parsed, and drawn nowhere
///
/// `cardio_load.zone_minutes` has been on the wire since the endpoint existed
/// and `ActivityToday` has parsed it into `CardioLoad.zoneMinutes` the whole
/// time — nothing rendered it. Legacy's Activity screen had a
/// `Heart-rate zones · today` card; the rebuild dropped it. Prod carries the
/// flag on all thirty of the last thirty days, so this is not a slot waiting
/// for data.
///
/// ## The zones are Edwards', and the boundaries are stated
///
/// `derive/cardio_load.py` cuts at **50 / 60 / 70 / 80 / 90 % of HRmax**, and
/// HRmax is Tanaka 2001 (`208 − 0.7 × age`) rather than the 220-minus-age rule
/// of thumb. Both facts belong on the card: a zone chart whose boundaries are
/// unstated is five bars the reader cannot check, and the same minute lands in
/// a different zone under a different HRmax.
///
/// **When the payload sends [CardioLoad.hrmax] the bands are named in beats**
/// as well as percent, because a boundary in bpm is one a reader recognises and
/// a boundary in percent is one they have to compute.
///
/// ## Waking minutes only
///
/// `derive_cardio_load` skips asleep minutes, so these are the minutes of the
/// day the owner was up. Said on the card: without it the totals look short
/// against a 24-hour day and the reader has no way to know why.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// `EDWARDS_ZONE_LO` — the lower bound of each zone as a share of HRmax.
const List<double> kZoneLowerBounds = <double>[0.50, 0.60, 0.70, 0.80, 0.90];

/// What each zone is for, in the owner's words rather than the literature's.
const List<String> kZoneNames = <String>[
  'Very light',
  'Light',
  'Moderate',
  'Hard',
  'Maximum',
];

/// The note the boundaries and the load figure are cited to.
const String kZonesNote =
    'Waking minutes only, cut at 50/60/70/80/90% of your estimated maximum '
    'heart rate. The estimate is age-based (Tanaka 2001), not a measured max.';

/// The five Edwards zones, as minutes of the day.
class ZonesPanel extends StatelessWidget {
  /// [load] is `/api/today.cardio_load`, already parsed.
  const ZonesPanel({required this.load, super.key});

  /// The card's title.
  static const String title = 'Where your heart rate sat';

  /// The gap between two zone rows.
  static const double rowGap = 11;

  /// The bar's height.
  static const double barHeight = 22;

  /// Its corner.
  static const double barRadius = 6;

  /// The label column on the left.
  static const double nameWidth = 92;

  /// The minutes column on the right.
  static const double minutesWidth = 52;

  /// The day's load, carrying its zone minutes.
  final CardioLoad load;

  /// The largest single zone, which every bar is drawn against.
  ///
  /// **Not the total.** Scaled against the sum, a day spent almost entirely in
  /// zone one draws four invisible bars — and those four are the ones the
  /// reader is looking for.
  int get peak => load.zoneMinutes.isEmpty
      ? 0
      : load.zoneMinutes.reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    final zones = load.zoneMinutes;
    return Panel(
      tone: Tone.heart,
      label: 'Heart-rate zones',
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.heartPulse,
        infoKey: 'hr_zone_minutes',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (zones.length != kZoneLowerBounds.length || peak <= 0)
            // A shape this card cannot read is not a day with no minutes in it.
            const PanelNote(
              'No zone breakdown for today. The strap recorded no waking '
              'heart rate to sort into them.',
            )
          else ...<Widget>[
            for (final (int i, int minutes) in zones.indexed) ...<Widget>[
              if (i > 0) const SizedBox(height: rowGap),
              _ZoneRow(
                index: i,
                minutes: minutes,
                peak: peak,
                hrmax: load.hrmax,
              ),
            ],
            const PanelNote(kZonesNote),
          ],
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.index,
    required this.minutes,
    required this.peak,
    required this.hrmax,
  });

  final int index;
  final int minutes;
  final int peak;
  final double? hrmax;

  /// `50–60%`, or `95–114 bpm` when the payload named the maximum.
  String get band {
    final lo = kZoneLowerBounds[index];
    final hi = index + 1 < kZoneLowerBounds.length
        ? kZoneLowerBounds[index + 1]
        : null;
    final max = hrmax;
    if (max == null) {
      final low = (lo * 100).round();
      return hi == null ? '$low%+' : '$low–${(hi * 100).round()}%';
    }
    final low = (lo * max).round();
    return hi == null ? '$low+ bpm' : '$low–${(hi * max).round()} bpm';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = context.family;
    // The higher the zone, the more of the family it carries — so intensity
    // reads off the bar without a second colour scale to learn.
    final fill = family.withValues(alpha: 0.35 + 0.145 * index);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: ZonesPanel.nameWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                kZoneNames[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
              ),
              Text(
                band,
                maxLines: 1,
                style: TypeScale.panelNote.copyWith(color: colors.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ZonesPanel.barRadius),
            child: SizedBox(
              height: ZonesPanel.barHeight,
              child: Stack(
                children: <Widget>[
                  ColoredBox(
                    color: colors.line,
                    child: const SizedBox(
                      width: double.infinity,
                      height: ZonesPanel.barHeight,
                    ),
                  ),
                  FractionallySizedBox(
                    // Zero minutes draws no bar at all rather than a sliver:
                    // a zone the owner never entered is an absence, and a hair
                    // of colour reads as a small amount of time in it.
                    widthFactor: peak <= 0 ? 0 : minutes / peak,
                    child: ColoredBox(
                      color: fill,
                      child: const SizedBox(height: ZonesPanel.barHeight),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: ZonesPanel.minutesWidth,
          child: Text(
            '$minutes min',
            textAlign: TextAlign.right,
            maxLines: 1,
            style: (minutes > 0 ? TypeLadder.calloutStrong : TypeLadder.callout)
                .copyWith(color: minutes > 0 ? colors.ink : colors.ink2),
          ),
        ),
      ],
    );
  }
}
