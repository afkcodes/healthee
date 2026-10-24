/// **Every surface that draws model prose hands that prose's sources to an ⓘ.**
///
/// The sweep in `citation_sweep_test.dart` proves no card draws a chip. Alone,
/// it is satisfied by deleting the grounding — which is the outcome this product
/// exists to prevent, and the reason `grounded_text.dart` spends four paragraphs
/// arguing that a strip helper makes dropping the evidence one character cheaper
/// than keeping it.
///
/// This file is the other half, and it is per call site rather than per screen.
/// A screen-level suite can only cover screens somebody wrote a suite for, and
/// the surfaces here are the ones the sweep just took chips off: Sleep's lever,
/// its timing action and its analysis, Actions' suggestions and challenges, the
/// coach, Today's rows and every disclosure.
///
/// The assertion is the same everywhere: **whatever `parseGrounded` finds in the
/// prose the surface drew, its ⓘ is carrying.** Not a fixed list — the parse
/// itself, so a surface cannot pass by citing a hard-coded id it does not
/// actually render.
///
/// The three things this move could lose quietly are in
/// `prose_grounding_loss_test.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/insights/generated_insight.dart';
import 'package:healthee/data/insights/insight_repository.dart';
import 'package:healthee/data/models/recommendation.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_insight.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/features/actions/v02/challenge_card.dart';
import 'package:healthee/features/actions/v02/suggestion_card.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:healthee/features/coach/widgets/coach_thread.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';
import 'package:healthee/features/sleep/v02/timing_panel.dart';
import 'package:healthee/features/today/widgets/actions_section.dart';
import 'package:healthee/shared/format/note_names.dart';
import 'package:healthee/shared/insight_card.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/reasoning_note.dart';
import '_citation_probe.dart';
import '_prose_fixtures.dart';

void main() {
  group('every prose surface hands its sources to an ⓘ', () {
    testWidgets('the v02 suggestion card — all three of its fields', (
      tester,
    ) async {
      await pumpAt(
        tester,
        390,
        ProviderScope(child: SuggestionCard(recommendation: kRec)),
      );
      // This card's ⓘ is the prototype's own `H.evidence()` text button, so the
      // sheet is opened rather than read off a dot.
      // The link became a dot on the eyebrow; the sheet behind it is unchanged.
      await tester.tap(find.bySemanticsLabel(kWhyLabel));
      await tester.pumpAndSettle();

      for (final id in kRec.grounding.noteIds) {
        expect(
          find.text(noteName(id)!),
          findsOneWidget,
          reason: '"$id" is cited by this suggestion and is not in its sheet',
        );
      }
      expect(find.text('Probable'), findsOneWidget, reason: 'the proved grade');
    });

    testWidgets('Today’s action row', (tester) async {
      // Drawn on its own: the section only builds rows once expanded, and the
      // row is what carries the rec's ⓘ.
      await pumpAt(tester, 390, ActionRow(recommendation: kRec));

      expectGrounds(
        tester,
        ActionRow,
        '${kRec.action} ${kRec.rationale} ${kRec.expectedEffect}',
        alsoCites: kRec.researchNoteIds,
      );
    });

    testWidgets('Today’s block head, for the daily line', (tester) async {
      const daily = 'Take a short walk today [exercise_mortality].';
      await pumpAt(
        tester,
        390,
        const ActionsSection(
          recommendations: <Recommendation>[],
          action: daily,
        ),
      );

      expectGrounds(tester, ActionsSection, daily);
    });

    testWidgets('the v02 challenge card', (tester) async {
      await pumpAt(
        tester,
        390,
        ChallengeCard(challenge: kChallenge, onOpen: () {}),
      );

      expectGrounds(
        tester,
        ChallengeCard,
        kChallenge.title,
        alsoCites: kChallenge.citations,
      );
    });

    testWidgets('Sleep’s tonight lever', (tester) async {
      await pumpAt(tester, 390, TonightPanel(lever: kLever));

      expectGrounds(tester, TonightPanel, kLever.prose);
    });

    testWidgets('Sleep’s timing panel, for the server’s own action line', (
      tester,
    ) async {
      const action = 'Shift lights out earlier [sleep_regularity_index].';
      await pumpAt(
        tester,
        390,
        SleepTimingPanel(
          bedtime: const <double>[5, 5.5],
          wake: const <double>[13, 13.5],
          dates: const <String>['1 Aug', '2 Aug'],
          consistency: SleepConsistency.fromJson(const <String, Object?>{
            'nights': 2,
            'action': action,
          }),
          reveals: RevealRegistry(),
        ),
      );

      expectGrounds(tester, SleepTimingPanel, action);
    });

    testWidgets('Sleep’s analysis panel', (tester) async {
      const analysis = '**Your nights**\n\nSteady [sleep_regularity_index].';
      await pumpAt(
        tester,
        390,
        ProviderScope(
          overrides: [
            sleepInsightProvider.overrideWith(
              (ref) async => SleepInsight.fromJson(const <String, Object?>{
                'insight': analysis,
                'citations': <String>['vo2max'],
                'grade_floor': 'Probable',
              }),
            ),
          ],
          child: const SleepAnalysisPanel(),
        ),
      );

      expectGrounds(
        tester,
        SleepAnalysisPanel,
        analysis,
        alsoCites: const <String>['vo2max'],
      );
      expect(
        detailIn(tester, find.byType(SleepAnalysisPanel)).grade,
        'Probable',
      );
    });

    testWidgets('the shared insight card, once opened', (tester) async {
      const analysis = 'Your week held steady [sleep_regularity_index].';
      await pumpAt(
        tester,
        390,
        ProviderScope(
          overrides: [
            generatedInsightProvider('activity', '').overrideWith(
              (ref) async => GeneratedInsight.fromJson(const <String, Object?>{
                'insight': analysis,
                'citations': <String>['vo2max'],
                'grade_floor': 'Probable',
                'validated': true,
              }),
            ),
          ],
          child: const InsightCard(scope: 'activity'),
        ),
      );
      await tester.tap(find.text('Coach analysis'));
      await tester.pumpAndSettle();

      expectGrounds(
        tester,
        InsightCard,
        analysis,
        alsoCites: const <String>['vo2max'],
      );
    });

    testWidgets('the coach bubble', (tester) async {
      await pumpAt(tester, 390, CoachEntryView(entry: CoachReply(kAnswer)));

      expectGrounds(
        tester,
        CoachEntryView,
        kAnswer.reply,
        alsoCites: kAnswer.citations,
      );
      expect(detailIn(tester, find.byType(CoachEntryView)).grade, 'Probable');
    });

    testWidgets('a disclosure whose answer is server prose', (tester) async {
      const answer = 'Because your debt is 120 minutes [sleep_need_debt].';
      await pumpAt(
        tester,
        390,
        const ReasoningNote(question: 'Why this, today', answer: answer),
      );

      expectGrounds(tester, ReasoningNote, answer);
    });

    testWidgets('a disclosure composed in Dart draws NO ⓘ', (tester) async {
      // An ⓘ opening an empty sheet is a control promising grounding there is
      // none of. Most disclosures in this app are of this kind.
      await pumpAt(
        tester,
        390,
        const ReasoningNote(
          question: 'The statistic behind this',
          answer: 'Computed over 105 days on which both were recorded.',
        ),
      );

      expect(dotIn(find.byType(ReasoningNote)), findsNothing);
    });
  });
}
