/// The two surfaces the prototype has no box for, rebuilt as v02 panels.
///
/// The prototype's Sleep screen ends at `Naps & your day` and a link to the
/// recommendations. This app's Sleep screen also reaches two server surfaces
/// that the browser mock-up never had to invent:
///
/// - **`/api/sleep/consistency`'s `tonight`** — one lever, a target clock, how
///   often it was hit, and a nap note.
/// - **`/api/sleep/insight`** — a grounded, server-written reading of these
///   nights, citation-validated against `packages/knowledge`.
///
/// Both are kept, for the reason `activity_sections.dart` records for its own
/// `InsightCard`: deleting a reachable server surface because the design
/// mock-up has no box for it is a feature removal wearing a redesign's clothes.
/// They sit **after** every panel the prototype does draw, so the prototype's
/// own order is never interrupted by something it does not contain.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_insight.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/states/grounded_markdown.dart';
import 'package:healthee/shared/states/grounded_text.dart';
import 'package:healthee/shared/v02/fold.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// The lever for tonight, and how often it has been hit.
class TonightPanel extends StatelessWidget {
  /// [lever] is `/api/sleep/consistency`'s `tonight` block.
  const TonightPanel({required this.lever, super.key});

  /// The gap above the adherence track.
  static const double trackGap = 14;

  /// The gap between the track and its count.
  static const double countGap = 8;

  /// The server's lever.
  final TonightLever lever;

  /// `LIGHTS OUT` for a bedtime lever, `TARGET WAKE` otherwise.
  String get targetCaption =>
      lever.lever == 'bedtime' || lever.lever == 'duration'
      ? 'Lights out'
      : 'Target wake';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = lever.targetClock;
    return Panel(
      tone: Tone.sleep,
      label: 'Tonight',
      head: PanelHead(
        title: lever.title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep_consistency',
        // The lever's prose is the server's, markers and all. Its sources go to
        // the ⓘ this head already carries, beside the explainer's own.
        detail: MetricDetail.grounded(groundingOf(lever.prose)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (target != null)
            PanelValue(target, unit: targetCaption.toLowerCase()),
          GroundedProse(
            text: lever.prose,
            style: TypeScale.panelContext.copyWith(color: colors.ink),
          ),
          if (lever.hasAdherence) ...<Widget>[
            const SizedBox(height: trackGap),
            ProgressTrack(fraction: lever.hit! / lever.of!),
            const SizedBox(height: countGap),
            Text(
              'Hit on ${lever.hit} of the last ${lever.of} nights.',
              style: TypeScale.panelNote.copyWith(color: colors.ink2),
            ),
          ],
          if (lever.napNote case final String note) PanelNote(note),
        ],
      ),
    );
  }
}

/// `/api/sleep/insight` — the grounded reading, or the reason there is none.
///
/// The four states are the endpoint's own and none of them is a blank panel: a
/// declined analysis says it was declined rather than guessed, and a locked one
/// says which plan it belongs to and that the measurements above are not part
/// of it.
class SleepAnalysisPanel extends ConsumerStatefulWidget {
  /// Reads `sleepInsightProvider`.
  const SleepAnalysisPanel({super.key});

  /// The panel's title.
  static const String title = 'Sleep analysis';

  /// While the server is still writing it.
  static const String pending = 'Analysing your recent sleep…';

  /// When the read failed.
  static const String unreachable =
      'We could not reach your server for the analysis. The measurements above '
      'come from your own strap and are unaffected. Pull down to try again.';

  /// When the plan does not include it.
  static const String locked =
      'AI analysis is part of the paid plan. Everything else on this screen is '
      'measured from your own strap and stays free.';

  /// When the model had nothing grounded to say.
  static const String refused =
      'The analysis was declined rather than guessed. There was not enough '
      'grounded evidence to say anything about these nights.';

  /// When there is simply no analysis yet.
  static const String empty =
      'No analysis yet. Check back once more nights are recorded.';

  @override
  ConsumerState<SleepAnalysisPanel> createState() => _SleepAnalysisPanelState();
}

