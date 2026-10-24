/// The cards that moved to Sleep and Activity wear their metric's legacy hue.
///
/// Today's cards were retinted when the grid landed; the ones that moved to the
/// two detail screens mostly were not, so Active minutes had no colour at all and
/// cardio load drew a grey chart under a coloured title. A cell and the card it
/// opens in different colours is the identity claim broken on the way through the
/// door. That is what this file still guards.
///
/// ## What it stopped guarding, on 2026-08-05
///
/// It used to assert that **no card title spends `fav`, `unf` or `alert`**, which
/// was the five-tag system's central invariant: tags were built to be 40° clear
/// of every verdict so the two could never be confused. That system is deleted.
/// Legacy — now the specification — makes `cHrv` and `cReady` **the same value as
/// its green**, so a card about HRV, MVPA or sleep health legitimately paints its
/// title in the colour that also means "improving". Keeping the old assertion
/// would fail the port for being faithful.
///
/// What survives is the part that is still true and still breakable: **a hue
/// comes from `hueFor` and nowhere else**, so a per-screen colour invented at a
/// call site fails here rather than looking fine.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/activity/v02/movement_panels.dart';
import 'package:healthee/features/activity/v02/training_panels.dart';
import 'package:healthee/shared/v02/metric_tone.dart';
import 'package:healthee/shared/v02/panel.dart';

import '_today_host.dart';

const InstrumentHues _hues = InstrumentHues.light();
const HealtheeColors _colors = HealtheeColors.light();

/// Pumps [screen] on a viewport tall enough that every card is laid out.
Future<void> _pump(WidgetTester tester, LocalStore store, Widget screen) async {
  // Tall enough that the WHOLE screen lays out in one pass: Sleep is a
  // `ListView.builder`, so a card that is never scrolled to is a card that was
  // never built, and `widgetList` cannot see it.
  tester.view
    ..physicalSize = const Size(420, 3400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(todayHost(store, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  group('Activity', () {
    // **Activity is v02 now, and v02 does not pass colours at all.** A panel
    // declares a `Tone` and everything inside it resolves `context.family` from
    // the enclosing `ToneScope` (`core/theme/tone.dart`). So the assertion that
    // used to read a title's `Color` reads the panel's declared family instead —
    // the same claim, at the place the decision is now made.
    //
    // The claim itself is unchanged and is the one that matters: a family is an
    // IDENTITY, chosen from the metric's id and never from its reading, so it
    // cannot become a verdict. `shared/v02/metric_tone.dart` holds the table.

    /// The `Tone` declared by the panel that contains [title].
    Future<Tone?> panelTone(WidgetTester tester, String title) async {
      await reveal(tester, find.text(title));
      final panel = find
          .ancestor(of: find.text(title), matching: find.byType(Panel))
          .first;
      return tester.widget<Panel>(panel).tone;
    }

    testWidgets('EVERY ACTIVITY PANEL DECLARES ITS METRIC’S FAMILY', (
      tester,
    ) async {
      await _pump(tester, store, const ActivityScreen());
      final cases = <String, Tone>{
        MovementPanel.title: Tone.movement,
        IntensityPanel.title: Tone.movement,
        TrainingLoadPanel.title: Tone.load,
        FitnessSourcePanel.title: Tone.heart,
      };
      for (final entry in cases.entries) {
        expect(
          await panelTone(tester, entry.key),
          entry.value,
          reason: '${entry.key} must declare ${entry.value}',
        );
      }
    });

    testWidgets('A PANEL’S FAMILY IS THE TABLE’S, NOT A CALL SITE’S', (
      tester,
    ) async {
      // The v02 restatement of "a hue comes from `hueFor` and nowhere else": the
      // families the screen declares are the ones `metric_tone.dart` assigns to
      // the ids those panels are about, so a colour invented at a call site
      // fails here rather than looking fine.
      await _pump(tester, store, const ActivityScreen());
      expect(
        await panelTone(tester, MovementPanel.title),
        toneForMetric('steps_total'),
      );
      expect(
        await panelTone(tester, IntensityPanel.title),
        toneForMetric('mvpa_min'),
      );
      expect(
        await panelTone(tester, TrainingLoadPanel.title),
        toneForMetric('cardio_load'),
      );
      expect(
        await panelTone(tester, FitnessSourcePanel.title),
        toneForMetric('vo2max_estimate'),
      );
    });

    test(
      'HEART AND BODY NUMBERS ARE TWO DOMAINS, and cardio load is strain',
      () {
        // The colour system gives each body system its own hue: VO₂max is Heart,
        // biological age is Body, and cardio load is Strain, split from heart.
        expect(hueFor(_hues, 'vo2max_estimate'), _hues.heart);
        expect(hueFor(_hues, 'biological_age'), _hues.fitness);
        expect(hueFor(_hues, 'cardio_load'), _hues.strain);
        expect(toneForMetric('vo2max_estimate'), Tone.heart);
        expect(toneForMetric('biological_age'), Tone.fitness);
        expect(toneForMetric('cardio_load'), Tone.load);
        expect(_hues.heart, isNot(_hues.fitness));
        expect(_hues.strain, isNot(_hues.heart));
      },
    );

    testWidgets('NOTHING ON THE INTENSITY PANEL TURNS AT THE WHO FLOOR', (
      tester,
    ) async {
      // The fixture is over 150 min/week, and the panel must not celebrate a
      // POPULATION target as though it were the owner's own baseline. In v02
      // there is no threshold comparison left to get wrong — the bars take the
      // family — so what is asserted is the consequence: no verdict colour of
      // any kind is painted inside this panel.
      await _pump(tester, store, const ActivityScreen());
      await reveal(tester, find.text(IntensityPanel.title));

      final panel = find
          .ancestor(
            of: find.text(IntensityPanel.title),
            matching: find.byType(Panel),
          )
          .first;
      final painted = tester
          .widgetList<ColoredBox>(
            find.descendant(of: panel, matching: find.byType(ColoredBox)),
          )
          .map((box) => box.color)
          .toSet();
      expect(painted, isNot(contains(_colors.alert)));
      expect(painted, isNot(contains(_colors.unf)));
    });
  });

  test('THEME PARITY — the dark hues come from the same table', () {
    // A hue assigned per-theme would be one metric in two families depending on
    // the hour. `hueFor` returns a FIELD of the extension, so this asserts the
    // mapping rather than the hex: whichever field the light theme picks, the
    // dark theme picks the same one.
    const dark = InstrumentHues.dark();
    for (final metric in <String>[
      'mvpa_min',
      'cardio_load',
      'vo2max_estimate',
      'biological_age',
      'steps_total',
      'sleep_duration',
      'spo2_overnight',
      'stress',
    ]) {
      expect(
        _fieldName(dark, hueFor(dark, metric)),
        _fieldName(_hues, hueFor(_hues, metric)),
        reason: '$metric changes family between themes',
      );
    }
  });
}

/// Which named field of [hues] holds [colour].
///
/// Returns the FIRST matching name, so the comparison above is between two
/// consistently-resolved names rather than between hexes.
String _fieldName(InstrumentHues hues, Color colour) => <String, Color>{
  'sleep': hues.sleep,
  'heart': hues.heart,
  'strain': hues.strain,
  'body': hues.fitness,
  'steps': hues.movement,
  'calories': hues.movement,
  'respiratory': hues.oxygen,
  'spo2': hues.oxygen,
  'stress': hues.stress,
  'rem': hues.sleep,
}.entries.firstWhere((entry) => entry.value == colour).key;
