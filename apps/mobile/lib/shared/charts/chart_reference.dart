/// What a series is READ AGAINST — the scale, the line on it, and its caption.
///
/// ## Why this file exists
///
/// Owner report, 2026-08-06, on the installed build: *"can we change the
/// heartrate, stress, hrv, blood oxygen graphs to be more meaningful ones, this
/// graphs all look similar."* They did, and the cause was structural rather than
/// cosmetic: all four were `HArea(series, color: tint, height: 52)` — a value
/// over time with **no reference**. Four different questions got one answer
/// shape, and none of the four answers could actually be read. 47 ms of HRV
/// means nothing without the owner's own normal beside it.
///
/// **This is an owner-directed departure from the verbatim-legacy rule**
/// (`feedback_port_legacy_design_verbatim`). Legacy draws no reference on any of
/// these four charts. Each card records the departure at its own site.
///
/// ## The rule that broke on the first attempt: A LABEL IS NOT INK IN THE PLOT
///
/// The first revision painted each reference's caption inside the plot box, just
/// above its line. Owner report on that build: *"heart rate is also looks wried,
/// same as blood oxygen you just made it bad."* Three charts shipped with the
/// label lying across the data — `YOUR 30-DAY NORMAL 53 MS` through the HRV
/// trace, `RESTING 56` on top of the hour captions, and a 55-character SpO2
/// sentence straight through the dots. Both the label and the data became
/// unreadable, which is strictly worse than the bare chart it replaced.
///
/// So [paintChartReference] draws **a line and nothing else**, and the caption is
/// a widget — [ChartReferenceCaption] — laid out under the chart where it cannot
/// collide with anything the painter drew. `test/features/vitals_labels_test.dart`
/// asserts that geometrically, in both themes, on all four cards: no glyph
/// overlaps a data mark and no glyph overlaps another glyph.
///
/// ## The one rule about the scale
///
/// A reference line is truthful only if it is drawn **in the same y-scale as the
/// series**, and only if that scale was widened to contain it. A resting-HR line
/// at 55 under a trace spanning 60–112 would otherwise clip to the bottom edge
/// and read as "you never went below your resting rate" — a false claim produced
/// entirely by layout. So [ChartScale.of] takes the reference values as
/// `include`, and a painter and its reference cannot disagree about where a
/// number sits.
///
/// ## How loud it is, and why the caption is louder — 2026-08-06
///
/// Owner report on the installed build: *"can we make the baseline line a bit
/// subtle in the charts"*. The line was opaque `ink3` — the same value as the
/// caption naming it — so a 1 px rule spanning the whole plot carried as much
/// ink as the words. It is [HealtheeColors.reference] now: `ink3` at 55%,
/// clearly visible and no longer a competitor with the trace.
///
/// **The caption did not follow it down, and that is measured rather than
/// lazy.** These are 9 px caps. `ink3` on this app's card surfaces measures
/// 5.17:1 in light and 5.55:1 in dark; at the reference's own 55% the same text
/// falls to **2.2:1**, and even 75% lands near 3.1:1 — under the 4.5:1 floor
/// that `DarkPalette.onAccent` exists in this codebase to respect. A hairline
/// may sit at the edge of perception; a word a reader has to read may not.
///
/// So the caption stays in `ink3` and is tied to its line a different way: it
/// carries a **swatch of the line itself**, dashed exactly when the line is
/// dashed ([_ReferenceSwatch]). That also puts the personal-baseline /
/// convention distinction on the screen for the first time — it used to live
/// only in the wording.
///
/// ## Structure, not verdict
///
/// A reference is drawn in a quiet ink and **never** in `fav`/`unf`/`alert`.
/// `palette.dart` rations those three to judgement, and a line saying "here is
/// your normal" is not a judgement about the reading beside it. The two kinds
/// differ by **dash**, not by hue:
///
///   * [ChartReferenceKind.personalBaseline] — solid. The owner's own number, as
///     the **server** defines it. The client never computes one: `CLAUDE.md`'s
///     one-definition-per-metric rule is exactly what a second, on-device
///     baseline would break.
///   * [ChartReferenceKind.convention] — dashed, and its caption says so. A
///     borrowed line that is not a measurement of this owner at all. The
///     blood-oxygen ~92% is the live case: `wearable_spo2_validity` is explicit
///     that it is *"a clinical convention, not a wearable-validated cutoff —
///     none is sourced (#98)"*. Drawing it exactly like a personal baseline
///     would assert it as a fact about this owner's oxygen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';

