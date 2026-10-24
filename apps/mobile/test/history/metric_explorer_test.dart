/// Health signals — what each row says, how it is judged, and what it refuses
/// to print.
///
/// The claims this file pins: a chip's words and colour come from the one
/// judgement (`reading_state.dart`); inside the usual range is neutral; a goal
/// exists only where the server sent one; a signal with nothing behind it says
/// "No reading" and a withheld one prints the server's sentence whole; and on a
/// past day every row is "No reading", because `/api/today` is the latest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/models/today_view.dart';
import 'package:healthee/features/history/metric_explorer_screen.dart';
import 'package:healthee/features/history/v02/signal_row.dart';
import 'package:healthee/features/history/v02/signal_row_view.dart';
import 'package:healthee/features/history/v02/signal_rows.dart';
import 'package:healthee/features/history/v02/signal_sections.dart';
import 'package:healthee/shared/charts/v02/signal_spark.dart';
import 'package:healthee/shared/v02/reading_state.dart';

import '../_today_stubs.dart';
import '_history_host.dart';
import '_signals_host.dart';

HealtheeColors get _colors => AppTheme.dark.extension<HealtheeColors>()!;

Finder _row(String metric) =>
    find.byWidgetPredicate((w) => w is SignalRowView && w.row.metric == metric);

Finder _in(String metric, String text) =>
    find.descendant(of: _row(metric), matching: find.text(text));

TextStyle? _styleOf(WidgetTester tester, String metric, String text) =>
    tester.widget<Text>(_in(metric, text)).style;

