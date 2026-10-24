/// "Your record": what the owner said yes to and what the strap says happened.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/data/coach/review_week.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/coach/v02/home_head.dart';
import 'package:healthee/features/coach/v02/ledger_bar.dart';
import 'package:healthee/shared/states/account_async_view.dart';
import 'package:healthee/shared/v02/choices.dart';
import 'package:healthee/shared/v02/reading_state.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The caption under the bar, or null when there is nothing true to say.
///
/// [lastWeek] is the Monday-to-Sunday week before the one containing [today],
/// when the ledger has it.
String? recordCaption(CoachLedger ledger, String today) {
  final day = DateTime.tryParse(today);
  LedgerWeek? last;
  if (day != null) {
    final monday = mondayOf(day);
    final previous = isoDay(
      DateTime(monday.year, monday.month, monday.day - 7),
    );
    for (final week in ledger.weeks) {
      if (week.from == previous) {
        last = week;
      }
    }
  }
  final unchecked = ledger.totals.noProof;
  return <String>[
    if (unchecked > 0) "$unchecked couldn't be checked.",
    if (last != null)
      'Last week: ${last.ideasGiven} ${last.ideasGiven == 1 ? 'idea' : 'ideas'}, '
          '${last.yeses} ${last.yeses == 1 ? 'yes' : 'yeses'}.',
  ].join(' ');
}

/// The section, with its own Week or Month choice (Month first).
class CoachRecordSection extends ConsumerStatefulWidget {
  /// Opens on the month.
  const CoachRecordSection({super.key});

  @override
  ConsumerState<CoachRecordSection> createState() => _CoachRecordSectionState();
}

class _CoachRecordSectionState extends ConsumerState<CoachRecordSection> {
  LedgerWindow _window = LedgerWindow.month;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(coachLedgerProvider(_window));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CoachSectionHead.text(
          context,
          'Your record',
          trailing: SizedBox(
            width: 176,
            child: Segment<LedgerWindow>(
              options: const <(LedgerWindow, String)>[
                (LedgerWindow.week, 'Week'),
                (LedgerWindow.month, 'Month'),
              ],
              selected: _window,
              onSelect: (w) => setState(() => _window = w),
            ),
          ),
        ),
        AccountAsyncView<CoachLedger>(
          value: value,
          onRetry: () => ref.invalidate(coachLedgerProvider(_window)),
          builder: (context, ledger) =>
              RecordCard(ledger: ledger, today: ref.watch(todayProvider)),
        ),
      ],
    );
  }
}

/// The card: four numbers, the bar, the caption.
class RecordCard extends StatelessWidget {
  /// Draws [ledger] as of [today].
  const RecordCard({required this.ledger, required this.today, super.key});

  /// The response.
  final CoachLedger ledger;

  /// The owner's day, ISO.
  final String today;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = recordCaption(ledger, today);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Figure(
                  value: ledger.ideasGiven,
                  label: 'ideas given',
                  state: null,
                ),
                const _Rule(),
                _Figure(
                  value: ledger.yeses,
                  label: 'you said yes',
                  state: null,
                ),
                const _Rule(),
                _Figure(
                  value: ledger.totals.done,
                  label: 'done',
                  state: ReadingState.better,
                ),
                const _Rule(),
                _Figure(
                  value: ledger.totals.missed,
                  label: 'missed',
                  state: ReadingState.worse,
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          LedgerBar(totals: ledger.totals),
          if (caption != null && caption.isNotEmpty) ...<Widget>[
            const SizedBox(height: Insets.md),
            Text(
              caption,
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.state,
  });

  final int value;
  final String label;

  /// Judged colour for done and missed; plain ink for the counts.
  final ReadingState? state;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$value',
              style: TypeLadder.metric.copyWith(
                color: state?.colourIn(context.colors) ?? context.colors.ink,
              ),
            ),
          ),
          Text(
            label,
            style: TypeLadder.callout.copyWith(color: context.colors.ink2),
          ),
        ],
      ),
    ),
  );
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      Container(width: hairline, color: context.colors.line);
}
