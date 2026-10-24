/// The ordered sections of Today. Composition only — no widget is defined here.
///
/// **This is the v02 prototype's screen, in the prototype's order.** Owner
/// decision, 2026-09: *"we need every screen to be designed pixel perfect with
/// the same idea that i told."* The order below is `design/mobile-preview`'s
/// `screens-overview.js::H.screens.today` read top to bottom.
///
/// ```text
///   header                    date · Today · avatar with its sync ring
///   device strip              Helio Strap · charge · Data & sync
///   data health               silent when everything is fresh
///   illness banner            silent when nothing is flagged
///   ── the hero ──────────────
///   biological age            the halo, the figure, the ruler, two terms
///   summary tiles             recovery · sleep · movement
///   context bridge            what the estimate is, and is not
///   chapter nav               Your night · Your day · Longer view
///   ── Last night → today ────
///   recovery, explained       weights, colour key, four factor bars
///   overnight HRV | resting heart
///   sleep stages · seven nights
///   sleep health, beyond duration
///   context bridge            sleep's share of the recovery model
///   blood oxygen | sleep need & debt
///   ── Movement → recovery ───
///   heart rate & stress       one hour cursor, two labelled scales
///   steps & energy
///   context bridge            today's effort against remaining readiness
///   effort in context
///   active minutes | strength
///   ── Patterns → small changes ──
///   cardiorespiratory fitness
///   daily journal
///   suggested actions · insights
///   coach | actions           the two entry points
///   footer
/// ```
///
/// ## What survived the redesign unchanged, and why
///
/// The **data wiring**. Every figure is still a [Reading] off `TodayFacts`, every
/// block is still gated on what the payload carried, and every refusal still
/// renders as a refusal with its reason. The presentation is new; the honesty
/// layer under it is the same one, wired the same way.
///
/// The **illness banner** stays above everything a number can be read from —
/// brief §4.1 makes it deterministic and outranking, so nothing on this screen
/// may be read before it. It is null on this account today, and null draws
/// nothing.
///
/// **`pai` is null on this account, and `anomalies` is not computed by this
/// endpoint at all** — it shipped as `[]`, which read as "nothing was
/// anomalous"; it is `null` now with a block naming `/api/notable` as the place
/// that does scan (`docs/BACKEND_GAPS_FROM_UI.md` A3). Neither gets a section
/// here: a heading that can never have content under it is dead code, and the
/// scan already has a home on the Insights tab as Notable events.
///
/// ## The date control, and the one half of the screen it can move
///
/// `.date-navigation` is built (`v02/date_control.dart`) and the header carries
/// it. The selection lives in `data/store/view_date.dart` and follows the reader
/// between screens.
///
/// **A past day now draws the same screen, answered for that day.** `/api/today`
/// takes an optional `day=YYYY-MM-DD` and reads the rows filed under it
/// (`docs/AS_OF_DAY.md`), so recovery, sleep health, debt, VO₂max and biological
/// age are that day's stored values rather than today's relabelled. The refusal
/// this file used to carry was correct while the endpoint answered only for the
/// current day; it is not a refusal we are entitled to any more, because withheld
/// and *not asked for* are different states.
///
/// Nothing about the honesty layer changes with it. A day with no row is
/// `Withheld` with its reason, exactly as an unsynced today is, and every block is
/// still a [Reading] — which is why a past day needed no second set of widgets:
/// the vocabulary that says "we don't have this" already existed and already said
/// it in the right voice.
///
/// **What a past day still refuses is the LLM half**, and that is deliberate
/// rather than pending. The daily action is cached per current day, so writing one
/// for an older date would be authoring a new claim rather than replaying a
/// record; the server sends null and the screen draws nothing, which is the same
/// thing it does for an un-warmed today. The live trust card goes with it — every
/// figure on it is an age measured against right now.
///
/// The prototype's `.scenarioNotice` is its review-scenario switch. The live
/// equivalent is the data-health card, which says the same class of thing about
/// real data, so that is what sits in the slot.
library;

