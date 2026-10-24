/// `Every yes, checked`: each idea the owner said yes to, and what the strap
/// says happened. Reads `/api/coach/ledger` for the chosen window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/features/coach/v02/ledger_pattern_card.dart';
import 'package:healthee/features/coach/v02/ledger_summary_card.dart';
import 'package:healthee/features/coach/v02/ledger_week_view.dart';
import 'package:healthee/shared/format/date_range.dart';
import 'package:healthee/shared/states/account_async_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/back_label_head.dart';
import 'package:healthee/shared/v02/choices.dart';
import 'package:healthee/shared/v02/detail_page.dart';

/// The screen's title.
const String kEveryYesTitle = 'Every yes, checked';

/// The ledger screen.
class EveryYesScreen extends ConsumerStatefulWidget {
  /// Opens on the month, as the design does.
  const EveryYesScreen({super.key});

  @override
  ConsumerState<EveryYesScreen> createState() => _EveryYesScreenState();
}

class _EveryYesScreenState extends ConsumerState<EveryYesScreen> {
  LedgerWindow _window = LedgerWindow.month;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(coachLedgerProvider(_window));
    final colors = context.colors;
    final ledger = value.hasValue ? value.value : null;
    return DetailPage(
      title: kEveryYesTitle,
      head: (context, onBack) => BackLabelHead(
        backLabel: 'Coach',
        title: kEveryYesTitle,
        onBack: onBack,
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 216,
              child: Segment<LedgerWindow>(
                options: const <(LedgerWindow, String)>[
                  (LedgerWindow.week, 'Week'),
                  (LedgerWindow.month, 'Month'),
                  (LedgerWindow.all, 'All'),
                ],
                selected: _window,
                onSelect: (w) => setState(() => _window = w),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Text(
                ledger == null || ledger.from.isEmpty
                    ? ''
                    : dateRangeLabel(ledger.from, ledger.to),
                textAlign: TextAlign.end,
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        AccountAsyncView<CoachLedger>(
          value: value,
          onRetry: () => ref.invalidate(coachLedgerProvider(_window)),
          builder: (context, ledger) => _Ledger(ledger: ledger),
        ),
      ],
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.ledger});

  final CoachLedger ledger;

  @override
  Widget build(BuildContext context) {
    if (ledger.isEmpty) {
      return const EmptyState(
        message: 'No yeses to check yet',
        hint:
            'When you say yes to one of the coach ideas, it lands here with '
            'what the strap saw.',
      );
    }
    final pattern = ledger.pattern;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LedgerSummaryCard(ledger: ledger),
        for (final week in ledger.weeks) ...<Widget>[
          const SizedBox(height: Insets.section),
          LedgerWeekView(week: week),
        ],
        if (pattern != null) ...<Widget>[
          const SizedBox(height: Insets.section),
          LedgerPatternCard(text: pattern),
        ],
      ],
    );
  }
}
