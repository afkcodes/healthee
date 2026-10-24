/// The client half of the severity-B and severity-C findings.
///
/// Each test asserts the PROPERTY the defect violated, not the shape of the fix.
/// The paired mutations live in `test/mutations.sh` and each one puts a defect
/// back and must go red here.
///
/// **C3 — the client computed its own, age-blind sleep need.**
/// `features/sleep/sleep_format.dart` carried `kSleepNeedMin = 480` and the
/// Sleep tab derived its shortfall, its performance percentage and its nightly
/// gap from it, while the Today tab reported the server's age-selected need from
/// `sleep_debt.need_min`. For an owner over 65 the canonical need is 450, so the
/// two tabs reported different shortfalls for the same nights and nothing said
/// which was which. `SleepDebt` had a fourth copy of the same assumption, as
/// `?? 480` in its parser.
///
/// **C2 — a night's `duration_min` and a nap's were different quantities.**
/// Total sleep time on a night, wall-clock time in bed on a nap, one key.
///
/// **B4 — `StepBucket` parsed a population-stride distance and a hardcoded
/// zero calorie count**, neither of which was a measurement and neither of which
/// any widget read.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_debt.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/features/sleep/sleep_windows.dart';
import 'package:healthee/features/sleep/v02/need_panel.dart';
import 'package:healthee/shared/charts/h_debt_bars.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../_sleep_stubs.dart';
import '../features/_sleep_host.dart';

void main() {
  group('C3 — one sleep need, and it is the server\'s', () {
    test('THE PAYLOAD\'S NEED IS CARRIED, NEVER DEFAULTED TO EIGHT HOURS', () {
      // 450 is the over-65 band. The parser used to coalesce a missing
      // `need_min` to 480, so an older owner was scored against a target half an
      // hour too high and it was published back as theirs.
      final debt = SleepDebt.maybe(<String, Object?>{
        'debt_min': 240,
        'need_min': 450,
      });
      expect(debt, isNotNull);
      expect(debt!.needMin, 450);
    });

    test('A PAYLOAD WITH NO NEED HAS NO NEED — not a flat 480', () {
      final debt = SleepDebt.maybe(<String, Object?>{'debt_min': 240});
      expect(debt, isNotNull);
      expect(
        debt!.needMin,
        isNull,
        reason:
            'a need nobody computed is not eight hours; every figure that '
            'depends on it withholds instead',
      );
    });

    test('the sleep page carries the block the Today page carries', () {
      final page = sleepPageFixture();
      expect(
        page.sleepDebt,
        isNotNull,
        reason: '/api/sleep sends sleep_debt now, so no screen invents a need',
      );
      expect(page.sleepDebt!.needMin, isNotNull);
    });

    testWidgets('WITH NO NEED THE PANEL WITHHOLDS AND DRAWS NO CHART', (
      tester,
    ) async {
      final windows = SleepWindows(sleepPageFixture(), kSleepNow);
      await tester.pumpWidget(
        sleepPanelHost(
          SleepNeedPanel(
            night: windows.latest,
            nights: windows.debt,
            needMin: null,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No shortfall, no percentage, no gap, and no need-versus-actual chart —
      // all four are ratios against a target we do not have.
      expect(find.byType(WithheldPanel), findsOneWidget);
      expect(find.byType(HDebtBars), findsNothing);
      expect(find.text('Sleep performance'), findsNothing);
      expect(find.text('Nightly gap'), findsNothing);
      // Twice: in the withheld panel where the figure would have been, and
      // in the note under the chart slot. Both are the same sentence from
      // the same constant, which is the point of there being one.
      expect(find.textContaining('No sleep need yet'), findsWidgets);
      // And nowhere on the panel does the deleted assumption reappear.
      expect(find.textContaining('8\u00A0h'), findsNothing);
    });

    testWidgets('WITH A NEED THE PANEL MEASURES AGAINST THAT NEED', (
      tester,
    ) async {
      final windows = SleepWindows(sleepPageFixture(), kSleepNow);
      await tester.pumpWidget(
        sleepPanelHost(
          SleepNeedPanel(
            night: windows.latest,
            nights: windows.debt,
            // The over-65 band, deliberately NOT 480: if the panel still had a
            // constant of its own, this figure would not reach the screen.
            needMin: 450,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('7\u00A0h 30\u00A0min'), findsWidgets);
      expect(find.byType(WithheldPanel), findsNothing);
    });
  });

  group('C2 — a night and a nap do not share one name', () {
    test('A NAP REPORTS TIME IN BED AND SLEEP TIME SEPARATELY', () {
      final nap = sleepPageFixture().naps.first;
      expect(nap.tibMin, isNotNull, reason: 'the wall-clock span');
      expect(nap.tstMin, isNotNull, reason: 'light + deep + REM');
      expect(
        nap.tibMin! >= nap.tstMin!,
        isTrue,
        reason:
            'time in bed includes wake, so it can never be less than sleep '
            'time — if these two can collapse the names are decorative',
      );
    });

    test('a night reports its total sleep time under that name', () {
      final night = sleepPageFixture().nights.first;
      expect(night.tstMin.valueOrNull, isNotNull);
    });
  });

  group('B4 — a step bucket carries only what was measured', () {
    test('the parsed bucket has steps, and a time to put them at', () {
      final bucket = StepBucket.fromJson(const <String, Object?>{
        'bucket': 48,
        'time': '12:00',
        'steps': 120,
      });
      expect(bucket.steps, 120);
      expect(bucket.bucket, 48);
      expect(bucket.time, '12:00');
    });

    test('THE MODEL READS NO DISTANCE AND NO CALORIES FROM THE PAYLOAD', () {
      // A DERIVED check, not a listed one (`HOW_WE_VERIFY.md` section 4): the
      // defect is a field with nothing behind it, and a field nothing reads is
      // invisible to a widget test — which is exactly how both survived. So the
      // source is read and the two keys are looked for by name.
      //
      // `distance_m` was `steps × 0.78` computed in SQL: a second, uncited
      // definition of stride implying a 188 cm owner, beside the canonical
      // `0.414 × height` that REFUSES without a profile. `calories` was the
      // literal `0` for a quantity nobody computed. Neither can come back here
      // without the server computing something real first.
      final source = File(
        'lib/data/models/today_series.dart',
      ).readAsStringSync();
      for (final key in <String>['distance_m', 'calories']) {
        expect(
          source.contains("json['$key']"),
          isFalse,
          reason:
              '`$key` is read back out of the step-bucket payload. The server '
              'stopped sending it because there was no measurement behind it; '
              'parsing it here would put the field back with nothing under it.',
        );
      }
    });

    test('and the wire does not carry them either', () {
      final buckets =
          loadJson(
                '../../packages/contracts/snapshots/today.json',
              )['today_step_buckets']!
              as List<Object?>;
      expect(buckets, isNotEmpty);
      for (final bucket in buckets) {
        expect((bucket! as Map<String, Object?>).keys.toSet(), <String>{
          'bucket',
          'time',
          'steps',
        });
      }
    });
  });
}
