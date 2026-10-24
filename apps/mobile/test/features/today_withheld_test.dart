/// Every card on Today that CAN be withheld renders as withheld, with its reason.
///
/// This is the one place the port is deliberately not legacy. Legacy gates each
/// block on `is Map` and draws **nothing** when the server sent none, so a
/// refusal and a bug look identical: an absent card. Every such block is a
/// `Reading` here, and an absent or refused block renders a `WithheldCard`
/// carrying the server's own remedy sentence.
///
/// ## Why this suite is written the way it is
///
/// Each case takes the committed contract snapshot and **removes exactly one
/// block**, then asserts two things at once: the refusal is on screen, and the
/// number that block would have carried is NOT. A test that only looked for the
/// word "WITHHELD" would pass for a card that drew the refusal *and* a stale
/// figure beside it, which is the failure mode the whole `Reading` type exists
/// to stop.
///
/// `test/mutations.sh` breaks the rendering on purpose and fails if this suite
/// does not notice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/v02/age_paused.dart';
import 'package:healthee/features/today/v02/night_panels.dart';
import 'package:healthee/features/today/v02/today_hero_withheld.dart';
import 'package:healthee/shared/v02/dimension_list.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

/// The payload with [key] replaced by a refusal the server itself would send.
Map<String, Object?> _withheld(Map<String, Object?> json, String key) => {
  ...json,
  key: <String, Object?>{
    'withheld': <String, Object?>{
      'reason': 'no_${key}_today',
      'message': 'Sentinel remedy for $key.',
    },
  },
};

/// The payload with [key] dropped entirely — the shape legacy drew nothing for.
Map<String, Object?> _absent(Map<String, Object?> json, String key) {
  final copy = <String, Object?>{...json};
  copy.remove(key);
  return copy;
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  Future<void> pump(
    WidgetTester tester,
    Map<String, Object?> Function(Map<String, Object?>) mutate,
  ) async {
    tester.view
      ..physicalSize = const Size(420, 14000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      todayHost(store, server: todayView(mutate: mutate)),
    );
    await tester.pumpAndSettle();
  }

  /// The blocks legacy gates on, with a figure each one alone would have shown.
  ///
  /// Each string is deliberately distinctive: `'3'` would also match a zone
  /// column and a stat, and a test that passed on a collision would be asserting
  /// nothing.
  const cases = <String, String>{
    'recovery_score': 'Morning recovery 72',
    'sleep_debt': 'sleep performance last night · 6.3h',
    'sleep_health': '/ 4',
    'cardio_load': '21.0',
    'mvpa': '/ 150 min',
    'biological_age': '1.7 years younger',
    'vo2max': '43.0',
  };

  group('a server refusal', () {
    for (final entry in cases.entries) {
      testWidgets('${entry.key} RENDERS AS WITHHELD, WITH ITS REMEDY', (
        tester,
      ) async {
        await pump(tester, (json) => _withheld(json, entry.key));

        // The remedy is on screen either way: the hero's notice prints the
        // server's sentence verbatim (`age_paused.dart`).
        expect(
          find.textContaining('Sentinel remedy for ${entry.key}.'),
          findsOneWidget,
        );
        expect(
          find.byType(
            entry.key == 'biological_age'
                ? TodayBioHeroWithheld
                : WithheldPanel,
          ),
          findsWidgets,
          reason:
              'the one 88px figure on the screen keeps the hero shape when it '
              'is refused; every other block is a panel',
        );
        expect(
          find.text(entry.value),
          findsNothing,
          reason:
              'the figure ${entry.key} would have carried must not survive '
              'beside its own refusal',
        );
      });
    }
  });

  group('a block the server never sent', () {
    for (final key in cases.keys) {
      testWidgets('$key SAYS SO RATHER THAN VANISHING', (tester) async {
        // Legacy's `if (d[key] is Map)` drew nothing here, so an absent block and
        // a broken screen were the same picture.
        await pump(tester, (json) => _absent(json, key));

        if (key == 'biological_age') {
          // The server sends this one as null ON PURPOSE (no date of birth, or
          // no term current), so the app explains it instead of calling it a
          // bug. `age_paused_test.dart` covers each sentence.
          expect(find.text(kAgePausedTitle), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(TodayBioHeroWithheld),
              matching: find.textContaining('a bug on our side'),
            ),
            findsNothing,
          );
          expect(find.text(cases[key]!), findsNothing);
          return;
        }
        expect(find.textContaining('the server did not say why'), findsWidgets);
        expect(
          find.textContaining('Left out: regularity'),
          findsNothing,
          reason:
              'the exclusion essay printed inline where the hero belongs is '
              'the defect this build fixed; it lives behind the ⓘ now',
        );
        expect(find.text(cases[key]!), findsNothing);
      });
    }
  });

  group('a dimension the server could not score', () {
    testWidgets('PRINTS A DASH, NEVER THE CUT-OFF THAT WOULD HAVE JUDGED IT', (
      tester,
    ) async {
      // **A whole block being withheld is the case above; this is one FIELD of
      // one block.** `sleep_health` arrives, so the grid draws — but `sri` is
      // absent, so Regularity has no reading. The cut-off sits on the same row
      // and is a number of the same shape, which is exactly what makes it
      // available to fall back to and exactly why it must not be: `≥ 70` where
      // the reading goes reads as a regularity of 70, and it would sit beside a
      // tick or a cross that judged something else entirely.
      await pump(
        tester,
        (json) => <String, Object?>{
          ...json,
          'sleep_health': <String, Object?>{
            ...json['sleep_health']! as Map<String, Object?>,
            'sri': null,
          },
        },
      );
      await reveal(tester, find.byType(SleepHealthPanel));

      final list = tester.widget<DimensionList>(
        find.descendant(
          of: find.byType(SleepHealthPanel),
          matching: find.byType(DimensionList),
        ),
      );
      final regularity = list.rows.firstWhere(
        (row) => row.label == 'Regularity',
      );
      expect(regularity.value, '—');
      // The cut-off is still ON the row — it is what the tick would have been
      // measured against, and it is the payload's own string. What must not
      // happen is it standing in for the reading.
      expect(regularity.against, isNotNull);
      expect(regularity.value, isNot(regularity.against));
      // And the dash is painted, not merely held: a row that carried it and
      // drew nothing would pass every assertion above.
      expect(
        find.descendant(
          of: find.byType(SleepHealthPanel),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });
  });

  group('a refusal is never a retry', () {
    testWidgets('the withheld card offers no button', (tester) async {
      await pump(tester, (json) => _withheld(json, 'vo2max'));

      final card = find.ancestor(
        of: find.text('Sentinel remedy for vo2max.'),
        matching: find.byType(WithheldPanel),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(ElevatedButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(OutlinedButton)),
        findsNothing,
      );
    });
  });
}
