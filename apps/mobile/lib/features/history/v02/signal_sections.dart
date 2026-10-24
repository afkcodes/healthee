/// The Health signals screen's furniture: the summary strip, the legend line
/// and one group (label row over a single card of hairline-divided rows).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/features/history/v02/signal_row_view.dart';
import 'package:healthee/features/history/v02/signal_rows.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// "5 signals", "1 signal".
String signalCount(int n) => '$n ${n == 1 ? 'signal' : 'signals'}';

/// How many rows are shown, outside their usual, and unread.
@immutable
class SignalTally {
  /// Counts [groups]. Outside is worse or watch; a goal missed is worse.
  factory SignalTally.of(List<SignalGroup> groups) {
    var total = 0;
    var outside = 0;
    var none = 0;
    for (final group in groups) {
      for (final row in group.rows) {
        total++;
        switch (row.judgement.state) {
          case ReadingState.worse || ReadingState.watch:
            outside++;
          case ReadingState.noData:
            none++;
          case ReadingState.better || ReadingState.usual:
            break;
        }
      }
    }
    return SignalTally._(total, outside, none);
  }

  const SignalTally._(this.signals, this.outside, this.noReading);

  /// Rows shown.
  final int signals;

  /// Rows worse than, or outside, their usual.
  final int outside;

  /// Rows with no reading.
  final int noReading;
}

/// Three equal cells in one surface card, hairlines between.
class SignalSummary extends StatelessWidget {
  /// Builds the strip.
  const SignalSummary({required this.tally, super.key});

  /// The counts.
  final SignalTally tally;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget cell(int n, String label, Color colour) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$n', style: TypeLadder.title1.copyWith(color: colour)),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
          ],
        ),
      ),
    );
    Widget rule() => VerticalDivider(
      width: hairline,
      thickness: hairline,
      color: colors.line,
    );
    return Container(
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(Radii.card),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            cell(tally.signals, 'signals', colors.ink),
            rule(),
            cell(
              tally.outside,
              'outside usual',
              tally.outside > 0 ? colors.alert : colors.ink,
            ),
            rule(),
            cell(tally.noReading, 'no reading', colors.ink2),
          ],
        ),
      ),
    );
  }
}

/// "▭ your usual range   trend = last 14 days".
class SignalLegend extends StatelessWidget {
  /// Builds the line.
  const SignalLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TypeLadder.caption.copyWith(color: colors.ink2);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Insets.lg,
      runSpacing: Insets.xs,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 16,
              height: 8,
              decoration: BoxDecoration(
                color: colors.band,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Text('your usual range', style: style),
          ],
        ),
        Text('trend = last $kSignalSparkDays days', style: style),
      ],
    );
  }
}

/// A domain's label row and its card of rows.
class SignalGroupView extends StatelessWidget {
  /// Draws [group]; [onOpen] opens a row's history.
  const SignalGroupView({required this.group, this.onOpen, super.key});

  /// The domain.
  final SignalGroup group;

  /// Opens one metric's history.
  final void Function(String metric)? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ToneScope(
      tone: group.tone,
      child: Builder(
        builder: (context) {
          final family = context.family;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.md),
                child: Row(
                  children: <Widget>[
                    Icon(group.icon, size: 16, color: family),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        group.label,
                        style: TypeLadder.headline.copyWith(color: family),
                      ),
                    ),
                    Text(
                      signalCount(group.rows.length),
                      style: TypeLadder.caption.copyWith(color: colors.ink2),
                    ),
                  ],
                ),
              ),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: colors.surface,
                  shape: hSquircle(Radii.card),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var i = 0; i < group.rows.length; i++) ...<Widget>[
                      if (i > 0)
                        Divider(
                          height: hairline,
                          thickness: hairline,
                          color: colors.line,
                        ),
                      SignalRowView(row: group.rows[i], onOpen: onOpen),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
