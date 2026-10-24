/// Every door OUT of the tab shell, and the way back in through it.
///
/// `back_navigation_test.dart` covers the rule inside the shell — pop a route
/// pushed in a branch, non-Today → Today, Today → exit. That rule was right and
/// shipped broken anyway, because everything it governs lives *inside* the shell
/// and every screen the avatar opens lives outside it.
///
/// **`context.go` REPLACES the location.** A `go` into Settings left nothing
/// beneath it, so the shell's rule found an empty branch stack, correctly
/// concluded "not on Today", and left the app — from a screen the owner had
/// tapped into two seconds earlier. Settings → Diagnostics → back left the app
/// too. Found on a device; this suite is the half that was missing.
///
/// The other half of the same defect is that a `go`-ed screen with an `AppBar`
/// has no leading control, so these screens offered no way back **at all** —
/// not a wrong one, none. The gesture and the affordance went missing together,
/// which is why nothing on screen looked broken.
///
/// `test/mutations.sh` flips each `push` back to `go` and requires this file to
/// go red. That check is what was not there when it shipped.
///
/// ## The `parents` back-map, and the screens that had no door at all
///
/// The last group is the same defect one level in. `DetailPage` drew its back
/// control only when `Navigator.canPop()` was true, so a detail screen reached
/// with an EMPTY stack — a deep link, a notification, a restored process, or the
/// `go` this file's own title records — had no way off it. The fix is the
/// prototype's own (`app.js:8`, `core/parent_tabs.dart`): pop when there is a
/// stack, and otherwise land on the tab the screen belongs under.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/diagnostics/diagnostics_screen.dart';
import 'package:healthee/features/pairing/pairing_screen.dart';
import 'package:healthee/features/settings/device_screen.dart';
import 'package:healthee/features/settings/settings_screen.dart';
import 'package:healthee/features/signin/server_signin_screen.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:solar_icons/solar_icons.dart';

import '_today_host.dart';

