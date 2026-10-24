/// `Your intentions.` — `screens-actions.js::H.screens['action-history']`.
///
/// ```text
///   header (detail)  "Action history · 30 days" · "Your intentions."
///   small            adopting records an intention, not a completed action
///   segment          30 · 90 · 180 days
///   section <day>    the action, its state, the evidence, the control
///   section          Keep exploring → active challenges · completed outcomes
///   footer
/// ```
///
/// ## The sentence at the top is the screen's whole point
///
/// The prototype writes it and the server means it: `adopted` records that the
/// owner said they would try something. Nothing in this app observes whether they
/// did. A history that showed ticks without that line would be a log of
/// completions nobody measured.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/recommendations/recommendation_history.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/actions/v02/evidence_sheet.dart';
import 'package:healthee/features/actions/v02/suggestion_card.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/server_action_button.dart';
import 'package:healthee/shared/states/account_async_view.dart';
import 'package:healthee/shared/states/grounded_text.dart';
import 'package:healthee/shared/v02/choices.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/rows.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:healthee/shared/v02/view_day.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's own h1.
const String kHistoryTitle = 'Your intentions.';

/// The sentence under it, verbatim.
const String kIntentionNote =
    'Adopting a suggestion records your intention. It doesn’t mean the action '
    'was completed.';

/// The prototype's closing section heading.
const String kExploreHeading = 'Keep exploring';

/// `screens['action-history']`'s own past-day heading.
const String kNoEarlierTitle = 'No earlier suggestions';

/// And what that is a fact about.
const String kNoEarlierBody =
    'Nothing in this window is dated on or before the day you are viewing. '
    'Choose Latest to see the most recent suggestions.';

/// The dated recommendations, and what the owner said about each.
class RecommendationHistoryScreen extends ConsumerStatefulWidget {
  /// Reads `recommendationHistoryProvider` for the chosen window and page.
  const RecommendationHistoryScreen({super.key});

  @override
  ConsumerState<RecommendationHistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<RecommendationHistoryScreen> {
  int _days = 30;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final provider = recommendationHistoryProvider(_days, _page);
    final ViewDay day = watchViewDay(ref);
    return DetailPage(
      // The window this list covers is on the segment control below, so the
      // head says the one thing only it can: which day the list ends on.
      eyebrow: day.line,
      title: kHistoryTitle,
      children: <Widget>[
        Text(
          kIntentionNote,
          style: TypeScale.small.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: Insets.lg),
        Segment<int>(
          options: const <(int, String)>[
            (30, '30 days'),
            (90, '90 days'),
            (180, '180 days'),
          ],
          selected: _days,
          onSelect: (days) => setState(() {
            _days = days;
            _page = 0;
          }),
        ),
        AccountAsyncView<List<DatedRecommendation>>(
          value: ref.watch(provider),
          onRetry: () => ref.invalidate(provider),
          builder: (context, items) => _list(_through(items, day), day),
        ),
        const SizedBox(height: SectionHead.sectionGap),
        const SectionHead(title: kExploreHeading),
        RowCard(<Widget>[
          ListRow(
            icon: SolarIconsOutline.flag,
            title: 'Active challenges',
            subtitle: 'Turn an intention into a measured experiment',
            tone: Tone.movement,
            onTap: () => context.go(Routes.actions),
          ),
          ListRow(
            icon: SolarIconsOutline.chartSquare,
            title: 'Every yes, checked',
            subtitle: 'What the strap saw for each one',
            tone: Tone.fitness,
            onTap: () => unawaited(context.push(Routes.coachLedger)),
          ),
        ]),
        const DataFooter(),
      ],
    );
  }

  /// The history, ending on the day being read.
  ///
  /// `H.historySeries` filters every history view to `date <= viewDate`, and a
  /// suggestion written after the chosen day is not something that day was
  /// told. Each row already carries its own date, so nothing here is relabelled
  /// — the list is only cut short.
  static List<DatedRecommendation> _through(
    List<DatedRecommendation> items,
    ViewDay day,
  ) => <DatedRecommendation>[
    for (final item in items)
      if (item.day.compareTo(day.day) <= 0) item,
  ];

