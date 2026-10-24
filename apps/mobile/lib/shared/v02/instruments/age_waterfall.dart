/// **The age waterfall** — chronological age, each contribution as a step, and
/// the estimate the steps land on.
///
/// The prototype's own note, from `README.md`: *"The biological-age waterfall
/// shows the actual reconciled calculation: 36 - 1.7 fitness + 0.0 sleep = 34.3.
/// Excluded regularity is separate."*
///
/// ## The excluded term is the whole reason this is a bespoke instrument
///
/// Three states look identical to a bar chart and mean three different things:
///
///   * **measured, and it moved the estimate** — a bar, and its size is the size
///     of the effect;
///   * **measured, and it moved nothing** — a 3 px stub labelled `+0.0y`. The
///     term was computed, the answer was zero, and that is a finding;
///   * **excluded** — the term could not be converted into years at all. It gets
///     **no bar of any height**, the word `excluded`, and the running level
///     drawn straight through it, because a zero-height bar reads as the second
///     case and it is not.
///
/// `age_instruments_test.dart` mutation-tests exactly that boundary: rendering
/// an exclusion as a minimum-height bar must fail the suite, because a stub
/// passing as an exclusion is the failure this instrument exists to prevent.
///
/// ## The ladder is not snapped to the estimate
///
/// The steps are drawn from the deltas and the estimate bar is drawn from the
/// estimate. When they reconcile, the last connector arrives exactly at the top
/// of the estimate bar; when the server's numbers disagree, the connector
/// arrives somewhere else and the reader can see it. Snapping the ladder onto
/// the estimate would draw a reconciliation that had not happened.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/v02/instruments/instrument_geometry.dart';

/// The shortest bar a measured contribution may draw. A measured zero is still
/// visible; see the library docstring.
const double kAgeStubHeight = 3;

/// What one column of the ladder knows about its term.
enum AgeTermState {
  /// The term was computed and is worth this many years.
  measured,

  /// The term could not be converted into years at all.
  excluded,

  /// The term has no value yet. Draws nothing, keeps its slot.
  missing,
}

/// One term of the estimate.
@immutable
class AgeTerm {
  /// A term worth [deltaYears]. Zero is a legitimate measurement.
  const AgeTerm.measured(this.label, this.deltaYears, {this.tone})
    : state = AgeTermState.measured;

  /// A term that cannot be expressed in years, and says so.
  const AgeTerm.excluded(this.label, {this.tone})
    : deltaYears = null,
      state = AgeTermState.excluded;

  /// A term with no value. Draws nothing and keeps its column.
  const AgeTerm.missing(this.label, {this.tone})
    : deltaYears = null,
      state = AgeTermState.missing;

  /// The column's name.
  final String label;

  /// Years added or removed. Null unless [state] is [AgeTermState.measured].
  final double? deltaYears;

  /// Which term this is.
  final AgeTermState state;

  /// The family this term belongs to — sleep's terms are violet wherever they
  /// are drawn. Null resolves the enclosing [ToneScope], like everything else.
  final Tone? tone;
}

/// Chronological age, the contributions, and the estimate — as one ladder.
class AgeWaterfall extends StatelessWidget {
  /// Builds the ladder.
  const AgeWaterfall({
    required this.chronologicalAge,
    required this.estimate,
    required this.terms,
    this.progress = 1,
    this.height = defaultHeight,
    super.key,
  });

  /// Identifies the plot for tests.
  static const Key plotKey = ValueKey<String>('age-waterfall-plot');

  /// `charts-detail.js`: `svg(body, …, 176)`.
  static const double defaultHeight = 176;

  /// The band under the plot that holds the column names.
  static const double labelBand = 31;

  /// The gap above the tallest bar, for its value label.
  static const double plotTop = 19;

  /// The owner's actual age.
  final double chronologicalAge;

  /// The estimate the terms are supposed to reconcile to.
  final double estimate;

  /// The contributions, in the order they are applied.
  final List<AgeTerm> terms;

  /// Reveal progress, 0-1. Bars grow from the level they start at.
  final double progress;