/// Records every `SystemNavigator.pop` the app sends while a test runs.
///
/// Filtered to that one method: the platform channel also carries `SystemChrome`
/// and `SystemSound` traffic the framework sends on its own, and a list of
/// everything would make "nothing happened" impossible to assert.
List<String> _watchPlatformCalls(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') {
        calls.add(call.method);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

/// Sends one system back press, the way the platform does.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// A viewport tall enough to hold the whole settings screen.
///
/// The default 800x600 leaves the lower rows BUILT but below the fold, so
/// `scrollUntilVisible` reports success without moving and the tap then lands
/// outside the render tree — a silent miss that reads as "the button does
/// nothing". `reachability_test.dart` documents the same trap. A taller window
/// is the honest fix: what is asserted here is where a row GOES, not that it
/// fits above the fold.
void _tallViewport(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(420, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  group('OUT OF THE SHELL — every door the owner mark opens comes back', () {
    /// Opens Settings the way the owner does: the mark in the header.
    ///
    /// By type, not by the semantics label. The label used to be the bare word
    /// `Settings` on an avatar; the mark now carries the strap as well and says
    /// `Helio Strap · Settings, data and sync`, and a test that pins the exact
    /// wording of a label breaks every time the label is improved.
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byType(OwnerMark));
      await tester.pumpAndSettle();
    }

    /// Taps a settings row by its title, scrolling it into view first.
    ///
    /// v02's rows are `ListRow`s inside a `FlushCard`, so there is no
    /// `OutlinedButton` to look for any more; the row's own words are what the
    /// owner aims at. `ensureVisible` rather than `scrollUntilVisible` because
    /// it scrolls the row's OWN scrollable — once a push has happened there are
    /// two in the tree, the pushed screen's and the index's underneath it.
    Future<void> tapRow(WidgetTester tester, String title) async {
      final row = find.text(title);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    testWidgets('BACK FROM SETTINGS LANDS ON TODAY AND DOES NOT EXIT', (
      tester,
    ) async {
      // The reported defect, exactly: force-stop, launch, avatar, back — and the
      // owner was on the Android home screen with the process still alive.
      _tallViewport(tester);
      final platform = _watchPlatformCalls(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await openSettings(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await _pressBack(tester);

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(
        find.byType(SettingsScreen),
        findsNothing,
        reason: 'back has to leave the screen it was pressed on',
      );
      expect(
        platform,
        isNot(contains('SystemNavigator.pop')),
        reason:
            'THIS is the bug: `go` replaced the location, so the shell rule '
            'found an empty stack and correctly decided to leave the app',
      );
    });

    testWidgets('BACK FROM DIAGNOSTICS LANDS ON SETTINGS, NOT TODAY', (
      tester,
    ) async {
      // Two levels out of the shell. Settings is the only thing that makes
      // diagnostics findable, so returning to Today would lose the owner's place
      // in the surface they were working through.
      _tallViewport(tester);
      final platform = _watchPlatformCalls(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapRow(tester, 'Instruments');
      expect(find.byType(DiagnosticsScreen), findsOneWidget);

      await _pressBack(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(TodayScreen), findsNothing);
      expect(platform, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('and a second back from there lands on Today', (tester) async {
      // The whole stack unwinds one screen at a time. A `pushReplacement`
      // anywhere in it would skip a level and look almost right.
      _tallViewport(tester);
      final platform = _watchPlatformCalls(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapRow(tester, 'Instruments');

      await _pressBack(tester);
      await _pressBack(tester);

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(platform, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('back from the pairing screen unwinds one screen at a time', (
      tester,
    ) async {
      // Renamed: v02 took `/pairing` off the settings index and put it on the
      // strap's own screen, so pairing is now THREE levels out of the shell and
      // one back lands on the strap screen rather than on Settings. That is a
      // longer stack to unwind, not a weaker claim — both hops are asserted, and
      // a `pushReplacement` anywhere in it would still skip a level.
      _tallViewport(tester);
      final platform = _watchPlatformCalls(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapRow(tester, 'Amazfit Helio Strap');
      await tapRow(tester, 'Pairing and unpair');
      expect(find.byType(PairingScreen), findsOneWidget);

      await _pressBack(tester);

      expect(find.byType(DeviceScreen), findsOneWidget);
      expect(find.byType(PairingScreen), findsNothing);

      await _pressBack(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(DeviceScreen), findsNothing);
      expect(platform, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('back from the sign-in screen returns to Settings', (
      tester,
    ) async {
      _tallViewport(tester);
      final platform = _watchPlatformCalls(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await openSettings(tester);
      // v02's index names the destination rather than the action, so the row
      // reads the same signed in or out; which session is held is what the
      // screen behind it says, and `settings_screen_test.dart` asserts that.
      await tapRow(tester, 'Account & server');
      expect(find.byType(ServerSignInScreen), findsOneWidget);

      await _pressBack(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(platform, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('DONE ON A PUSHED SETUP FLOW RETURNS TO WHAT OPENED IT', (
      tester,
    ) async {
      // "Done" cannot mean one thing for both ways in. Pushed from Settings it
      // has a screen underneath and must pop to it; redirected into by an
      // unpaired app it has nothing underneath and must go to Today.
      // `router.dart::leaveSetup` asks `canPop()` rather than being told.
      //
      // Renamed with the route: what is underneath a pushed pairing flow is now
      // the strap screen, so "returns to Settings" would name the wrong screen.
      // Landing there is also the STRONGER assertion — Settings stays mounted
      // under the whole stack, so it is found whether Done popped one level or
      // threw the stack away.
      _tallViewport(tester);
      final platform = _watchPlatformCalls(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapRow(tester, 'Amazfit Helio Strap');
      await tapRow(tester, 'Pairing and unpair');
      expect(find.byType(PairingScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(HButton, 'Done'));
      await tester.pumpAndSettle();

      expect(
        find.byType(DeviceScreen),
        findsOneWidget,
        reason:
            'hard-coding the redirect\'s answer throws away the screen '
            'underneath, which looks correct until pairing is opened from here',
      );
      expect(find.byType(PairingScreen), findsNothing);
      expect(platform, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('EVERY OUT-OF-SHELL SCREEN DRAWS A BACK ARROW', (tester) async {
      // The other half of the defect, and the reason nothing looked wrong: a
      // `go`-ed screen with an `AppBar` has no leading control, so these screens
      // offered no way back AT ALL — not a wrong one, none. The gesture and the
      // affordance went missing together.
      //
      // v02 has no `AppBar` and so no `BackButton` to look for: the control is
      // `DetailHeader`, which draws an `SolarIconsOutline.arrowLeft` inside a
      // `Semantics(button: true, label: 'Go back')`. The glyph is the assertion
      // because it is the affordance — the thing that was missing.
      _tallViewport(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await openSettings(tester);

      expect(find.byIcon(SolarIconsOutline.arrowLeft), findsOneWidget);
    });
  });

  group('THE PARENTS BACK-MAP — a detail screen with an empty stack', () {
    /// The app's own router, driven to [location] the way a deep link does.
    ///
    /// `context.go` REPLACES, which this file's title records — so this leaves
    /// the destination with **nothing underneath it**, which is exactly the
    /// state a deep link, a notification and a restored process produce. The
    /// defect is not reachable any other way, and it is the state the old
    /// `canPop() ? pop : null` drew no control for.
    Future<void> deepLink(WidgetTester tester, String location) async {
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(TodayScreen))).go(location);
      await tester.pumpAndSettle();
    }

    testWidgets('DRAWS A BACK CONTROL WITH NOTHING TO POP', (tester) async {
      // The defect itself: no stack, no arrow, no way off the screen. Not a
      // wrong way back — none.
      await deepLink(tester, Routes.body);

      expect(find.byType(BodyScreen), findsOneWidget);
      expect(
        find.byIcon(SolarIconsOutline.altArrowLeft),
        findsOneWidget,
        reason: 'a restored detail screen has to offer a way off it',
      );
    });

    testWidgets('BACK LANDS ON THE MAPPED PARENT TAB, NOT ON TODAY', (
      tester,
    ) async {
      // `app.js:8` files `body` under `activity`. Today would be the lazy
      // answer and would look right on every screen the map exists for.
      final platform = _watchPlatformCalls(tester);
      await deepLink(tester, Routes.body);

      await tester.tap(find.byIcon(SolarIconsOutline.altArrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(ActivityScreen), findsOneWidget);
      expect(find.byType(BodyScreen), findsNothing);
      expect(platform, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('a system back press takes the same door', (tester) async {
      // The gesture and the affordance went missing together last time, so
      // they are asserted together this time.
      final platform = _watchPlatformCalls(tester);
      await deepLink(tester, Routes.body);

      await _pressBack(tester);

      expect(find.byType(BodyScreen), findsNothing);
      expect(platform, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('AND A PUSHED DETAIL SCREEN STILL POPS TO WHAT OPENED IT', (
      tester,
    ) async {
      // The fallback must not become the rule. Opened from Today's hero, back
      // returns to Today — never to `body`'s mapped tab, which the owner was
      // not on.
      _tallViewport(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AgeSphere));
      await tester.pumpAndSettle();
      expect(find.byType(BodyScreen), findsOneWidget);

      await tester.tap(find.byIcon(SolarIconsOutline.altArrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(
        find.byType(ActivityScreen),
        findsNothing,
        reason: 'the map is the FALLBACK; a real stack outranks it',
      );
    });
  });
}
