/// The three sleep panels of `Last night → today` that are not a mini trend.
///
/// `screens-overview.js::nightCharts`, in order: the seven-night stage chart,
/// the four independent dimensions, and — as the right half of the last pair —
/// need against debt.
///
/// ## Nothing here composes a sleep score
///
/// `SleepHealthPanel` draws `sleep_health.dimensions` as four **separate**
/// readings against four published cutoffs. It does not add them up, and the
/// prototype's own title says why: *"Sleep health, beyond duration"*. The
/// payload also carries a dimension COUNT (`sleep_health_score_4dim`); it is not
/// drawn as a score anywhere, for the reason `feedback_no_composite_score`
/// gives — three out of four is a tally of unlike things, and a reader will take
/// it for a mark out of four.
///
/// ## The stage chart keeps its pre-v02 painter, deliberately
///
/// `HStackedSleep` is the only stacked stage chart in the app and it already
/// reads `InstrumentHues.sleepStage` for its colours, takes no `Color`, and
/// takes its reveal progress as a parameter. v02 changes what is around it — the
/// panel, the head, the legend, the note — not what it draws. A second stacked
/// painter would be a second opinion about the same seven nights.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/sleep_debt.dart';
import 'package:healthee/data/models/sleep_health.dart';
import 'package:healthee/data/models/sleep_history.dart';
import 'package:healthee/shared/charts/h_stacked_sleep.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/colour_key.dart';
import 'package:healthee/shared/v02/dimension_list.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// The one thing the legend is there to say.
const String kStageColourNote =
    'Each stage keeps the same colour throughout the app.';

/// `Sleep stages · seven nights` — the week, stacked, with its legend.
class SleepWeekPanel extends StatelessWidget {
  /// [nights] is oldest first and is drawn only when there are two of them —
  /// `today_body.dart` holds that gate, because one bar is not a week.
  const SleepWeekPanel({
    required this.nights,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Sleep stages · seven nights';

  /// The pre-v02 card's own height, unchanged.
  static const double chartHeight = 108;

  /// The gap above the legend.
  static const double legendGap = 10;

  /// The week.
  final List<SleepNightSummary> nights;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the sleep screen.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final hues = context.hues;
    return Panel(
      tone: Tone.sleep,
      // The card opens the metric; the head keeps only its ⓘ. See
      // `Panel.onOpen`.
      onOpen: onDetails,
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep',
        // The legend's own sentence. It teaches — it says nothing about THIS
        // week's nights — so it went where the owner asked method text to live.
        detail: MetricDetail(method: <String>[kStageColourNote]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            // `—` when the latest night carries no measured total. It used to fall
            // back to the stage sum, which for an unstaged night is zero — so the
            // panel headline read `0h 0m` over a night nobody measured. The dash
            // is this app's existing absence glyph, four lines down on the same
            // panel; a second vocabulary for the same fact would be worse than a
            // dash the owner already knows.
            switch (nights.last.durationMin) {
              final int minutes => durationText(minutes),
              null => '—',
            },
            context_:
                'Latest night\n${nights.first.date} → ${nights.last.date}',
          ),
          RevealOnce(
            id: 'today.sleep-week',
            registry: reveals,
            builder: (context, t) =>
                HStackedSleep(nights, progress: t, height: chartHeight),
          ),
          const SizedBox(height: legendGap),
          ColourKey(<ColourKeyEntry>[
            for (final stage in kSleepStages)
              ColourKeyEntry(
                sleepStageLabel(stage),
                colour: sleepStageColor(hues, stage),
              ),
          ]),
          // The count stays: it says how much of a week this chart IS, which is
          // a fact about the bars beside it rather than a lesson about them.
          PanelNote('${nights.length} nights'),
        ],
      ),
    );
  }
}