/// Whose number a reference line is.
enum ChartReferenceKind {
  /// The owner's own normal, from the server's baseline. Drawn solid.
  personalBaseline,

  /// A borrowed line that is not a measurement of this owner. Drawn dashed, and
  /// its caption must say what it is. See the library docstring.
  convention,
}

/// One horizontal line a series is read against.
@immutable
class ChartReference {
  /// The owner's own normal — a server-computed baseline and nothing else.
  const ChartReference.personalBaseline({
    required this.value,
    required this.label,
  }) : kind = ChartReferenceKind.personalBaseline;

  /// A published convention. [label] MUST name it as one; see the library
  /// docstring and `wearable_spo2_validity` D2.
  const ChartReference.convention({required this.value, required this.label})
    : kind = ChartReferenceKind.convention;

  /// Where the line sits, in the series' own units.
  final double value;

  /// The caption drawn UNDER the chart. Never painted in the plot — see the
  /// library docstring on why that is a rule and not a preference.
  final String label;

  /// Whose number this is.
  final ChartReferenceKind kind;

  /// Whether this line is drawn broken. See the library docstring.
  bool get isDashed => kind == ChartReferenceKind.convention;
}

/// The value→y mapping a series and its references MUST share.
///
/// The geometry is [HArea]'s, extracted so that extending that chart with a
/// reference could not quietly move the curve it has always drawn: the same 3 px
/// inset top and bottom, and the same 0.18 padding fraction **around the data**.
@immutable
class ChartScale {
  /// Prefer [ChartScale.of] or [ChartScale.window].
  const ChartScale(this.low, this.high);

  /// The scale that fits [data] **and every value in [include]**.
  ///
  /// [include] is what makes a reference honest rather than decorative: a line
  /// outside the data's own range widens the chart instead of clipping to an
  /// edge.
  ///
  /// ## The padding is asymmetric on purpose, and that is the 2026-08-06 repair
  ///
  /// [pad] is 18% of the DATA's span, and it exists so the curve does not touch
  /// the edges of its box. A reference below the data needs no such air — it is
  /// a straight line, not a peak that can be clipped — so padding it by the same
  /// 18% spends the plot on nothing. On the owner's own heart-rate day (60–75
  /// bpm against a resting rate of 56) the symmetric version handed 49% of the
  /// plot to empty space and the trace read as flat. Padding the reference side
  /// by [referencePadFraction] instead gives the data 59% of the height, and
  /// `test/features/vitals_scales_test.dart` holds that floor.
  ///
  /// With no references the result is byte-for-byte what it always was, because
  /// the data's own extremes then set both ends.
  factory ChartScale.of(
    List<double> data, {
    Iterable<double> include = const <double>[],
    double pad = padFraction,
  }) {
    final series = data.isNotEmpty ? data : include.toList();
    if (series.isEmpty) {
      return const ChartScale(0, 1);
    }
    var dataLow = series.first;
    var dataHigh = series.first;
    for (final value in series) {
      dataLow = math.min(dataLow, value);
      dataHigh = math.max(dataHigh, value);
    }
    var low = dataLow;
    var high = dataHigh;
    for (final value in include) {
      low = math.min(low, value);
      high = math.max(high, value);
    }
    final span = (dataHigh - dataLow) == 0 ? 1.0 : dataHigh - dataLow;
    return ChartScale(
      math.min(dataLow - span * pad, low - span * referencePadFraction),
      math.max(dataHigh + span * pad, high + span * referencePadFraction),
    );
  }

  /// A FIXED window from [low] to [high], widened only by what falls outside it.
  ///
  /// The difference from [ChartScale.of] is that this scale does not move when
  /// the data moves. That is the whole point of it, and it is a measurement
  /// argument rather than an aesthetic one: an auto-scale fitted to a fortnight
  /// of overnight SpO2 minimums resolves tenths of a percent, on a sensor whose
  /// error `wearable_spo2_validity` (#98) records as unquantified and **at least
  /// ±3.5%**. A chart that rescales to that noise draws the noise as a trend,
  /// and draws a different trend every night from the same body.
  ///
  /// Nothing is ever hidden: a value outside the window widens the window, and
  /// the caller says so on the card (`blood_oxygen_card.dart`).
  factory ChartScale.window(
    List<double> data, {
    required double low,
    required double high,
    Iterable<double> include = const <double>[],
  }) {
    var bottom = low;
    var top = high;
    for (final value in <double>[...data, ...include]) {
      bottom = math.min(bottom, value);
      top = math.max(top, value);
    }
    return ChartScale(bottom, top);
  }

