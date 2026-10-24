/// Today's body: the hero, the tiles, and the `Last night → today` chapter.
///
/// Split from `today_sections.dart` at the 400-line gate (Standards §1), and the
/// seam is the same one as before the redesign: that file owns the **head** —
/// the things true before any number is read — and this one owns the
/// instruments. `today_day_sections.dart` carries the two chapters after this
/// one, for the same reason.
///
/// The ORDER across all three files is unbroken and
/// `test/features/today_order_test.dart` asserts it against the prototype rather
/// than against any one file.
///
/// ## Every gate here is a gate on what the payload carried
///
/// A block with no data draws **nothing** — no empty panel, no zero-state
/// heading. A block the server *refused* draws a refusal with its reason, which
/// is a different thing and is the whole point of `Reading`. The two are not
/// interchangeable: "there is no sleep history" and "we will not show you the
/// sleep history" are different sentences, and only one of them is about the
/// owner.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/models/sleep_debt.dart';
import 'package:healthee/data/models/sleep_health.dart';
import 'package:healthee/features/today/today_day_sections.dart';
import 'package:healthee/features/today/today_facts.dart';
import 'package:healthee/features/today/today_sections.dart';
import 'package:healthee/features/today/v02/mini_trend_panel.dart';
import 'package:healthee/features/today/v02/night_panels.dart';
import 'package:healthee/features/today/v02/recovery_panel.dart';
import 'package:healthee/features/today/v02/today_chapters.dart';
import 'package:healthee/features/today/v02/today_hero.dart';
import 'package:healthee/features/today/v02/today_hero_withheld.dart';
import 'package:healthee/features/today/v02/today_key_numbers.dart';
import 'package:healthee/features/today/v02/today_tonight.dart';
import 'package:healthee/features/today/widgets/stale_sleep_banner.dart';
import 'package:healthee/shared/instrument_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/section_list.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/v02/chapter.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';
import 'package:solar_icons/solar_icons.dart';

/// The bridge under sleep health: sleep's share of the recovery model.
const String kSleepBridge =
    'Sleep carries the largest single share of the recovery model. The full '
    'night includes its stages, its efficiency and its overnight physiology.';

/// Everything from the hero down.
void todayBody(
  SectionList sections,
  TodayFacts facts,
  ScreenData data,
  TodayExtras extras,
) {
  final snapshot = facts.snapshot;
  final reveals = data.reveals;

  // A refused hero is still a hero. `WithheldPanel` is right for a PANEL — a
  // named slot, a hole and a sentence — and wrong for the one 88 px figure on
  // the screen: it collapsed the card the owner reads first into a small dashed
  // box. `today_hero_withheld.dart` keeps the hero's ground, radius, padding,
  // eyebrow and model label, and puts the server's prose behind the ⓘ.
  sections.addBleed(
    ReadingView<BiologicalAge>(
      reading: snapshot.biologicalAge,
      label: 'Biological age · estimate',
      caveatCarrier: CaveatCarrier.insideCard,
      withheldBuilder: (context, disclosure) => TodayBioHeroWithheld(
        withheld: disclosure,
        block: snapshot.bioAgeBlock,
        vo2maxWithheld: snapshot.vo2maxWithheld,
        onOpen: extras.onOpenBody,
        exclusions: switch (snapshot.biologicalAge) {
          Withheld<BiologicalAge>(:final exclusions) => exclusions,
          _ => const <Disclosure>[],
        },
      ),
      builder: (context, age) => TodayBioHero(
        age: age,
        block: snapshot.bioAgeBlock,
        onOpenBody: extras.onOpenBody,
      ),
    ),
  );
  sections.add(
    TodayKeyNumbers(
      facts: facts,
      onOpenRecovery: extras.onOpenRecovery,
      onOpenSleep: extras.onOpenSleep,
      onOpenActivity: extras.onOpenActivity,
      onOpenTrends: extras.onOpenTrends,
    ),
  );
  sections.add(TodayTonight(live: facts.snapshot.asOf?.isToday ?? true));
  if (extras.chapters case final TodayChapters chapters) {
    // Pinned: `richer.css` gives `.chapter-nav` `position: sticky; top: 0`, and
    // it is the one element on the page that has it.
    sections.addPinned(
      TodayChapterNav(chapters: chapters),
      ChapterNav.extentOf,
    );
  }
  _nightChapter(sections, facts, reveals, extras);
  todayDaySections(sections, facts, data, extras);
}

