/// The invented sample data the render harness draws: a night, and the two
/// weeks of nights and days before it. Sample numbers only, never anyone's.
library;

import 'dart:math' as math;

import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/models/trend_point.dart';
import '../_sleep_stubs.dart';

/// The preview's sample night: stage and minutes, in order. Invented numbers.
const List<(String, int)> kRenderNight = <(String, int)>[
  ('light', 14),
  ('deep', 31),
  ('light', 22),
  ('rem', 9),
  ('awake', 3),
  ('light', 41),
  ('deep', 19),
  ('light', 18),
  ('rem', 27),
  ('light', 62),
  ('deep', 16),
  ('light', 21),
  ('rem', 24),
  ('awake', 4),
  ('light', 33),
  ('rem', 29),
  ('awake', 3),
  ('light', 17),
];

/// The contract snapshot's Sleep page with its newest night's timeline swapped
/// for [kRenderNight]. Everything else is the wire's own.
SleepPage sleepWithSampleNight() {
  final Map<String, Object?> json = loadJson(kSleepSnapshotPath);
  final List<Object?> nights = json['nights']! as List<Object?>;
  final Map<String, Object?> night = Map<String, Object?>.of(
    nights.first! as Map<String, Object?>,
  );
  var at = 0;
  night['stage_timeline'] = <Map<String, Object?>>[
    for (final (String stage, int minutes) in kRenderNight)
      <String, Object?>{
        'stage': stage,
        'start_offset_min': at.toDouble(),
        'end_offset_min': (at += minutes).toDouble(),
        'duration_min': minutes.toDouble(),
      },
  ];
  // The nights before it vary, so the Today sleep card has a usual to draw.
  var index = 0;
  return SleepPage.fromJson(<String, Object?>{
    ...json,
    'nights': <Object?>[
      night,
      for (final Object? earlier in nights.skip(1))
        <String, Object?>{
          ...earlier! as Map<String, Object?>,
          'tst_min': kRenderSleepMinutes[index % kRenderSleepMinutes.length],
          'efficiency_pct': kRenderEfficiency[index % kRenderEfficiency.length],
          'sri': kRenderSri[index % kRenderSri.length],
          'hrv_sleep_avg': kRenderHrv[index++ % kRenderHrv.length],
          'rhr': 52 + index % 6,
          ..._sampleTimes(earlier, index),
          'stages': <String, Object?>{
            'deep': 70 + (index * 7) % 30,
            'light': 190 + (index * 11) % 40,
            'rem': 75 + (index * 5) % 25,
            'awake': 15 + (index * 3) % 15,
          },
          'respiratory_rate': 13 + (index % 3) * 0.6,
          'spo2_avg': 95 + index % 4,
          'skin_temp_c': 33.0 + (index % 5) * 0.15,
        },
    ],
  });
}

/// Invented nights and days for the two weeks before the sample day.
const List<int> kRenderSleepMinutes = <int>[
  402,
  355,
  371,
  428,
  348,
  396,
  410,
  362,
  433,
  385,
  351,
  419,
  377,
  390,
];
const List<double> kRenderEfficiency = <double>[
  91,
  88.5,
  93,
  86,
  90,
  84,
  92,
  89,
  94,
  87,
  85,
  90.5,
  88,
  92.5,
  80,
  83,
];
const List<double> kRenderSri = <double>[
  71,
  68,
  74,
  66,
  72,
  63,
  70,
  75,
  69,
  73,
  61,
  67,
  76,
  70,
  58,
  62,
];
const List<double> kRenderHrv = <double>[
  44,
  51,
  47,
  39,
  49,
  53,
  42,
  46,
  50,
  41,
  48,
  55,
  43,
  46,
  38,
  52,
];
const List<double> kRenderRecovery = <double>[
  61,
  72,
  58,
  66,
  70,
  55,
  63,
  74,
  59,
  68,
  64,
  57,
  71,
  62,
];
const List<double> kRenderSteps = <double>[
  6420,
  4810,
  8930,
  5230,
  7700,
  4180,
  6060,
  9420,
  5590,
  7110,
  4630,
  8210,
  6840,
  5050,
];

/// The dated history the Today cards read: the 14 days before 31 July.
DatedHistory sampleHistory() {
  final end = DateTime.utc(2026, 7, 31);
  List<TrendPoint> series(List<double> values) => <TrendPoint>[
    for (var i = 0; i < values.length; i++)
      TrendPoint(
        date: end
            .subtract(Duration(days: values.length - i))
            .toIso8601String()
            .substring(0, 10),
        value: values[i],
      ),
  ];
  return DatedHistory(
    days: 90,
    series: <String, List<TrendPoint>>{
      'recovery_score': series(kRenderRecovery),
      'steps_total': series(kRenderSteps),
    },
  );
}

/// A bedtime between 22:40 and 00:40 and a wake seven to eight hours later,
/// on the night's own date, so the timing charts have a week to draw.
Map<String, Object?> _sampleTimes(Object? night, int index) {
  final date = DateTime.parse(
    (night! as Map<String, Object?>)['date']! as String,
  );
  final bed = DateTime(
    date.year,
    date.month,
    date.day - 1,
    22,
    40,
  ).add(Duration(minutes: (index * 37) % 120));
  final wake = bed.add(Duration(minutes: 420 + (index * 23) % 60));
  return <String, Object?>{
    'start_iso': bed.toIso8601String(),
    'end_iso': wake.toIso8601String(),
  };
}

/// A year of invented daily readings for [metric], ending 31 July.
List<TrendPoint> sampleSeries(String metric) {
  final base = switch (metric) {
    'rhr_daily' => 56.0,
    'recovery_score' => 64.0,
    'steps_total' => 6500.0,
    'sleep_regularity_index' => 70.0,
    _ => 46.0,
  };
  final end = DateTime.utc(2026, 7, 31);
  return <TrendPoint>[
    for (var i = 364; i >= 0; i--)
      if (i % 11 != 3)
        TrendPoint(
          date: end
              .subtract(Duration(days: i))
              .toIso8601String()
              .substring(0, 10),
          value:
              base * (1 + 0.08 * math.sin(i / 2.3) + 0.04 * math.cos(i / 17)),
        ),
  ];
}