  /// The instrument's height.
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hues = Theme.of(context).extension<InstrumentHues>()!;
    final fallback = context.tone;
    return SizedBox(
      height: height,
      child: CustomPaint(
        key: plotKey,
        painter: _AgeWaterfallPainter(
          columns: _columns(hues, fallback),
          progress: progress.clamp(0.0, 1.0),
          ink: colors.ink,
          ink2: colors.ink2,
          grid: colors.grid,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// Turns the terms into drawable columns, resolving every family through the
  /// tone system — no caller ever hands this instrument a colour.
  List<_Column> _columns(InstrumentHues hues, Tone fallback) {
    final columns = <_Column>[
      _Column(
        label: 'Actual',
        from: null,
        to: chronologicalAge,
        valueLabel: formatYears(chronologicalAge),
        colour: Tone.oxygen.family(hues),
        state: AgeTermState.measured,
      ),
    ];
    var running = chronologicalAge;
    for (final term in terms) {
      final delta = term.deltaYears;
      final colour = (term.tone ?? fallback).family(hues);
      if (term.state != AgeTermState.measured || delta == null) {
        columns.add(
          _Column(
            label: term.label,
            from: running,
            to: null,
            valueLabel: term.state == AgeTermState.excluded ? 'excluded' : null,
            colour: colour,
            state: term.state,
          ),
        );
        continue;
      }
      columns.add(
        _Column(
          label: term.label,
          from: running,
          to: running + delta,
          valueLabel: '${formatYears(delta, signed: true)}y',
          colour: colour,
          state: AgeTermState.measured,
        ),
      );
      running += delta;
    }
    columns.add(
      _Column(
        label: 'Estimate',
        from: null,
        to: estimate,
        valueLabel: formatYears(estimate),
        colour: fallback.family(hues),
        state: AgeTermState.measured,
      ),
    );
    return columns;
  }
}

/// One drawn column. `from` of null means "from the floor of the plot".
@immutable
class _Column {
  const _Column({
    required this.label,
    required this.from,
    required this.to,
    required this.valueLabel,
    required this.colour,
    required this.state,
  });

  final String label;
  final double? from;
  final double? to;
  final String? valueLabel;
  final Color colour;
  final AgeTermState state;

  /// The running level after this column. An exclusion changes nothing.
  double levelAfter(double running) => to ?? running;
}

class _AgeWaterfallPainter extends CustomPainter {
  const _AgeWaterfallPainter({
    required this.columns,
    required this.progress,
    required this.ink,
    required this.ink2,
    required this.grid,
  });

  final List<_Column> columns;
  final double progress;
  final Color ink;
  final Color ink2;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || columns.isEmpty) {
      return;
    }
    final values = <double>[
      for (final column in columns)
        if (column.to != null) column.to!,
      for (final column in columns)
        if (column.from != null) column.from!,
    ];
    final low = (values.reduce((a, b) => a < b ? a : b) - 1).floorToDouble();
    final high = (values.reduce((a, b) => a > b ? a : b) + 1).ceilToDouble();
    final span = high - low < 4 ? 4.0 : high - low;
    final bottom = size.height - AgeWaterfall.labelBand;
    final plot = bottom - AgeWaterfall.plotTop;
    double y(double value) => bottom - (value - low) / span * plot;

    final axisStyle = TypeScale.colourKey.copyWith(color: ink2);
    final gutter = chartLabel(formatYears(high), axisStyle).width + 6;
    const left = 4.0;
    final right = size.width - gutter;
    _paintGrid(canvas, y, low, span, left, right, size.width, axisStyle);

    final pitch = (right - left) / columns.length;
    final barWidth = pitch * 0.55;
    var running = columns.first.to ?? low;
    for (var i = 0; i < columns.length; i++) {
      final column = columns[i];
      final x = left + pitch * i + (pitch - barWidth) / 2;
      _paintColumn(canvas, column, y, x, barWidth, bottom, low, running);
      final next = column.levelAfter(running);
      if (i < columns.length - 1) {
        drawDashed(
          canvas,
          Offset(x + barWidth, y(next)),
          Offset(left + pitch * (i + 1) + (pitch - barWidth) / 2, y(next)),
          Paint()
            ..color = grid
            ..strokeWidth = 1,
        );
      }
      running = next;
      paintLabel(
        canvas,
        chartLabel(column.label, axisStyle),
        Offset(x + barWidth / 2, bottom + 9),
        anchor: LabelAnchor.middle,
      );
    }
  }

  void _paintGrid(
    Canvas canvas,
    double Function(double) y,
    double low,
    double span,
    double left,
    double right,
    double width,
    TextStyle style,
  ) {
    final step = (span / 4).ceilToDouble();
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var value = low; value <= low + span + 0.001; value += step) {
      drawDashed(canvas, Offset(left, y(value)), Offset(right, y(value)), line);
      paintLabel(
        canvas,
        chartLabel(formatYears(value), style),
        Offset(width, y(value) - 5),
        anchor: LabelAnchor.end,
      );
    }
  }

  void _paintColumn(
    Canvas canvas,
    _Column column,
    double Function(double) y,
    double x,
    double barWidth,
    double bottom,
    double low,
    double running,
  ) {
    final valueStyle = TypeScale.colourKey.copyWith(color: ink);
    final to = column.to;
    if (to == null) {
      // Excluded or missing: NO BAR, at any height. The level runs straight on.
      if (column.state == AgeTermState.excluded) {
        drawDashed(
          canvas,
          Offset(x, y(running)),
          Offset(x + barWidth, y(running)),
          Paint()
            ..color = ink2
            ..strokeWidth = 1,
        );
        paintLabel(
          canvas,
          chartLabel(
            column.valueLabel!,
            TypeScale.colourKey.copyWith(color: ink2),
          ),
          Offset(x + barWidth / 2, y(running) - 16),
          anchor: LabelAnchor.middle,
        );
      }
      return;
    }
    final anchor = column.from == null ? bottom : y(column.from!);
    var far = y(to);
    if ((far - anchor).abs() < kAgeStubHeight) {
      far = anchor + (far <= anchor ? -kAgeStubHeight : kAgeStubHeight);
    }
    final edge = anchor + (far - anchor) * progress;
    final rect = Rect.fromLTRB(
      x,
      edge < anchor ? edge : anchor,
      x + barWidth,
      edge < anchor ? anchor : edge,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = revealed(column.colour, progress),
    );
    final label = column.valueLabel;
    if (label != null) {
      paintLabel(
        canvas,
        chartLabel(label, valueStyle),
        Offset(x + barWidth / 2, rect.top - 14),
        anchor: LabelAnchor.middle,
      );
    }
  }

  @override
  bool shouldRepaint(_AgeWaterfallPainter old) =>
      old.progress != progress ||
      old.columns != columns ||
      old.ink != ink ||
      old.grid != grid;
}