/// `Last night → today` — recovery, the two overnight trends, and the night.
void _nightChapter(
  SectionList sections,
  TodayFacts facts,
  RevealRegistry reveals,
  TodayExtras extras,
) {
  final snapshot = facts.snapshot;
  sections.add(
    ChapterHeading(
      key: extras.chapters?.night,
      title: 'Last night → today',
      icon: SolarIconsOutline.moonSleep,
      tone: Tone.sleep,
    ),
  );
  if (facts.staleSleep) {
    sections.add(StaleSleepBanner(nightLabel: facts.sleepNight));
    sections.gap(PageSpacing.panel);
  }
  sections.add(
    ReadingView<RecoveryScore>(
      reading: snapshot.recovery,
      label: 'Recovery',
      caveatCarrier: CaveatCarrier.insideCard,
      withheldBuilder: (context, disclosure) =>
          WithheldPanel(disclosure: disclosure, label: 'Recovery'),
      builder: (context, score) =>
          RecoveryPanel(score: score, onDetails: extras.onOpenRecovery),
    ),
  );
  sections.gap(PageSpacing.panel);
  sections.add(
    TwinPanels(
      left: MiniTrendPanel(
        title: 'Overnight HRV',
        label: 'HRV · overnight',
        infoKey: 'hrv',
        icon: SolarIconsOutline.heartPulse,
        tone: Tone.fitness,
        reading: facts.heartRateVariability,
        series: facts.spark(TodayMetricIds.heartRateVariability),
        revealId: 'today.hrv-trend',
        reveals: reveals,
        unit: 'ms',
        onDetails: _metric(extras, TodayMetricIds.heartRateVariability),
        note: _baselineNote(
          facts.spark(TodayMetricIds.heartRateVariability).length,
          facts.heartRateVariabilityBaseline,
          'ms',
          facts.heartRateVariabilityBaselineSd,
        ),
      ),
      right: MiniTrendPanel(
        title: 'Resting heart',
        label: 'Resting heart rate',
        infoKey: 'rhr_daily',
        icon: SolarIconsOutline.heart,
        tone: Tone.heart,
        reading: facts.restingHeartRate,
        series: facts.spark(TodayMetricIds.restingHeartRate),
        revealId: 'today.rhr-trend',
        reveals: reveals,
        unit: 'bpm',
        onDetails: _metric(extras, TodayMetricIds.restingHeartRate),
        note: _baselineNote(
          facts.spark(TodayMetricIds.restingHeartRate).length,
          facts.median(TodayMetricIds.restingHeartRate),
          'bpm',
          facts.spread(TodayMetricIds.restingHeartRate),
        ),
      ),
    ),
  );
  // One bar is not a week. The prototype draws seven; the payload decides.
  if (snapshot.sleepHistory7d.length >= 2) {
    sections.gap(PageSpacing.panel);
    sections.add(
      SleepWeekPanel(
        nights: snapshot.sleepHistory7d,
        reveals: reveals,
        onDetails: extras.onOpenSleep,
      ),
    );
  }
  sections.gap(PageSpacing.panel);
  sections.add(
    ReadingView<SleepHealth>(
      reading: snapshot.sleepHealth,
      label: 'Sleep health · 4-dim',
      caveatCarrier: CaveatCarrier.insideCard,
      withheldBuilder: (context, disclosure) =>
          WithheldPanel(disclosure: disclosure, label: 'Sleep health · 4-dim'),
      builder: (context, health) => SleepHealthPanel(
        health: health,
        breathing: facts.respiratoryRate,
        onDetails: extras.onOpenSleep,
      ),
    ),
  );
  sections.add(
    // `H.bridge('sleep', …, 'sleep', 'Open your night')` — the label is the
    // prototype's, and it ends the sentence rather than sitting under it.
    ContextBridge.link(
      kSleepBridge,
      label: 'Open your night',
      onOpen: extras.onOpenSleep,
    ),
  );
  sections.gap(PageSpacing.panel);
  sections.add(
    TwinPanels(
      left: MiniTrendPanel(
        title: 'Blood oxygen',
        label: 'Blood oxygen · overnight',
        infoKey: 'spo2',
        icon: SolarIconsOutline.waterdrop,
        tone: Tone.oxygen,
        reading: facts.bloodOxygen,
        series: facts.spark(TodayMetricIds.bloodOxygenMin),
        revealId: 'today.blood-oxygen',
        reveals: reveals,
        unit: '%',
        digits: 1,
        // The overnight series this app keeps a history for. The card draws
        // nightly MINIMUMS, which `history_metric.dart` has no entry of its
        // own for; sending the reader to the overnight average would be a
        // different measurement behind the same word.
        onDetails: _metric(extras, TodayMetricIds.bloodOxygen),
        note: 'Nightly minimums. Gaps stay visible.',
      ),
      right: ReadingView<SleepDebt>(
        reading: facts.snapshot.sleepDebt,
        label: 'Sleep need · debt',
        caveatCarrier: CaveatCarrier.insideCard,
        withheldBuilder: (context, disclosure) =>
            WithheldPanel(disclosure: disclosure, label: 'Sleep need · debt'),
        builder: (context, debt) =>
            SleepNeedPanel(debt: debt, onDetails: extras.onOpenSleep),
      ),
    ),
  );
}

