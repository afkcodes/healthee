/// One metric, one tone: `metric_tone.dart` must never disagree with `toneFor`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/shared/v02/metric_tone.dart';

void main() {
  test(
    'toneForMetric agrees with toneFor for every known id and an unknown',
    () {
      const ids = <String>[
        'hrv_sleep_avg',
        'hrv_rmssd_ms',
        'rhr_daily',
        'cardio_load',
        'stress',
        'skin_temp_c',
        'spo2_overnight',
        'spo2_overnight_min',
        'respiratory_rate_sleep',
        'steps_total',
        'distance_m_daily',
        'active_calories',
        'basal_calories',
        'total_calories',
        'mvpa_min',
        'sleep',
        'sleep_score',
        'sleep_duration',
        'sleep_regularity_index',
        'sleep_health_score_4dim',
        'vo2max_estimate',
        'biological_age',
        'recovery_score',
        'weight_kg',
        'recovery',
        'nonsense_metric',
      ];
      for (final id in ids) {
        expect(toneForMetric(id), toneFor(id), reason: id);
      }
    },
  );
}