/// `Sleep health, beyond duration` — four readings, four cutoffs, no total.
class SleepHealthPanel extends StatelessWidget {
  /// [health] is the payload's block; [breathing] is the overnight rate.
  const SleepHealthPanel({
    required this.health,
    required this.breathing,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Sleep health, beyond duration';

  /// The dimensions and what they were read against.
  final SleepHealth health;

  /// The overnight respiratory rate.
  ///
  /// **Not part of `sleep_health`**, and drawn here anyway. The prototype's grid
  /// is Efficiency / Regularity / **Breathing** / Midpoint, and this is the only
  /// surface on the new Today where an overnight breathing rate belongs. It
  /// keeps its own disclosure rather than joining the block's: the two come from
  /// different places on the wire (`respiratory_rate_sleep` or
  /// `last_sleep_extras`, against `sleep_health`), so one note carrying both
  /// would attach the wrong sentence to one of them.
  final Reading<double> breathing;

  /// Opens the sleep screen.
  final VoidCallback? onDetails;

  /// The label the breathing cell and its disclosure share.
  static const String breathingLabel = 'Breathing · overnight';

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.sleep,
      // The card opens the metric; the head keeps only its ⓘ. See
      // `Panel.onOpen`.
      onOpen: onDetails,
      label: 'Sleep health',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep_health',
        detail: MetricDetail(
          // The four "Reference …" pills the owner asked us to take off the
          // cards. Kept, not deleted: a published cutoff with no source is a
          // number this app made up — and the bands are now DRAWN, so the
          // figures here are what the drawing is measured against.
          references: <String>[
            for (final dimension in health.dimensions)
              '${dimension.name}: reference ${dimension.cutoff}',
          ],
          notes: health.researchNotes,
          // The breathing reading's own caveat, moved off the card at the
          // owner's request. It keeps its own label so it cannot be read as
          // qualifying one of the four sleep dimensions — the two come from
          // different places on the wire.
          disclosures: breathing.caveatsOrEmpty,
          disclosuresLabel: breathingLabel,
        ),
      ),
      child: DimensionList(<DimensionRow>[
        for (final dimension in health.dimensions)
          DimensionRow(
            dimension.name,
            // An unscored dimension prints a dash, never its cutoff dressed up
            // as a reading.
            dimension.reading ?? '—',
            // The published cutoff, ON the card. It used to live only in the ⓘ,
            // which left four figures nobody could read without knowing four
            // references by heart. It is the payload's own formatted string.
            against: dimension.cutoff,
            met: dimension.passed,
          ),
        // Breathing has no cutoff in `sleep_health`: no reference, no verdict.
        // It keeps its row and names the instrument behind the figure, which is
        // the one class of sentence that must stay on the card it is about.
        DimensionRow(
          SleepHealthPanel.breathingLabel,
          breathing.valueOrNull == null
              ? '—'
              : '${breathing.valueOrNull!.toStringAsFixed(1)} /min',
          against: 'Overnight average',
        ),
      ]),
    );
  }
}

/// `Sleep need & debt` — the shortfall, and what it is a shortfall against.
class SleepNeedPanel extends StatelessWidget {
  /// [debt] is the payload's block.
  const SleepNeedPanel({required this.debt, this.onDetails, super.key});

  /// The prototype's title.
  static const String title = 'Sleep need & debt';

  /// The gap above the comparison.
  static const double comparisonGap = 14;

  /// The gap between the row and its track.
  static const double trackGap = 8;

  /// The accumulated shortfall and the need behind it.
  final SleepDebt debt;

  /// `H.panel(…,'sleep')` — the whole night, which is where this figure is
  /// worked out. Null draws no link.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final asleep = debt.lastTstMin;
    final need = debt.needMin;
    // A need of null is the server saying it has none for this owner (no date of
    // birth on the profile). The debt itself still stands — it is an accumulated
    // shortfall the server computed — so it is shown, and the comparison that
    // needs a target is withheld with its reason instead of drawn against 8 h.
    final hasNeed = need != null && need > 0;
    return Panel(
      tone: Tone.sleep,
      // The card opens the metric; the head keeps only its ⓘ. See
      // `Panel.onOpen`.
      onOpen: onDetails,
      label: 'Sleep need · debt',
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep_debt',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(hoursText(debt.debtMin / 60), unit: 'debt'),
          if (asleep != null && hasNeed) ...<Widget>[
            const SizedBox(height: comparisonGap),
            StatRow(<Stat>[Stat('Asleep', durationText(asleep))]),
            const SizedBox(height: trackGap),
            ProgressTrack(fraction: asleep / need),
            PanelNote(
              '${durationText(need)} need · '
              '${durationText((need - asleep).clamp(0, need))} short',
            ),
          ] else if (hasNeed)
            PanelNote('${durationText(need)} need')
          else
            const PanelNote(kNoSleepNeed),
        ],
      ),
    );
  }
}