/// One panel's Details link, or none when this build has no such history.
///
/// [TodayExtras.onOpenMetric] takes the canonical id, so every Details link on
/// this screen resolves through one function and a panel cannot quietly point
/// at a different metric from the one it draws.
VoidCallback? _metric(TodayExtras extras, String metric) {
  final void Function(String metric)? open = extras.onOpenMetric;
  return open == null ? null : () => open(metric);
}

/// `14 nights · baseline 45 ms`, or the count alone when nothing is baselined.
///
/// **Never a baseline computed here.** `today_facts.dart` records why: a median
/// over the fourteen points on the chart is a baseline over a different window
/// from the one every other surface quotes — a second definition arriving as a
/// helpful-looking last resort. A metric the server has not baselined draws no
/// baseline.
/// `14 nights · baseline 44 ± 6 ms`.
///
/// The ± is the server's own `sd_30d` / `baseline_sd`
/// (`docs/BACKEND_GAPS_FROM_UI.md` B4) — one robust standard deviation of the
/// same 30 days the median came from, and the exact divisor behind the `z` the
/// rest of the payload quotes. Without it "baseline 44" is a point, and a
/// reading of 50 could be a normal night or an extraordinary one.
///
/// It is dropped rather than defaulted when the server sends none: a baseline
/// with no spread is still a baseline, and a ± computed from the fourteen points
/// on the chart beside it would be a spread over a different window from the
/// centre it is attached to.
String _baselineNote(int samples, double? baseline, String unit, [double? sd]) {
  final nights = '$samples ${samples == 1 ? 'night' : 'nights'}';
  if (baseline == null) {
    return nights;
  }
  // No-break spaces hold `55 ± 0 bpm` together: a narrow twin tile wraps the
  // line, and a unit or a spread stranded on the next one reads as its own.
  final spread = sd == null ? '' : '\u00a0±\u00a0${sd.round()}';
  return '$nights · baseline ${baseline.round()}$spread\u00a0$unit';
}
