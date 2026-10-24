/// Today, sheets, sleep, recovery and body cases of the group A render harness. **Not a test**; see
/// `render_group_a.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';

import '../_bio_age_stubs.dart';
import '../_sleep_stubs.dart';
import '../_today_stubs.dart';
import '../features/_today_host.dart';
import 'render_group_a_support.dart';
import 'render_samples.dart';

/// The Today family, its two sheets, Sleep, Recovery and the Biological age screen.
List<GroupCase> todayCases(LocalStore Function() getStore) {
  Widget today(
    ThemeData t, {
    Widget? home,
    Map<String, Object?> Function(Map<String, Object?>)? mutate,
  }) => todayOn(getStore(), t, home: home ?? _snapshotDay(), mutate: mutate);
  Widget screen(ThemeData t, Widget home) => today(t, home: pushed(home));

  return <GroupCase>[
    GroupCase(
      name: 'today',
      route: '/ (TodayScreen)',
      data:
          'today.json minus illness_flag; sampleHistory; sleepWithSampleNight',
      build: (t) => today(t, mutate: noIllness),
    ),
    GroupCase(
      name: 'today-attention',
      route: '/ (TodayScreen)',
      data: 'today.json as committed (illness_flag moderate); sampleHistory',
      build: today,
    ),
    GroupCase(
      name: 'today-withheld',
      route: '/ (TodayScreen)',
      data:
          'today.json + pausedToday(staleWeightTerm); profile weight_age_days 41',
      build: (t) => todayHost(
        getStore(),
        themeOverride: t,
        server: todayView(
          mutate: pausedToday(absentTerms: [staleWeightTerm()]),
        ),
        profile: profileFixture(
          mutate: (json) => <String, Object?>{...json, 'weight_age_days': 41},
        ),
        history: sampleHistory(),
        sleep: sleepWithSampleNight(),
        home: _snapshotDay(),
      ),
    ),
    GroupCase(
      name: 'today-new',
      route: '/ (TodayScreen)',
      status: 'empty state',
      data:
          'no strap data in the store; today.json with its findings, '
          'history and sparklines removed; no history',
      build: (t) => todayHost(
        // A store nothing was ever synced into: the first day.
        LocalStore.memory(),
        themeOverride: t,
        server: todayView(mutate: firstDay),
        home: _snapshotDay(),
      ),
    ),
    GroupCase(
      name: 'sheet-explainer',
      route: 'showMetricInfo(recovery_score) over /',
      data: 'kMetricInfo[recovery_score]; today.json',
      size: screenSize,
      build: (t) => today(t, mutate: noIllness),
      beforeShot: (tester) async {
        showMetricInfo(
          tester.element(find.byType(Scaffold).first),
          'recovery_score',
        );
        await letSheetRise(tester);
      },
    ),
    GroupCase(
      name: 'sheet-day',
      route: 'DayPill month grid over /',
      data: 'today.json; viewDate window of the pinned clock',
      size: screenSize,
      build: (t) => today(t, mutate: noIllness),
      beforeShot: (tester) async {
        await tester.tap(find.byType(DayPill));
        await letSheetRise(tester);
      },
    ),
    GroupCase(
      name: 'sleep',
      route: '/sleep',
      data: 'sleep.json with sample night (sleepWithSampleNight)',
      build: (t) => todayHost(
        getStore(),
        themeOverride: t,
        home: SleepScreen(now: kSleepNow),
        sleep: sleepWithSampleNight(),
      ),
    ),
    GroupCase(
      name: 'sleep-history',
      route: '/sleep-history',
      data: 'sleep.json with sample nights',
      build: (t) => screen(t, const SleepHistoryScreen()),
    ),
    GroupCase(
      name: 'recovery',
      route: '/recovery',
      data: 'today.json recovery block; sampleHistory',
      build: (t) => screen(t, RecoveryScreen(now: now)),
    ),
    GroupCase(
      name: 'body',
      route: '/body',
      data: 'today.json biological_age',
      build: (t) => screen(t, BodyScreen(now: now)),
    ),
    GroupCase(
      name: 'body-open',
      route: '/body (What moves it open)',
      data: 'today.json biological_age',
      build: (t) => screen(t, BodyScreen(now: now)),
      beforeShot: (tester) async {
        await tester.tap(find.byKey(WhatMovesIt.headerKey));
        await tester.pump(const Duration(seconds: 1));
      },
    ),
  ];
}

/// Today as of the snapshot's own morning.
Widget _snapshotDay() =>
    onSnapshotDay(TodayScreen(now: DateTime(2026, 7, 31, 9, 30)));