  Widget _list(List<DatedRecommendation> items, ViewDay day) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (items.isEmpty && day.isPast)
        const PastDayNotice(title: kNoEarlierTitle, body: kNoEarlierBody),
      for (final item in items) ...<Widget>[
        const SizedBox(height: SectionHead.sectionGap),
        SectionHead(title: item.day),
        _Entry(item: item, onChanged: _reread),
      ],
      _Paging(
        page: _page,
        count: items.length,
        onPage: (page) => setState(() => _page = page),
      ),
    ],
  );

  void _reread() {
    ref.invalidate(recommendationHistoryProvider);
    ref.invalidate(todaySnapshotProvider);
  }
}

/// One dated recommendation: what was suggested, and what was said about it.
class _Entry extends ConsumerWidget {
  const _Entry({required this.item, required this.onChanged});

  final DatedRecommendation item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final rec = item.recommendation;
    final adopted = rec.adopted;
    final grounding = rec.grounding;
    return SurfaceCard(
      tone: toneForCategory(rec.category),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: GroundedProse(
                  text: rec.action,
                  style: TypeScale.rowTitle.copyWith(color: colors.ink),
                ),
              ),
              const SizedBox(width: Insets.sm),
              StatusBadge(switch (adopted) {
                true => 'Adopted',
                false => 'Dismissed',
                null => 'Suggested',
              }, accented: adopted ?? false),
            ],
          ),
          if (signalLabel(rec.signalSource) case final String raised) ...[
            const SizedBox(height: Insets.sm),
            Text(
              raised,
              style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
            ),
          ],
          // The dated card's own ⓘ. Drawn whenever there is something behind
          // this rec, rationale or not — see `suggestion_card.dart`.
          if (rec.rationale != null ||
              grounding.isNotEmpty ||
              rec.gradeLabel != null)
            TextLink(
              label: 'How we know',
              icon: SolarIconsOutline.infoCircle,
              onPressed: () => showEvidenceSheet(
                context,
                title: kWhyTitle,
                prose: rec.rationale ?? '',
                grounding: grounding,
                grade: rec.gradeLabel,
              ),
            ),
          // No id, no control: there is nowhere to write the decision to.
          if (rec.id case final int id)
            AccountAsyncView<AccountApi>(
              value: ref.watch(accountApiProvider),
              onRetry: () => ref.invalidate(accountApiProvider),
              builder: (context, api) => ServerActionButton(
                key: ObjectKey(api),
                label: (adopted ?? false)
                    ? 'Remove intention'
                    : 'Adopt suggestion',
                action: () async {
                  await setRecommendationAdoption(
                    api,
                    id,
                    (adopted ?? false) ? 'dismiss' : 'adopt',
                  );
                  return null;
                },
                onSaved: onChanged,
              ),
            ),
        ],
      ),
    );
  }
}

/// Previous / next, and the one sentence an empty page owes the reader.
class _Paging extends StatelessWidget {
  const _Paging({
    required this.page,
    required this.count,
    required this.onPage,
  });

  /// The server's page size. `Next` is offered only on a full page.
  static const int pageSize = 100;

  final int page;
  final int count;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (count == 0) ...<Widget>[
          const SizedBox(height: Insets.lg),
          Text(
            'No actions in this part of your history.',
            style: TypeScale.small.copyWith(color: colors.ink2),
          ),
        ],
        if (page > 0 || count == pageSize)
          Padding(
            padding: const EdgeInsets.only(top: Insets.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextLink(
                  label: 'Previous',
                  icon: SolarIconsOutline.arrowLeft,
                  onPressed: page > 0 ? () => onPage(page - 1) : null,
                ),
                Text(
                  'Page ${page + 1}',
                  style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
                ),
                TextLink(
                  label: 'Next',
                  onPressed: count == pageSize ? () => onPage(page + 1) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
