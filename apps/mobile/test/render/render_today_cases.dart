/// Today's hero at dpr 3 in every accent and ground it ships in. **Not a test
/// file**: `render_screens.dart` calls [todayRenders] from its `main`.
///
/// The 390 x 844 frame Today opens on, for each of Forest and Indigo on light,
/// espresso and amoled; the whole scroll and the text scale 1.3 frame on light
/// Forest; and the paused hero on light and espresso.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/today_screen.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';
import '../features/_today_host.dart';
import 'render_samples.dart';
import 'render_support.dart';

/// The frame Today opens on, at 3 device pixels per logical one.
const Size _frame = Size(390, 844);
const double _dpr = 3;

/// Tall enough for the lines under the sphere at text scale 1.3 and for the
/// paused notice with its button.
const Size _long = Size(390, 1150);

const Map<String, (Brightness, BackgroundVariant)> _grounds =
    <String, (Brightness, BackgroundVariant)>{
      'light': (Brightness.light, BackgroundVariant.espresso),
      'espresso': (Brightness.dark, BackgroundVariant.espresso),
      'amoled': (Brightness.dark, BackgroundVariant.amoled),
    };

ThemeData _theme(String ground, int accent) => AppTheme.customized(
  _grounds[ground]!.$1,
  AppearanceVariant(accent: accent, background: _grounds[ground]!.$2),
);

/// Registers the Today hero renders.
void todayRenders(LocalStore Function() store) {
  Widget today(ThemeData theme, {Widget? home}) => todayHost(
    store(),
    themeOverride: theme,
    history: sampleHistory(),
    sleep: sleepWithSampleNight(),
    home: home,
  );

  for (final accent in <int>[0, 4]) {
    for (final ground in _grounds.keys) {
      final name = 'today7-$ground-${AppearanceVariant.accentNames[accent]}';
      testWidgets('render $name', (tester) async {
        await shoot(
          tester,
          name,
          today(_theme(ground, accent)),
          size: _frame,
          dpr: _dpr,
        );
      });
    }
  }
  testWidgets('render today7 light Forest, the whole scroll', (tester) async {
    await shoot(
      tester,
      'today7-scroll-light-Forest',
      today(_theme('light', 0)),
      dpr: _dpr,
    );
  });
  testWidgets('render today7 light Forest at text scale 1.3', (tester) async {
    await shoot(
      tester,
      'today7-light-Forest-text13',
      today(
        _theme('light', 0),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: TodayScreen(now: now),
          ),
        ),
      ),
      size: _long,
      dpr: _dpr,
    );
  });
  for (final ground in <String>['light', 'espresso']) {
    testWidgets('render today7 paused $ground', (tester) async {
      await shoot(
        tester,
        'today7-paused-$ground',
        todayHost(
          store(),
          themeOverride: _theme(ground, 0),
          server: todayView(
            mutate: pausedToday(absentTerms: [staleWeightTerm()]),
          ),
          profile: profileFixture(
            mutate: (json) => <String, Object?>{...json, 'weight_age_days': 41},
          ),
          history: sampleHistory(),
          sleep: sleepWithSampleNight(),
        ),
        size: _long,
        dpr: _dpr,
      );
    });
  }
}
