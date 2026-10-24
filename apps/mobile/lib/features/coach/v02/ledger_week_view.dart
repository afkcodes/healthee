/// One week of the ledger: its header, and either the "No yeses" row or the
/// cards of entries grouped by day.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/features/coach/v02/ledger_entry_row.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/date_range.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// A week.
class LedgerWeekView extends StatelessWidget {
  /// Draws [week].
  const LedgerWeekView({required this.week, super.key});

  /// The week.
  final LedgerWeek week;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = <List<LedgerEntry>>[];
    for (final entry in week.entries) {
      if (days.isNotEmpty && days.last.first.date == entry.date) {
        days.last.add(entry);
      } else {
        days.add(<LedgerEntry>[entry]);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xs,
            0,
            Insets.xs,
            Insets.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  dateRangeLabel(week.from, week.to),
                  style: TypeLadder.callout.copyWith(color: colors.ink2),
                ),
              ),
              Text(
                '${week.yeses} of ${week.ideasGiven}',
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
            ],
          ),
        ),
        if (week.yeses == 0 || days.isEmpty)
          _NoYeses(week: week)
        else
          for (var i = 0; i < days.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: Insets.cardGap),
            _DayCard(entries: days[i]),
          ],
      ],
    );
  }
}

class _NoYeses extends StatelessWidget {
  const _NoYeses({required this.week});

  final LedgerWeek week;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final skipped = week.skipped;
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(Radii.card),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'No yeses this week',
              style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
            ),
          ),
          const SizedBox(width: Insets.sm),
          Text(
            week.ideasGiven == 0
                ? 'No ideas given'
                : '$skipped ${skipped == 1 ? 'idea' : 'ideas'} skipped',
            style: TypeLadder.body.copyWith(color: colors.ink2),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.entries});

  final List<LedgerEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            shortDate(entries.first.date),
            style: TypeLadder.callout.copyWith(color: colors.ink2),
          ),
          for (var i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.md),
                child: Divider(
                  height: hairline,
                  thickness: hairline,
                  color: colors.line,
                ),
              )
            else
              const SizedBox(height: Insets.md),
            LedgerEntryRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}