/// It opens expanded and can be folded away.
///
/// **It sits at the top of the screen now**, above the night it is about, which
/// is what makes the fold worth having: an analysis of several paragraphs in
/// the first slot would push every measurement below the fold for a reader who
/// only wanted last night's numbers. Expanded is still the default, because a
/// panel that hides its content by default is a panel the owner has to
/// discover, and this is the one thing on the screen written FOR them.
///
/// The state is per-mount and deliberately not persisted: there is no store for
/// it, and a remembered fold would silently hide new analysis the next morning.
class _SleepAnalysisPanelState extends ConsumerState<SleepAnalysisPanel> {
  /// The vertical inset while the fold is shut.
  static const double shutPadding = 11;

  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final insight = ref.watch(sleepInsightProvider);
    final panel = _panel(context, insight);
    // **The whole card toggles, both ways.** A scroll drag never fires this:
    // the gesture arena hands a vertical drag to the enclosing scrollable and
    // the tap recogniser loses, so the card-wide target costs the reader
    // nothing while they are scrolling past it.
    return HTap(
      onTap: () => setState(() => _open = !_open),
      semanticLabel: '${SleepAnalysisPanel.title}, ${_open ? 'hide' : 'show'}',
      child: panel,
    );
  }

  Widget _panel(BuildContext context, AsyncValue<SleepInsight> insight) {
    return Panel(
      tone: Tone.fitness,
      label: SleepAnalysisPanel.title,
      head: PanelHead(
        title: SleepAnalysisPanel.title,
        icon: SolarIconsOutline.stars,
        infoKey: 'sleep',
        // The head reads the SAME analysis the body draws, so the sources in
        // the ⓘ are the sources of the paragraphs underneath it. A locked,
        // refused or still-pending read carries no prose and grounds nothing.
        detail: _grounding(insight.value),
        collapsed: !_open,
        onToggle: () => setState(() => _open = !_open),
      ),
      // **Nothing behind the fold when it is shut.** A one-line "hidden" stub
      // left a full-height card carrying a sentence about itself; the head
      // already says what the panel is and the chevron already says it opens.
      //
      // The head gap moves INSIDE the fold — see `Panel.headSpacing`. Left
      // where it was it survived the collapse, and 12px of it above the card's
      // 18px of bottom padding was the empty strip under the shut title.
      headSpacing: 0,
      // Shut, the card is one row of head; the full 18 above and below it is
      // more inset than content. It animates with the fold because
      // `AnimatedSize` is measuring the whole card, not just the body.
      padded: EdgeInsets.symmetric(
        horizontal: Panel.padding,
        vertical: _open ? Panel.padding : shutPadding,
      ),
      child: Fold(
        open: _open,
        child: Padding(
          padding: const EdgeInsets.only(top: Panel.headGap),
          child: insight.when(
            loading: () => const PanelNote(SleepAnalysisPanel.pending),
            error: (_, _) => const PanelNote(SleepAnalysisPanel.unreachable),
            data: (analysis) => _body(context, analysis),
          ),
        ),
      ),
    );
  }

  /// What the ⓘ carries: the analysis's own markers, the `citations` the payload
  /// sent, and the grade floor the server computed. Nothing when there is no
  /// analysis to ground.
  static MetricDetail _grounding(SleepInsight? analysis) {
    if (analysis == null || analysis.locked || !analysis.hasText) {
      return MetricDetail.none;
    }
    return MetricDetail.grounded(
      groundingOf(analysis.text, alsoCites: analysis.citations),
      grade: analysis.gradeFloor,
    );
  }

  static Widget _body(BuildContext context, SleepInsight analysis) {
    if (analysis.locked) {
      return const PanelNote(SleepAnalysisPanel.locked);
    }
    if (analysis.refused) {
      return const PanelNote(SleepAnalysisPanel.refused);
    }
    if (!analysis.hasText) {
      return const PanelNote(SleepAnalysisPanel.empty);
    }
    return GroundedMarkdown(text: analysis.text, accent: context.colors.accent);
  }
}
