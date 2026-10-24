/// A look-at-it harness for the Health signals screen, both themes, at dpr 3.
///
/// **Not a test** (no `_test` suffix). Run by hand:
///
/// ```bash
/// flutter test test/render/render_signals.dart
/// ls build/renders/signals-*.png
/// ```
///
/// The fixture is the contract snapshot with the server's usual ranges laid on
/// three cards, so the screen draws a below-usual HRV, an above-usual resting
/// HR and a steady blood-oxygen row beside the rest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/features/history/metric_explorer_screen.dart';

import '../_today_stubs.dart';
import '../history/_history_host.dart';
import 'render_support.dart';

Map<String, Object?> _card(
  String metric,
  String label,
  double value,
  String unit,
  double median,
  double sd,
) => <String, Object?>{
  'metric': metric,
  'label': label,
  'value': value,
  'unit': unit,
  'median_30d': median,
  'sd_30d': sd,
  'z': null,
  'anomalous': false,
  'withheld': null,
  'provenance': <String, Object?>{},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetsApp.debugAllowBannerOverride = false;
  setUpAll(loadBundledFonts);

  final themes = <String, ThemeData>{
    'light': AppTheme.customized(Brightness.light, const AppearanceVariant()),
    'dark': AppTheme.customized(
      Brightness.dark,
      const AppearanceVariant(background: BackgroundVariant.espresso),
    ),
  };
  for (final entry in themes.entries) {
    for (final scale in <double>[1, 1.3]) {
      testWidgets('render signals ${entry.key} x$scale', (tester) async {
        final view = todayView(
          mutate: (json) {
            final cards =
                <Object?>[
                  ...(json['metrics']! as List<Object?>),
                  _card(
                    'hrv_sleep_avg',
                    'Overnight HRV',
                    43.9,
                    'ms',
                    50.5,
                    6.5,
                  ),
                  _card('spo2_overnight', 'Blood oxygen', 98.3, '%', 98.5, 0.4),
                  _card(
                    'respiratory_rate_sleep',
                    'Breathing rate',
                    14.3,
                    'breaths/min',
                    14.6,
                    0.4,
                  ),
                ]..removeWhere(
                  (c) =>
                      c is Map &&
                      c['metric'] == 'rhr_daily' &&
                      c['sd_30d'] == 0,
                );
            cards.add(_card('rhr_daily', 'Resting HR', 63, 'bpm', 58.5, 2.5));
            json['metrics'] = cards;
            return json;
          },
        );
        await shoot(
          tester,
          'signals-${entry.key}-x${scale.toString().replaceAll('.', '')}',
          historyHost(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const MetricExplorerScreen(),
            ),
            view: view,
            theme: entry.value,
          ),
          size: const Size(390, 2600),
          dpr: 3,
        );
      });
    }
  }
}
