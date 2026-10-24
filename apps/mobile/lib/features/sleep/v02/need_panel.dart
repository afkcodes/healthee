/// `Sleep need & debt` — the shortfall, and what it is a shortfall against.
///
/// `design/mobile-preview/sleep-history-view.js`:
///
/// ```js
/// H.panel('Sleep need & debt','sleep',
///   `${H.value(debt,'min debt', need + ' need')}
///    <div class="three section">${H.stat('79','%','Sleep performance')}
///                               ${H.stat('1h 40m','','Nightly gap')}
///                               ${H.stat('14','','Modelled nights')}</div>
///    <div class="progress-track section"><i style="width:79.16%"></i></div>
///    ${H.charts.sleepGap()}
///    ${H.note('The 8h reference leaves a 1h 40m nightly gap. '
///             'Debt is a separate 14-night model.')}
///    ${H.evidence('sleep_need_debt')}`, '', 'moon')
/// ```
///
/// ## Two deliberate differences from the prototype's numbers
///
/// **`/api/sleep` now sends the need and the debt** — the same `sleep_debt`
/// block the Today page carries, from the same rows. It used to send neither,
/// and this panel measured its shortfall against `kSleepNeedMin`, a client
/// constant of 480 minutes flat. The server's need is age-selected (NSF 2015:
/// 480 under 65, 450 at 65 and over), so for an older owner the two tabs
/// reported different shortfalls for the same nights and neither said which was
/// which. That is the second definition `CLAUDE.md`'s first hard rule is about,
/// and the constant is deleted rather than corrected: a better client constant
/// is still a second definition.
///
/// **Where the server has no need, this panel says so and draws nothing.** The
/// need band is selected from AGE, so a profile with no date of birth has none
/// — and a shortfall, a performance percentage and a nightly gap are all
/// ratios against it. Withheld with the reason, never computed against an
/// assumed eight hours.
///
/// The shortfall is still summed over the nights THIS SCREEN was sent, not over
/// the server's fourteen, so the note under the chart names the count actually
/// used — *"the 7 measured nights of the last seven"*. A `14` here would be a
/// label borrowed from a model that is not running behind it; the server's own
/// 14-night debt is a different figure and lives on the Today page.
///
/// ## ⛔ TWO WINDOWS ON ONE CARD, AND THEY MUST SAY WHICH IS WHICH
///
/// The debt is summed over **the measured week** and the chart draws **those
/// seven nights**. `Sleep performance` and `Nightly gap` are **last night** —
/// `sleep_performance_pct` is `last_tst / need`, ported verbatim and cited to
/// `sleep_need_debt`, and the explainer says so in words.
///
/// Stacked unlabelled, that reads as one window. Worse, it reads as the RIGHT
/// one by coincidence: on the owner's own week the debt was `16h 04m` over 7
/// nights — a mean of `2h 18m` — directly above a `Nightly gap` of `2h 26m`.
/// Eight minutes apart, so the wrong reading is indistinguishable from the
/// average nobody computed. **Never let these two sit together unlabelled.**
///
/// The fix is the label, never the arithmetic: making performance weekly here
/// would be the second definition `CLAUDE.md`'s first hard rule forbids, and
/// the server owns this one.
///
/// ## The chart is `HDebtBars`, not a second one
///
/// `H.charts.sleepGap` draws each night's bar to what was slept and a dashed
/// ghost from there up to the reference. `HDebtBars` already draws exactly that,
/// takes no `Color`, takes its reveal as a parameter, and is the app's one
/// need-versus-actual chart. A second painter would be a second opinion about
/// the same seven nights.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/sleep_debt.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_windows.dart';
import 'package:healthee/shared/charts/h_debt_bars.dart';
import 'package:healthee/shared/charts/v02/chart_void.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/colour_key.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';
import 'package:solar_icons/solar_icons.dart';

