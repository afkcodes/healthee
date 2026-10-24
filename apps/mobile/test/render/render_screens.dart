/// A look-at-it harness: renders the product screens to PNG, both themes.
///
/// **Not a test.** It asserts nothing and it is deliberately named without the
/// `_test` suffix so `flutter test` never picks it up. It is run by hand:
///
/// ```bash
/// flutter test test/render/render_screens.dart
/// ls build/renders/
/// ```
///
/// ## Why it exists
///
/// `feedback_look_at_the_design` in the owner's notes is blunt about it: grep
/// output is not a design, and an agent's *report* of visual work is not the
/// work. A screen has to be rendered and looked at, before and after, or a
/// layout that overflows on a phone ships green.
///
/// ## What is real in the output and what is not
///
/// The **fonts are the app's own** — [loadBundledFonts] registers each family
/// under the name `pubspec.yaml` gives it (`Figtree`, and `HealtheeSymbols` for
/// the bundled glyph fallback), so glyph widths, overflow and the tabular-figure
/// alignment are all genuine. It used to derive the family from the file name,
/// which registered `Figtree.ttf` as `Figtree.ttf` and drew every glyph as a
/// block. Colour, spacing and chart geometry are real either way.
///
/// The night on the Sleep screen is [kRenderNight], the same invented sample
/// night as the HTML preview (`design/mobile-preview/proposal.js`): the
/// contract snapshot's night has three stages, too few to judge a night chart.
///
/// Animations are pumped for fixed durations, never settled: the Sleep screen
/// has a ticker that never idles, and `pumpAndSettle` waited on it for nine
/// minutes.
///
/// The viewport is deliberately **taller than a phone** ([renderSize]) so a
/// `ListView.builder` lays its whole list out in one pass and the PNG is the
/// entire scroll rather than the first screenful. The width is a real phone's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/data/history/history_repository.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/coach/coach_home_screen.dart';
import 'package:healthee/features/diagnostics/diagnostics_screen.dart';
import 'package:healthee/features/insights/insights_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/features/trends/trends_period.dart';
import 'package:healthee/features/trends/trends_screen.dart';

import '../_bio_age_stubs.dart';
import '../_sleep_stubs.dart';
import '../_today_stubs.dart';
import '../features/_today_host.dart';
import 'render_samples.dart';
import 'render_support.dart';
import 'render_today_cases.dart';

const Size _tallSize = Size(390, 9000);

/// The Biological age screen: a phone's width, tall enough for the whole scroll,
/// at 3 device pixels per logical one.
const Size _bodySize = Size(390, 2300);
const double _bodyDpr = 3;

/// The list screens (Today, Sleep, Activity, Trends), at a real phone's density.
const double _listDpr = 3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The owner looks at these; the debug ribbon is not part of the app.
  WidgetsApp.debugAllowBannerOverride = false;

  setUpAll(loadBundledFonts);

  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });

  tearDown(() => store.close());

  for (final theme in <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    testWidgets('render today — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'today-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          history: sampleHistory(),
          sleep: sleepWithSampleNight(),
        ),
        dpr: _listDpr,
      );
    });

    // The paused age: the committed withheld shape with a weight 41 days old,
    // so the hero draws the headline, the server's sentence, the caption and
    // the button, and no number.
    testWidgets('render today paused — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'today-paused-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          server: todayView(
            mutate: pausedToday(absentTerms: [staleWeightTerm()]),
          ),
          profile: profileFixture(
            mutate: (json) => <String, Object?>{...json, 'weight_age_days': 41},
          ),
          history: sampleHistory(),
          sleep: sleepWithSampleNight(),
        ),
      );
    });

    testWidgets('render sleep — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'sleep-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          // Pinned, so the night labels and the whole page eyebrow are the same
          // in every render rather than drifting with the wall clock.
          home: SleepScreen(now: kSleepNow),
          sleep: sleepWithSampleNight(),
        ),
        size: _tallSize,
        dpr: _listDpr,
      );
    });

    testWidgets('render trends — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'trends-${theme.key}',
        ProviderScope(
          overrides: [
            todayProvider.overrideWithValue('2026-07-31'),
            for (final spec in kTrendSpecs)
              for (final period in TrendPeriod.values)
                metricHistoryProvider(
                  spec.metric,
                  period.fetchDays,
                ).overrideWith((ref) async => sampleSeries(spec.metric.id)),
          ],
          child: MaterialApp(theme: theme.value, home: const TrendsScreen()),
        ),
        size: const Size(390, 4200),
        dpr: _listDpr,
      );
    });

    testWidgets('render activity — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'activity-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          home: const ActivityScreen(),
        ),
        dpr: _listDpr,
      );
    });

    testWidgets('render insights — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'insights-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          home: const InsightsScreen(),
        ),
      );
    });

    testWidgets('render actions — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'actions-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          home: const CoachHomeScreen(),
        ),
      );
    });

    testWidgets('render diagnostics — ${theme.key}', (tester) async {
      await shoot(
        tester,
        'diagnostics-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          home: DiagnosticsScreen(now: now),
        ),
      );
    });
  }

  _bodyRenders(() => store);
  todayRenders(() => store);
}

