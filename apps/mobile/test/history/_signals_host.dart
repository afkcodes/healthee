/// Shared fixtures for the Health signals tests: the contract snapshot with
/// chosen cards laid over it, and the screen pumped on it.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/today_view.dart';
import 'package:healthee/features/history/metric_explorer_screen.dart';

import '../_today_stubs.dart';
import '_history_host.dart';

/// The contract snapshot with [cards] replacing any card of the same metric,
/// and [mutate] applied after.
TodayView signalsView({
  List<Map<String, Object?>> cards = const <Map<String, Object?>>[],
  void Function(Map<String, Object?> json)? mutate,
}) => todayView(
  mutate: (json) {
    final list = (json['metrics']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((m) => !cards.any((c) => c['metric'] == m['metric']))
        .toList();
    json['metrics'] = <Object?>[...list, ...cards];
    mutate?.call(json);
    return json;
  },
);

Map<String, Object?> signalsCard(
  String metric,
  String label,
  double value,
  String unit, {
  double? median,
  double? sd,
}) => <String, Object?>{
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

Future<void> pumpSignals(
  WidgetTester tester, {
  double width = 390,
  TodayView? view,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = Size(width, 6000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    historyHost(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const MetricExplorerScreen(),
      ),
      view: view ?? todayView(),
      width: width,
    ),
  );
  await tester.pumpAndSettle();
}
