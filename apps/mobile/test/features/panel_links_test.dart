/// The `Details` links, and where each one actually lands.
///
/// `docs/V02_CONNECTIVITY.md` section 2 is a walk of all 33 prototype screens.
/// Most of what it found missing was not a missing SCREEN — it was a panel whose
/// `Details` link was never wired, or was wired to a neighbour.
///
/// A link that lands on the wrong screen is the hard case for a test to catch,
/// because it looks exactly like a link that works: the control is there, the
/// tap does something, and a new screen appears. So this suite taps the control
/// and names the screen it expects, rather than asking whether a callback is
/// non-null.
///
/// Three suites divide this subject and the seam is the KIND of control:
/// `today_order_test.dart` owns which panels are drawn and in what order;
/// `v02_screen_links_test.dart` owns the doorways into the four screens that
/// were built last (a hero row, a bridge, a relationship card); and this file
/// owns the `Details` link on a panel head, the two bridges Today draws, the
/// device strip and the metric directory's closing rows.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/fitness_screen.dart';
import 'package:healthee/features/history/metric_explorer_screen.dart';
import 'package:healthee/features/settings/data_freshness_screen.dart';
import 'package:healthee/features/settings/settings_screen.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/v02/panel.dart';

import '_today_host.dart';

/// A window tall enough that a `ListView.builder` builds the whole screen.
///
/// Below the fold is NOT BUILT, so a scoped finder would come back empty and a
/// `findsNothing` would pass for a link that is present and merely off screen.
void _tall(WidgetTester tester) {
  tester.view
    // Taller since the three key numbers went full width (+~460 px).
    ..physicalSize = const Size(420, 7000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Taps the `Details` control belonging to the panel titled [panel].
///
/// Scoped to that panel, because Today draws a dozen controls with this exact
/// word on it and `find.text('Details')` would resolve all of them.
///
/// **A twin panel has no visible word.** `panel_head.dart::_compact` is the
/// prototype's `font-size: 0` on the text button — the words are deleted and the
/// arrow is kept, with the label travelling as the control's semantic name so
/// it is still announced. Both shapes are the same link, so this finds either.
Future<void> tapPanelDetails(
  WidgetTester tester,
  String panel, {
  bool settle = true,
}) async {
  final Finder card = find.ancestor(
    of: find.text(panel),
    matching: find.byType(Panel),
  );
  expect(card, findsOneWidget, reason: 'no panel titled "$panel"');
  // **The card IS the link.** A `Details` word inside it is the older shape,
  // still drawn by the panels whose action goes somewhere the card is not
  // about; where the destination is just more of the same reading, the whole
  // card opens it and a chevron says so. Either way this taps what the owner
  // taps.
  Finder details = find.descendant(of: card, matching: find.text('Details'));
  if (details.evaluate().isEmpty) {
    details = find.descendant(
      of: card,
      matching: find.bySemanticsLabel('Details'),
    );
  }
  if (details.evaluate().isEmpty) {
    details = card;
  }
  await tester.ensureVisible(details);
  await tester.pumpAndSettle();
  await tester.tap(details);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

/// Where the router is now.
String locationOf(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(Scaffold).first),
).state.uri.toString();

/// Taps a control by its words, scrolling it into view first.
Future<void> tapText(WidgetTester tester, String label) async {
  final Finder target = find.text(label);
  expect(target, findsOneWidget, reason: 'no control reads "$label"');
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  group("TODAY'S PANELS GO WHERE THE PROTOTYPE SENDS THEM", () {
    testWidgets('THE OWNER MARK OPENS SETTINGS, WHICH HOLDS DATA & SYNC', (
      tester,
    ) async {
      // **This claim moved with the design, it was not dropped.** The strip
      // used to be a row of its own ending in `Data & sync ›`, and this test
      // guarded it against being pointed at `#settings` — a screen about the
      // app rather than an answer to "is my strap current?".
      //
      // The strip is gone: `Data & sync` is a row INSIDE Settings, so the
      // separate door was a second way to the same room, and the strap folded
      // onto the mark that already opened Settings. What has to hold now is
      // that the room is still one tap further on, which is why this asserts
      // the row is there rather than stopping at the screen.
      _tall(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OwnerMark));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.text('Data & sync'));
      await tester.pumpAndSettle();
      expect(find.byType(DataFreshnessScreen), findsOneWidget);
    });

    testWidgets('Recovery, explained → the recovery screen', (tester) async {
      _tall(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tapPanelDetails(tester, 'Recovery, explained');

      expect(find.byType(RecoveryScreen), findsOneWidget);
    });

    testWidgets('the sleep bridge carries its own label to the Sleep tab', (
      tester,
    ) async {
      // `H.bridge('sleep', …, 'sleep', 'Open your night')`. It was drawn as
      // prose with no link on the end of it, which is the one shape a
      // `.context-bridge` never has in the prototype.
      _tall(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tapText(tester, 'Open your night');

      expect(find.byType(SleepScreen), findsOneWidget);
    });

    testWidgets('the movement bridge carries its own label to recovery', (
      tester,
    ) async {
      // `H.bridge('movement', …, 'recovery', 'See the relationship')`.
      _tall(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tapText(tester, 'See the relationship');

      expect(find.byType(RecoveryScreen), findsOneWidget);
    });

    testWidgets('Cardiorespiratory fitness → the fitness screen', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tapPanelDetails(tester, 'Cardiorespiratory fitness');

      expect(find.byType(FitnessScreen), findsOneWidget);
    });

    testWidgets('A METRIC DETAILS LINK OPENS THAT METRIC, NOT A NEIGHBOUR', (
      tester,
    ) async {
      // Every one of these resolves through `TodayExtras.onOpenMetric`, so a
      // panel cannot point at a metric other than the one it draws. The
      // LOCATION is what is asserted, and it names the canonical id: the
      // destination itself opens a `/api/history` read this host does not
      // answer, so settling on it would hang on a request rather than tell us
      // anything about the link.
      _tall(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tapPanelDetails(tester, 'Overnight HRV', settle: false);

      expect(locationOf(tester), '/history?metric=hrv_sleep_avg');
    });
  });

  group('THE METRIC DIRECTORY CLOSES ON THE TWO SCREENS IT NAMES', () {
    /// Opens the directory the way Insights does — `Routes.history`, no metric.
    Future<void> openDirectory(WidgetTester tester) async {
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      unawaited(
        GoRouter.of(
          tester.element(find.byType(TodayScreen)),
        ).push(Routes.history),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MetricExplorerScreen), findsOneWidget);
    }

    testWidgets('Sleep history opens SLEEP HISTORY, not the Sleep tab', (
      tester,
    ) async {
      // The row promises "duration, stages and regularity" and used to open
      // last night. Two screens about one subject, and only one of them is the
      // thirty nights the row names.
      _tall(tester);
      await openDirectory(tester);

      await tapText(tester, 'Sleep history');

      expect(find.byType(SleepHistoryScreen), findsOneWidget);
    });

    testWidgets('Fitness estimates opens FITNESS, not the Activity tab', (
      tester,
    ) async {
      _tall(tester);
      await openDirectory(tester);

      await tapText(tester, 'Fitness estimates');

      expect(find.byType(FitnessScreen), findsOneWidget);
    });

    testWidgets('AND BOTH ARE PUSHED, so the directory is still under them', (
      tester,
    ) async {
      // `go` REPLACES. Either row done that way would leave the destination
      // with nothing beneath it and this screen unreachable by Back — the
      // defect `out_of_shell_navigation_test.dart` was written for.
      _tall(tester);
      await openDirectory(tester);
      await tapText(tester, 'Fitness estimates');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(MetricExplorerScreen), findsOneWidget);
    });
  });
}
