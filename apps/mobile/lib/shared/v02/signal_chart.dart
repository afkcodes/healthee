/// `.signal-chart` — each signal against **its own** baseline, not a population.
///
/// ```css
/// .signal-chart     { margin-block: 16px }
/// .signal-chart-key { display:flex; justify-content:space-between;
///                     padding: 0 48px 12px 80px; color:var(--subtle);
///                     font-size:8px }
/// .signal-row       { display:grid; grid-template-columns:68px minmax(0,1fr) 56px;
///                     gap:8px; align-items:center; margin-block:17px;
///                     font-size:11px }
/// .signal-row b     { font-size:10px; text-align:right; font-weight:500 }
/// .signal-track     { position:relative; height:5px; border-radius:5px;
///                     background:var(--surface-soft) }
/// .signal-band      { position:absolute; inset:-7px 32%;
///                     background:var(--chart-faint); border-radius:4px }
/// .signal-center    { position:absolute; left:50%; width:1px; height:27px;
///                     top:-11px; background:var(--rule) }
/// .signal-dot       { position:absolute; top:-3px; width:11px; height:11px;
///                     background:var(--accent); border:2px solid var(--surface);
///                     border-radius:50%; transform:translateX(-50%) }
/// ```
///
/// ## The axis is the one number the prototype does not have to choose
///
/// Every dot in the prototype is hard-coded at `left: 50%`. A live ladder has to
/// turn a standard score into a position, and that is the one piece of chart
/// craft here: **the track spans ±[axisSigma] standard scores** and the band is
/// ±1, which lands its edges at 33.3% — the 32% the CSS draws, to within a
/// pixel. So the band still means "inside your normal range" and the scale it is
/// read on is stated rather than implied.
///
/// ## A signal with no baseline has no position, and gets no dot
///
/// `recovery_signals.dart` is explicit: *"a signal with no baseline yet has no
/// position on the ladder, and drawing it at the centre line would assert it is
/// exactly normal"*. A [SignalRow] with a null [SignalRow.z] draws its track,
/// its band and its centre line, and no marker at all.
///
/// **The dot is never coloured by which side it is on.** Which side is
/// favourable is a research question the server answers in `direction`, and a
/// hue chosen here from the sign of `z` would be a verdict this widget has no
/// evidence for. It is `var(--accent)`, exactly as the CSS says.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/meter_type_scale.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';

/// One row of a [SignalChart].
@immutable
class SignalRow {
  /// [z] of null draws no marker; see the library docstring.
  const SignalRow(this.label, this.reading, {this.z});

  /// The signal's name.
  final String label;

  /// The reading, already formatted with its unit.
  final String reading;

  /// Standard scores from the owner's own baseline, or null.
  final double? z;
}

/// `.signal-chart` — the personal-baseline ladder.
class SignalChart extends StatelessWidget {
  /// Builds the ladder. An empty [rows] draws nothing at all.
  const SignalChart(this.rows, {super.key});

  /// How many standard scores the full track width spans, each way.
  static const double axisSigma = 3;

  /// `.signal-chart { margin-block: 16px }`.
  static const double outerGap = 16;

  /// `.signal-chart-key { padding: 0 48px 12px 80px }`.
  static const double keyLeftInset = 80;
  static const double keyRightInset = 48;
  static const double keyBottomGap = 12;

  /// `.signal-row { grid-template-columns: 68px … 56px }`.
  static const double labelWidth = 68;
  static const double readingWidth = 56;

  /// `.signal-row { gap: 8px }`.
  static const double columnGap = 8;

  /// `.signal-row { margin-block: 17px }`.
  static const double rowGap = 17;

  /// `.signal-track { height: 5px; border-radius: 5px }`.
  static const double trackHeight = 5;
  static const double trackRadius = 5;

  /// `.signal-band { inset: -7px …; border-radius: 4px }`.
  static const double bandOutset = 7;
  static const double bandRadius = 4;

  /// `.signal-center { width: 1px; height: 27px; top: -11px }`.
  static const double centreWidth = 1;
  static const double centreHeight = 27;
  static const double centreTop = -11;

  /// `.signal-dot { width: 11px; height: 11px; top: -3px; border: 2px }`.
  static const double dotSize = 11;
  static const double dotTop = -3;
  static const double dotRing = 2;

  /// The three column headings the key carries.
  static const List<String> captions = <String>[
    'Lower',
    'Your baseline',
    'Higher',
  ];

  /// The signals, in the payload's own order.
  final List<SignalRow> rows;

  /// Where a standard score sits on the track, 0–1, or null when it has none.
  static double? position(double? z) {
    if (z == null || !z.isFinite) {
      return null;
    }
    return (0.5 + z / (axisSigma * 2)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: outerGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              keyLeftInset,
              0,
              keyRightInset,
              keyBottomGap,
            ),
            // Three equal thirds, aligned start · centre · end, rather than
            // `spaceBetween`: the middle caption then sits over the baseline
            // whatever the outer two measure, and a caption too wide for its
            // third wraps instead of pushing the row past the track.
            child: Row(
              children: <Widget>[
                for (final (index, caption) in captions.indexed)
                  Expanded(
                    child: Text(
                      caption,
                      textAlign: switch (index) {
                        0 => TextAlign.start,
                        1 => TextAlign.center,
                        _ => TextAlign.end,
                      },
                      style: MeterType.signalKey.copyWith(color: colors.ink2),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: rowGap),
            _SignalRow(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

/// One `.signal-row`: the name, the track it sits on, and the reading.
class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.row});

  final SignalRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: <Widget>[
        SizedBox(
          width: SignalChart.labelWidth,
          child: Text(
            row.label,
            style: TypeScale.factorRow.copyWith(color: colors.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: SignalChart.columnGap),
        Expanded(child: _SignalTrack(at: SignalChart.position(row.z))),
        const SizedBox(width: SignalChart.columnGap),
        SizedBox(
          width: SignalChart.readingWidth,
          child: Text(
            row.reading,
            textAlign: TextAlign.right,
            style: MeterType.signalReading.copyWith(color: colors.ink),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
      ],
    );
  }
}

/// The track, its band, its centre line and — when there is a position — its
/// marker. Split out so the row above stays a three-column layout and this stays
/// the drawing.
class _SignalTrack extends StatelessWidget {
  const _SignalTrack({required this.at});

  /// Where the marker goes, 0–1, or null when this signal has no position.
  final double? at;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: SignalChart.trackHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // The ±1σ band, on the axis the chart declares. Drawn first so the
            // track's own ground reads through where the band does not reach.
            Positioned(
              left: constraints.maxWidth * SignalChart.position(-1)!,
              right: constraints.maxWidth * (1 - SignalChart.position(1)!),
              top: -SignalChart.bandOutset,
              bottom: -SignalChart.bandOutset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.familySoft,
                  borderRadius: BorderRadius.circular(SignalChart.bandRadius),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(SignalChart.trackRadius),
                ),
              ),
            ),
            Positioned(
              left: constraints.maxWidth / 2,
              top: SignalChart.centreTop,
              width: SignalChart.centreWidth,
              height: SignalChart.centreHeight,
              child: ColoredBox(color: colors.rule),
            ),
            if (at case final double fraction)
              Positioned(
                left: constraints.maxWidth * fraction - SignalChart.dotSize / 2,
                top: SignalChart.dotTop,
                width: SignalChart.dotSize,
                height: SignalChart.dotSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.surface,
                      width: SignalChart.dotRing,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