import 'package:flutter/material.dart';
import 'package:healthee/data/push/push_stamp.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/features/today/today_body.dart';
import 'package:healthee/features/today/today_facts.dart';
import 'package:healthee/features/today/today_measured.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/features/today/v02/today_chapters.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/features/today/widgets/data_health_section.dart';
import 'package:healthee/features/today/widgets/illness_banner.dart';
import 'package:healthee/shared/device_health_card.dart';
import 'package:healthee/shared/instrument_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/section_list.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

/// Everything Today needs that is not on [ScreenData].
@immutable
class TodayExtras {
  /// The push state, the session state, the classified connection, the strap's
  /// charge, the three things the header and the entry cards can open, and the
  /// chapter anchors the jump nav walks to.
  const TodayExtras({
    this.push,
    this.signedIn,
    this.health,
    this.batteryPercent,
    this.chapters,
    this.navigation,
    this.onSignIn,
    this.onOpenProfile,
    this.onAddLog,
    this.onOpenCoach,
    this.onOpenActions,
    this.onOpenRecovery,
    this.onOpenBody,
    this.onOpenSleep,
    this.onOpenActivity,
    this.onOpenTrends,
    this.onOpenMetric,
    this.onOpenFitness,
    this.onOpenWorkouts,
  });

  /// What the app knows about its own pushing, for the data-health card.
  final PushStamp? push;

  /// Null while the keystore read is in flight — "not yet known", which the
  /// card stays silent about rather than guessing "signed out" for a frame.
  final bool? signedIn;

  /// The connection surface's one classification.
  ///
  /// Null draws no ring in the header, a neutral dot on the device strip and no
  /// link section on the data-health card. It carries `busy` and the fetch's
  /// progress, so nothing else has to.
  final ConnectionHealth? health;

  /// Strap battery at the last sync, for the device strip.
  final int? batteryPercent;

  /// Where the chapter nav jumps to. Null draws no nav rather than three dead
  /// buttons — see `today_chapters.dart`.
  final TodayChapters? chapters;

  /// The window the date control may move within. Null prints the date as a
  /// label, which is what a host with no writable selection gets.
  final DateNavigation? navigation;

  /// Opens the sign-in screen.
  final VoidCallback? onSignIn;

  /// Opens settings. The avatar's destination.
  final VoidCallback? onOpenProfile;

  /// Opens the manual-entry log sheet, when there is one.
  final VoidCallback? onAddLog;

  /// Opens the coach.
  final VoidCallback? onOpenCoach;

  /// Opens the actions tab.
  final VoidCallback? onOpenActions;

  /// Opens the recovery detail — the hero's first summary row.
  final VoidCallback? onOpenRecovery;

  /// Opens the biological-age detail — a tap anywhere on the hero.
  final VoidCallback? onOpenBody;

  /// Opens the sleep tab — the hero's second summary row.
  final VoidCallback? onOpenSleep;

  /// Opens the activity tab — the hero's third summary row.
  final VoidCallback? onOpenActivity;

  /// Opens `Your trends`, from the head of Today's three.
  final VoidCallback? onOpenTrends;

  /// Opens one metric's own dated series, by its canonical id.
  ///
  /// Every `H.panel(…, 'metric/:key')` Details link on this screen. Null draws
  /// no link at all, which is what a panel whose metric this build keeps no
  /// history for gets — `today_day_sections.dart` names the one such panel.
  final void Function(String metric)? onOpenMetric;

  /// Opens the VO₂max screen — the fitness panel's Details link.
  final VoidCallback? onOpenFitness;

  /// Opens the workout list — the strength panel's Details link.
  final VoidCallback? onOpenWorkouts;
}