/// The Biological age screen at dpr 3, in every accent and ground it ships in.
void _bodyRenders(LocalStore Function() store) {
  final grounds = <String, (Brightness, BackgroundVariant)>{
    'light': (Brightness.light, BackgroundVariant.espresso),
    'espresso': (Brightness.dark, BackgroundVariant.espresso),
    'amoled': (Brightness.dark, BackgroundVariant.amoled),
  };
  for (final accent in <int>[0, 4]) {
    for (final ground in grounds.entries) {
      final theme = AppTheme.customized(
        ground.value.$1,
        AppearanceVariant(accent: accent, background: ground.value.$2),
      );
      final name =
          'bioage-${ground.key}-${AppearanceVariant.accentNames[accent]}';
      for (final open in <bool>[false, true]) {
        testWidgets('render $name ${open ? 'open' : 'closed'}', (tester) async {
          await shoot(
            tester,
            '$name-${open ? 'open' : 'closed'}',
            todayHost(
              store(),
              themeOverride: theme,
              home: _pushed(BodyScreen(now: now)),
            ),
            size: _bodySize,
            dpr: _bodyDpr,
            beforeShot: open ? _openMoves : null,
          );
        });
      }
    }
  }
  final paused = <String, Map<String, Object?> Function(Map<String, Object?>)>{
    'paused': pausedToday(absentTerms: [staleWeightTerm()]),
    'sleep-withheld': pausedToday(
      absentTerms: [noNightsTerm()],
      keepSleep: false,
    ),
  };
  for (final state in paused.entries) {
    for (final ground in <String>['light', 'espresso']) {
      testWidgets('render bioage ${state.key} $ground', (tester) async {
        final (brightness, background) = grounds[ground]!;
        await shoot(
          tester,
          'bioage-${state.key}-$ground',
          todayHost(
            store(),
            themeOverride: AppTheme.customized(
              brightness,
              AppearanceVariant(background: background),
            ),
            server: todayView(mutate: state.value),
            profile: profileFixture(
              mutate: (json) => <String, Object?>{
                ...json,
                'weight_age_days': 41,
              },
            ),
            home: _pushed(BodyScreen(now: now)),
          ),
          size: _bodySize,
          dpr: _bodyDpr,
        );
      });
    }
  }
}

/// [screen] with a route under it, so its back control is drawn.
Widget _pushed(Widget screen) => Navigator(
  onGenerateInitialRoutes: (navigator, initial) => <Route<void>>[
    MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    MaterialPageRoute<void>(builder: (_) => screen),
  ],
);

/// Opens the "What moves it" dropdown.
Future<void> _openMoves(WidgetTester tester) async {
  await tester.tap(find.byKey(WhatMovesIt.headerKey));
  await tester.pump(const Duration(seconds: 1));
}