  /// The bottom of the plot, in the series' units.
  final double low;

  /// The top of the plot, in the series' units.
  final double high;

  /// Legacy's `yPad`, applied around the DATA. See [ChartScale.of].
  static const double padFraction = 0.18;

  /// The air left beyond a reference that sits outside the data's own range.
  ///
  /// Small on purpose: a horizontal line only has to be visibly clear of the
  /// edge, and every unit spent here is a unit the reading does not get.
  static const double referencePadFraction = 0.06;

  /// Legacy's 3 px of air above and below the plotted range.
  static const double inset = 3;

  /// Where [value] sits in a plot [height] px tall.
  double y(double value, double height) =>
      height - inset - ((value - low) / (high - low)) * (height - inset * 2);

  /// The share of a [height]-tall plot that a series spanning [low]..[high] owns.
  ///
  /// The measurement behind "the trace looks flat": a chart whose reading uses a
  /// third of its own box is a chart about its padding.
  double share(double seriesLow, double seriesHigh, double height) =>
      (y(seriesLow, height) - y(seriesHigh, height)) / height;
}

/// Draws [reference] across the plot in [scale], fading in with [progress].
///
/// A LINE AND NOTHING ELSE. [color] is the caller's quiet ink — see the library
/// docstring on why it is never a verdict token, and on why the caption is a
/// widget ([ChartReferenceCaption]) rather than ink in the plot.
void paintChartReference(
  Canvas canvas,
  Size size,
  ChartReference reference, {
  required ChartScale scale,
  required Color color,
  required double progress,
}) {
  final y = scale.y(reference.value, size.height);
  if (!y.isFinite) {
    return;
  }
  final paint = Paint()
    ..color = revealed(color, progress)
    ..strokeWidth = 1;
  if (reference.isDashed) {
    for (var x = 0.0; x < size.width; x += _dash + _dashGap) {
      final end = (x + _dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  } else {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
}

/// Names the lines drawn on the chart above, in the module's own foot voice.
///
/// This is the other half of [paintChartReference]: the words that used to be
/// painted across the data. An empty list draws nothing at all — a caption slot
/// held open for a reference the server did not send would be a blank line the
/// reader has to interpret.
class ChartReferenceCaption extends StatelessWidget {
  /// [references] are the same objects the chart above was given, in order.
  const ChartReferenceCaption(this.references, {super.key});

  /// The lines this caption names.
  final List<ChartReference> references;

  /// Enough air that the caption cannot be read as part of the plot, and few
  /// enough pixels that it is still read as belonging to it.
  static const EdgeInsets _padding = EdgeInsets.only(top: 5);

  @override
  Widget build(BuildContext context) {
    if (references.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Padding(
      padding: _padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final reference in references)
            Semantics(
              label: reference.label,
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ReferenceSwatch(dashed: reference.isDashed),
                    const SizedBox(width: Insets.xs + 2),
                    // Caps are the module foot's voice; the semantic label above
                    // carries the sentence as written, because several screen
                    // readers spell an all-caps run out letter by letter.
                    Flexible(
                      child: Text(
                        reference.label.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HType.label(colors.ink2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A 12 px sample of the line this caption names, in the line's own ink.
///
/// The one thing on the card that says WHICH mark the words are about, and the
/// only place the solid/dashed distinction is visible at caption size. Drawn
/// from [HealtheeColors.reference], so a swatch cannot disagree with the rule
/// [paintChartReference] drew.
class _ReferenceSwatch extends StatelessWidget {
  const _ReferenceSwatch({required this.dashed});

  /// Whether the line it samples is broken. [ChartReference.isDashed].
  final bool dashed;

  /// Wide enough to read as a line rather than as a dot, narrow enough that it
  /// never competes with the words beside it.
  static const double width = 12;

  @override
  Widget build(BuildContext context) {
    final rule = ColoredBox(color: context.colors.reference);
    return SizedBox(
      width: width,
      height: hairline,
      child: dashed
          // The painter's own 3-on-3-off, at this width: two dashes and a gap.
          ? Row(
              children: [
                Expanded(child: rule),
                const Spacer(),
                Expanded(child: rule),
              ],
            )
          : rule,
    );
  }
}

const double _dash = 3;
const double _dashGap = 3;