void main() {
  useRealFonts();

  final TodayView usualView = signalsView(
    cards: <Map<String, Object?>>[
      signalsCard(
        'hrv_sleep_avg',
        'Overnight HRV',
        43.9,
        'ms',
        median: 50.5,
        sd: 6.5,
      ),
      signalsCard('rhr_daily', 'Resting HR', 63, 'bpm', median: 58.5, sd: 2.5),
      signalsCard(
        'spo2_overnight',
        'Blood oxygen',
        98.3,
        '%',
        median: 98.5,
        sd: 0.4,
      ),
    ],
  );

  group('what is listed', () {
    test('groups come in the kit order with the right signals', () {
      final groups = signalGroups(todayView().snapshot);
      expect(groups.map((g) => g.label).toList(), <String>[
        'Heart',
        'Breathing & oxygen',
        'Sleep',
        'Activity',
        'Body',
      ]);
      expect(groups[0].rows.map((r) => r.metric).toList(), <String>[
        'hrv_sleep_avg',
        'rhr_daily',
        'recovery_score',
        'vo2max_estimate',
        'cardio_load',
      ]);
      expect(groups[1].rows.length, 3);
      expect(groups[2].rows.map((r) => r.metric).toList(), <String>[
        'sleep_health_score_4dim',
        'sleep_regularity_index',
        'sleep_debt_min',
      ]);
      expect(groups[3].rows.map((r) => r.metric).toList(), <String>[
        'steps_total',
        'distance_m_daily',
        'active_calories',
        'total_calories',
        'mvpa_min',
        'moderate_min',
        'vigorous_min',
      ]);
      expect(groups[4].rows.map((r) => r.metric).toList(), <String>[
        'weight_kg',
        'basal_calories',
      ]);
    });

    test('every row opens a history the server answers for', () {
      final known = HistoryMetric.values.map((m) => m.id).toSet();
      for (final group in signalGroups(todayView().snapshot)) {
        for (final row in group.rows) {
          expect(known, contains(row.metric));
          expect(row.title, isNotEmpty);
          expect(row.title, isNot(contains('_')));
        }
      }
    });

    test('with no snapshot every row is No reading', () {
      final rows = signalGroups(null).expand((g) => g.rows);
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.judgement.state, ReadingState.noData, reason: row.metric);
        expect(row.figure, isNull, reason: row.metric);
      }
    });

    test('the tally counts shown, outside usual and no reading', () {
      final groups = signalGroups(usualView.snapshot);
      final tally = SignalTally.of(groups);
      final rows = groups.expand((g) => g.rows).toList();
      expect(tally.signals, rows.length);
      expect(
        tally.outside,
        rows
            .where(
              (r) =>
                  r.judgement.state == ReadingState.worse ||
                  r.judgement.state == ReadingState.watch,
            )
            .length,
      );
      expect(tally.noReading, rows.where((r) => !r.hasReading).length);
      // HRV below and resting HR above are both worse than usual.
      expect(tally.outside, greaterThanOrEqualTo(2));
    });
  });

  group('the row words', () {
    testWidgets('HRV below usual is worse, in the alert colour', (
      tester,
    ) async {
      await pumpSignals(tester, view: usualView);
      expect(_in('hrv_sleep_avg', '↓ Below usual'), findsOneWidget);
      expect(
        _styleOf(tester, 'hrv_sleep_avg', '↓ Below usual')!.color,
        _colors.alert,
      );
      expect(
        _in('hrv_sleep_avg', 'higher is better · usual 44 to 57'),
        findsOneWidget,
      );
    });

    testWidgets('resting HR above usual is worse', (tester) async {
      await pumpSignals(tester, view: usualView);
      expect(_in('rhr_daily', '↑ Above usual'), findsOneWidget);
      expect(
        _styleOf(tester, 'rhr_daily', '↑ Above usual')!.color,
        _colors.alert,
      );
      expect(
        _in('rhr_daily', 'lower is better · usual 56 to 61'),
        findsOneWidget,
      );
    });

    testWidgets('inside the range is Usual in ink2, with a primary-ink dot', (
      tester,
    ) async {
      await pumpSignals(tester, view: usualView);
      expect(_in('spo2_overnight', 'Usual'), findsOneWidget);
      expect(_styleOf(tester, 'spo2_overnight', 'Usual')!.color, _colors.ink2);
      expect(
        _in('spo2_overnight', 'best inside range · usual 98.1 to 98.9'),
        findsOneWidget,
      );
      final spark = tester.widget<CustomPaint>(
        find.descendant(
          of: _row('spo2_overnight'),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is SignalSparkPainter,
          ),
        ),
      );
      final painter = spark.painter! as SignalSparkPainter;
      expect(painter.state, ReadingState.usual);
      expect(ReadingState.usual.dotIn(_colors), _colors.ink);
    });

    testWidgets('a goal met says so, with a progress bar', (tester) async {
      await pumpSignals(tester);
      expect(_in('mvpa_min', 'Goal met'), findsOneWidget);
      expect(_in('mvpa_min', 'this week · goal 150'), findsOneWidget);
      expect(
        tester.widget<SignalRowView>(_row('mvpa_min')).row.graphic,
        SignalGraphic.bar,
      );
    });

    testWidgets('a goal missed says how many to go', (tester) async {
      await pumpSignals(
        tester,
        view: signalsView(
          mutate: (json) =>
              (json['mvpa']! as Map<String, Object?>)['week_min'] = 4,
        ),
      );
      expect(_in('mvpa_min', '146 to go'), findsOneWidget);
      expect(_styleOf(tester, 'mvpa_min', '146 to go')!.color, _colors.alert);
    });

    testWidgets('no goal on the wire means no goal chip', (tester) async {
      await pumpSignals(
        tester,
        view: signalsView(
          mutate: (json) =>
              (json['mvpa']! as Map<String, Object?>)['week_target'] = null,
        ),
      );
      final row = tester.widget<SignalRowView>(_row('mvpa_min')).row;
      expect(row.progress, isNull);
      expect(row.judgement.words, isNot(contains('to go')));
      expect(row.judgement.words, isNot('Goal met'));
    });

    testWidgets('sleep health is four pills and a count of misses', (
      tester,
    ) async {
      await pumpSignals(tester);
      final row = tester.widget<SignalRowView>(_row('sleep_health_score_4dim'));
      expect(row.row.graphic, SignalGraphic.checks);
      expect(row.row.checks.length, 4);
      expect(_in('sleep_health_score_4dim', '1 missed'), findsOneWidget);
    });

    testWidgets('a signal with nothing behind it says No reading', (
      tester,
    ) async {
      await pumpSignals(
        tester,
        view: signalsView(
          mutate: (json) => (json['sparklines']! as Map<String, Object?>)
              .remove('spo2_overnight_min'),
        ),
      );
      expect(_in('spo2_overnight_min', 'No reading'), findsOneWidget);
      expect(_in('spo2_overnight_min', '—'), findsOneWidget);
    });

    testWidgets('A WITHHELD READING PRINTS THE SERVER’S SENTENCE, WHOLE', (
      tester,
    ) async {
      const sentence =
          'Your last weigh-in is 61 days old. Log a current weight and this '
          'comes back.';
      await pumpSignals(
        tester,
        view: signalsView(
          mutate: (json) {
            for (final card in json['metrics']! as List<Object?>) {
              final row = card! as Map<String, Object?>;
              if (row['metric'] == 'weight_kg') {
                row['value'] = null;
                row['withheld'] = <String, Object?>{
                  'reason': 'logged_weight_stale',
                  'message': sentence,
                  'last_as_of_date': '2026-06-04',
                };
              }
            }
          },
        ),
      );
      expect(_in('weight_kg', sentence), findsOneWidget);
      expect(_in('weight_kg', 'No reading'), findsOneWidget);
      expect(
        tester.widget<SignalRowView>(_row('weight_kg')).row.figure,
        isNull,
      );
    });
  });

  group('the screen', () {
    testWidgets('title, summary strip and legend', (tester) async {
      await pumpSignals(tester, view: usualView);
      expect(find.text('Health signals'), findsOneWidget);
      final tally = SignalTally.of(signalGroups(usualView.snapshot));
      expect(find.text('${tally.signals}'), findsOneWidget);
      expect(find.text('signals'), findsOneWidget);
      expect(find.text('outside usual'), findsOneWidget);
      expect(find.text('no reading'), findsOneWidget);
      expect(find.text('your usual range'), findsOneWidget);
      expect(find.text('trend = last 14 days'), findsOneWidget);
      // Group counts.
      expect(find.text('5 signals'), findsOneWidget);
      expect(find.text('3 signals'), findsNWidgets(2));
    });

    testWidgets('one semantics label per row says the verdict in words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpSignals(tester, view: usualView);
      expect(
        tester.getSemantics(_row('hrv_sleep_avg')).label,
        'Overnight HRV 43.9 milliseconds, below your usual of 44 to 57',
      );
      handle.dispose();
    });

    testWidgets('a row is one tap target of at least 48 px', (tester) async {
      await pumpSignals(tester);
      for (final id in <String>['hrv_sleep_avg', 'weight_kg', 'mvpa_min']) {
        expect(tester.getSize(_row(id)).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('A PAST DAY IS NO READING EVERYWHERE, AND SAYS WHY', (
      tester,
    ) async {
      await pumpSignals(tester, view: usualView);
      await selectDay(tester, '2026-08-03');
      final rows = tester.widgetList<SignalRowView>(find.byType(SignalRowView));
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.row.hasReading, isFalse, reason: row.row.metric);
        expect(
          _in(row.row.metric, 'No reading'),
          findsOneWidget,
          reason: row.row.metric,
        );
      }
      expect(find.text(kPastDayCaption), findsOneWidget);
      expect(find.text('${rows.length}'), findsNWidgets(2));
    });

    testWidgets('no raw id and no citation marker anywhere on it', (
      tester,
    ) async {
      await pumpSignals(tester);
      for (final text in textsOn(tester)) {
        expect(text, isNot(contains('_')));
        expect(text, isNot(contains('[')));
      }
    });

    testWidgets('the two links are there', (tester) async {
      await pumpSignals(tester);
      expect(find.text('Sleep history'), findsOneWidget);
      expect(find.text('Fitness estimates'), findsOneWidget);
    });

    testWidgets('fits every phone width at 1.3 text scale', (tester) async {
      for (final width in kPhoneWidths) {
        await pumpSignals(
          tester,
          width: width,
          view: usualView,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull, reason: 'at $width');
      }
    });
  });
}