/// `Sleep need & debt` — the seven-night shortfall against the server's need.
class SleepNeedPanel extends StatelessWidget {
  /// [night] is the latest session; [nights] the measured week, oldest first;
  /// [needMin] the server's own sleep need, or null when it has none.
  const SleepNeedPanel({
    required this.night,
    required this.nights,
    required this.needMin,
    required this.reveals,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Sleep need & debt';

  /// `H.charts.sleepGap()`'s height.
  static const double chartHeight = 130;

  /// The gap above the statistics row.
  static const double statsGap = 14;

  /// The gap between a window label and what it labels.
  static const double labelGap = 8;

  /// The gap above the legend.
  static const double legendGap = 10;

  /// The latest night.
  final SleepNight night;

  /// The measured nights of the last seven, oldest first.
  final List<DebtNight> nights;

  /// The server's age-selected sleep need in minutes, or null when it has none
  /// for this owner. Every figure below is a ratio against it, so null withholds
  /// all of them rather than substituting a reference nobody computed.
  final int? needMin;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Total minutes short of the need across [nights], or null without a need.
  double? get shortfallMin {
    final need = needMin?.toDouble();
    if (need == null || need <= 0) {
      return null;
    }
    return nights.fold<double>(
      0,
      (sum, night) => sum + (need - night.totalMin).clamp(0.0, need),
    );
  }

  /// Last night as a share of the need, carrying its honesty state.
  Reading<double>? get performance {
    final need = needMin?.toDouble();
    if (need == null || need <= 0) {
      return null;
    }
    return night.tstMin.map((minutes) => (100 * minutes / need).clamp(0, 100));
  }

  /// Last night's own shortfall, or null when the night or the need is missing.
  double? get nightlyGapMin {
    final need = needMin?.toDouble();
    final minutes = night.tstMin.valueOrNull;
    if (need == null || need <= 0 || minutes == null) {
      return null;
    }
    return (need - minutes).clamp(0.0, need);
  }

  /// The note, naming the need and the window it was applied over.
  String get note {
    final need = needMin;
    if (need == null || need <= 0) {
      return kNoSleepNeed;
    }
    return 'Measured against your ${durationText(need)} age-based need, summed '
        'over the ${nights.length} measured '
        '${nights.length == 1 ? 'night' : 'nights'} of the last seven. This is '
        'not the 14-night modelled debt.';
  }

  @override
  Widget build(BuildContext context) {
    final need = needMin;
    final hasNeed = need != null && need > 0;
    final percent = performance?.valueOrNull;
    final gap = nightlyGapMin;
    final shortfall = shortfallMin;
    return Panel(
      tone: Tone.sleep,
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
          if (shortfall != null && hasNeed)
            PanelValue(
              durationText(shortfall),
              unit: 'debt',
              context_: '${durationText(need)} need',
            )
          else
            const WithheldPanel(
              disclosure: Disclosure(
                reason: kNoSleepNeedReason,
                message: kNoSleepNeed,
              ),
              label: 'Sleep need',
            ),
          if (percent != null || gap != null) ...<Widget>[
            const SizedBox(height: statsGap),
            // The window these two belong to, said once, above both. See the
            // docstring: unlabelled they read as the week, and on this owner's
            // data the wrong reading lands eight minutes from the right one.
            const WindowLabel('Last night'),
            const SizedBox(height: labelGap),
            StatRow(<Stat>[
              if (percent != null)
                Stat('Sleep performance', '${percent.round()}', unit: '%'),
              if (gap != null) Stat('Short of need', durationText(gap)),
            ]),
          ],
          // **`Nights counted` is gone and the bare track with it.** The count
          // is repeated verbatim in the note below — "the 7 measured nights of
          // the last seven" — and the track drew one of the three figures
          // beside it, full width, with nothing saying which. A mark that
          // carries no reading of its own does not belong on this surface.
          const SizedBox(height: statsGap),
          const WindowLabel('The measured week'),
          const SizedBox(height: labelGap),
          // One bar is not a week, and a need-versus-actual chart with no need
          // is not a chart. Below either floor the slot is kept and drawn empty,
          // and the note below says which floor it was.
          if (!hasNeed || nights.length < SleepWindows.minimumNights)
            const ChartVoid(height: chartHeight)
          else
            RevealOnce(
              id: 'sleep.debt',
              registry: reveals,
              builder: (context, t) => SizedBox(
                height: chartHeight,
                child: HDebtBars(
                  totalsMin: <double>[for (final n in nights) n.totalMin],
                  labels: <String>[for (final n in nights) n.label],
                  needMin: need,
                  progress: t,
                  height: chartHeight,
                ),
              ),
            ),
          if (hasNeed) ...<Widget>[
            const SizedBox(height: legendGap),
            // The ghost had NO legend entry, and it is the mark the card's own
            // title is about. Three entries for three things the chart draws.
            ColourKey(<ColourKeyEntry>[
              ColourKeyEntry('Met ${durationText(need)}', tone: Tone.fitness),
              const ColourKeyEntry('Slept', tone: Tone.sleep),
              ColourKeyEntry(
                'Still needed',
                colour: context.hues.sleep.withValues(
                  alpha: HDebtBars.ghostAlpha,
                ),
              ),
            ]),
          ],
          PanelNote(note),
          if (night.tstMin case Withheld<double>(:final disclosure))
            PanelNote('Last night: ${disclosure.message}'),
        ],
      ),
    );
  }
}
