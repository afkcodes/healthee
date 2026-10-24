/// A look-at-it harness for the Insights screen. **Not a test**: named without
/// the `_test` suffix so `flutter test` never picks it up.
///
/// ```bash
/// flutter test test/render/render_insights.dart
/// ls build/renders/insights-*.png
/// ```
///
/// Each PNG is the whole scroll at logical width 390 and device pixel ratio 3,
/// in light and in the dark espresso background, once at the system text scale
/// and once at 1.3. The payload is the contract snapshot with the findings and
/// the fitness lever replaced by the kit's five correlations and a +6.8 year
/// fitness term, so every row shape (opposite, together, lagged, too few) and
/// both hero tiles are on screen at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/insights/insights_screen.dart';

import '../_today_stubs.dart';
import '../features/_today_host.dart';
import 'render_support.dart';

const Size _size = Size(390, 4300);
const double _dpr = 3;

Map<String, Object?> _finding(
  String a,
  String b,
  double r,
  int n, {
  int lag = 0,
}) => <String, Object?>{
  'kind': 'pairwise_lag',
  'metric_a': a,
  'metric_b': b,
  'effect_metric': 'rho',
  'effect_size': r,
  'q_value': 0.001,
  'n_samples': n,
  'lag_days': lag,
  'research_note_ids': const <String>[],
};

Map<String, Object?> _kit(Map<String, Object?> json) {
  final age = Map<String, Object?>.from(json['biological_age']! as Map);
  final terms = <Object?>[
    for (final term in age['contributions']! as List)
      (term as Map)['term'] == 'fitness'
          ? <String, Object?>{
              ...Map<String, Object?>.from(term),
              'delta_years': 6.8,
              'value': 33.3,
              'target': 46.5,
            }
          : term,
  ];
  return <String, Object?>{
    ...json,
    'biological_age': <String, Object?>{...age, 'contributions': terms},
    'top_findings': <Object?>[
      _finding('rhr_daily', 'recovery_score', -0.88, 67),
      _finding('hrv_sleep_avg', 'recovery_score', 0.82, 36),
      _finding('hrv_sleep_avg', 'rhr_daily', -0.82, 36),
      _finding('sleep_regularity_index', 'vo2max_estimate', 0.64, 47, lag: 1),
      _finding('sleep_regularity_index', 'sleep_debt_min', -0.57, 54, lag: 1),
      _finding('alcohol', 'sleep_score', 0.5, 1),
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetsApp.debugAllowBannerOverride = false;
  setUpAll(loadBundledFonts);

  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  final themes = <String, ThemeData>{
    'light': AppTheme.light,
    'espresso': AppTheme.customized(
      Brightness.dark,
      const AppearanceVariant(
        accent: 0,
        background: BackgroundVariant.espresso,
      ),
    ),
  };

  for (final scale in <double>[1, 1.3]) {
    for (final theme in themes.entries) {
      final name = 'insights${scale == 1 ? '' : '-large'}-${theme.key}';
      testWidgets('render $name', (tester) async {
        await shoot(
          tester,
          name,
          todayHost(
            store,
            themeOverride: theme.value,
            server: todayView(mutate: _kit),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: const InsightsScreen(),
              ),
            ),
          ),
          size: _size,
          dpr: _dpr,
        );
      });
    }
  }
}