/// Builds the ordered section list for one render of Today.
List<PageSection> todaySections(ScreenData data, TodayExtras extras) {
  final snapshot = data.snapshot;
  // `view.latest` is the wall-clock day, so this is "the owner has chosen a day
  // that is not today" — not "these two dates disagree", which is also true of
  // a cached payload on the current day and means something else. It comes off
  // `ScreenData` rather than off the control, because a screen reached with no
  // control on it is still on whatever day was selected.
  // The day the reader asked for. It decides LAYOUT only; whether the payload is
  // entitled to be drawn under it is `ScreenData.snapshot`'s question and is
  // answered there, once, for every screen. Two guards would be two chances to
  // disagree about what "this day" means (Standards section 1).
  final past = data.view.isPast;
  if (!past && data.day.hasNothing && snapshot == null) {
    return _freshInstall(data, extras);
  }
  final now = data.now ?? DateTime.now();
  final sections = SectionList();
  sections.add(
    TodayHeader(
      // **The day being READ.** With a control in the header the date is no
      // longer a label on the payload; it is the thing the two chevrons move,
      // and a control whose own figure disagreed with its arithmetic would step
      // two days on the first press. A payload that describes an older day
      // still says so — `today_facts.dart`'s provenance line and the
      // stale-sleep banner are where that belongs, and both name the date.
      //
      // With no control there is nothing to move, so the payload's own date
      // stays the label it always was.
      date: extras.navigation == null
          ? (snapshot?.date ?? data.day.date)
          : data.day.date,
      now: now,
      health: extras.health,
      navigation: extras.navigation,
      batteryPercent: extras.batteryPercent ?? data.day.batteryPercent,
      onOpenProfile: extras.onOpenProfile,
      onOpenCoach: extras.onOpenCoach,
    ),
  );
  // The live-feed trust card is an age measured against right now, so it belongs
  // to the current day only — the server sends it as null otherwise, and this is
  // the same decision said in the layout rather than left to a null check.
  if (!past) {
    sections.add(_dataHealth(data, extras));
  }
  // Above everything a number can be read from, and absent entirely when the
  // server flagged nothing. See the library docstring.
  if (snapshot?.illnessFlag case final flag?) {
    sections.add(
      IllnessBanner(
        flag: flag,
        // The day the payload answers for, so the banner can say when the signal it
        // is drawing was raised on a different one — the server's window reaches two
        // days back (A4).
        viewedDay: snapshot?.asOf?.day,
      ),
    );
    sections.gap(PageSpacing.block);
  }
  if (data.serverFailure case final PageSection failure) {
    sections.addSection(failure);
    sections.gap(PageSpacing.panel);
    measuredOnlySections(sections, data);
  }
  if (data.serverPending case final PageSection pending) {
    sections.addSection(pending);
  }
  if (snapshot != null) {
    todayBody(sections, TodayFacts.of(snapshot, now), data, extras);
  }
  return sections.build();
}

/// A phone that has synced nothing AND has heard nothing from the server.
List<PageSection> _freshInstall(ScreenData data, TodayExtras extras) {
  final now = data.now ?? DateTime.now();
  return <PageSection>[
    PageSection(
      TodayHeader(
        date: data.day.date,
        now: now,
        health: extras.health,
        batteryPercent: extras.batteryPercent ?? data.day.batteryPercent,
        onOpenProfile: extras.onOpenProfile,
      ),
      gap: 0,
    ),
    PageSection(_dataHealth(data, extras), gap: 0),
    const PageSection(
      EmptyState(
        message: 'Nothing from your strap yet',
        hint:
            'Pull down on this screen with the strap on your wrist and nearby. '
            'Everything here comes off the device or from the '
            "server's reading of it; nothing is estimated in the meantime.",
      ),
    ),
    PageSection(DeviceHealthCard(day: data.day, now: data.now)),
    if (data.serverFailure case final PageSection failure) failure,
  ];
}

Widget _dataHealth(ScreenData data, TodayExtras extras) {
  final view = data.server.value;
  return DataHealthSection(
    health: data.snapshot?.dataHealth,
    // The radio's own faults have nowhere else to be said — see the card.
    connection: extras.health,
    push: extras.push,
    cachedAt: view != null && view.fromCache ? view.fetchedAt : null,
    cachedDate: view != null && view.describesAnotherDay(data.day.date)
        ? data.snapshot?.date
        : null,
    lastStrapSync: data.day.sync.lastCompleteSync,
    now: data.now,
    signedIn: extras.signedIn,
    onSignIn: extras.onSignIn,
    // The card carries its own bottom space, so a healthy day leaves no gap.
    bottomGap: 16,
  );
}
