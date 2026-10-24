/// The breathing screens at dpr 3, 390 wide, light and dark. **Not a test**:
/// run by hand with `flutter test test/render/render_breathing.dart`.
///
/// Writes `build/renders/breathing-<screen>-<light|dark>[-text13].png`, to be
/// looked at against `design/redesign-2026-10/04`, `08` and `09`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/water/water_controller.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/coach/breathing_plan_screen.dart';
import 'package:healthee/features/coach/breathing_player_screen.dart';
import 'package:healthee/features/coach/v02/todays_basics_section.dart';
import 'package:healthee/features/coach/v02/water_card.dart';

import '../features/coach/_breathing_fakes.dart';
import '../features/coach/water_fakes.dart';
import 'render_support.dart';

/// The home basics: the water card over the breathing card.
Widget _basics(LocalStore store, FakeWaterServer server) => ProviderScope(
  overrides: [
    localStoreProvider.overrideWithValue(store),
    waterClockProvider.overrideWithValue(() => kWaterNow),
    journalRepositoryProvider.overrideWith(
      (ref) async =>
          JournalRepository(server.dio(), await CacheSession.capture(null)),
    ),
    journalFeedProvider.overrideWith(
      (ref) => Stream.value(
        ServerSnapshot(
          JournalFeed(entries: server.entries, fastOpen: false),
          fetchedAt: DateTime.now(),
        ),
      ),
    ),
  ],
  child: const Scaffold(
    body: SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: TodaysBasicsSection(water: WaterCard()),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetsApp.debugAllowBannerOverride = false;
  setUpAll(loadBundledFonts);

  for (final brightness in Brightness.values) {
    for (final scale in <double>[1, 1.3]) {
      final tag = '${brightness.name}${scale == 1 ? '' : '-text13'}';

      testWidgets('render basics $tag', (tester) async {
        final store = LocalStore.memory();
        addTearDown(store.close);
        final harness = BreathingHarness(store)
          ..done = {BreathingItemKind.morning};
        final server = FakeWaterServer([
          waterEntry('a', 9, 10),
          waterEntry('b', 11, 40),
          waterEntry('c', 13, 5),
        ]);
        await shoot(
          tester,
          'breathing-basics-$tag',
          harness.app(
            _basics(store, server),
            brightness: brightness,
            textScale: scale,
          ),
          size: Size(390, scale == 1 ? 760 : 1000),
          dpr: 3,
        );
      });

      testWidgets('render plan $tag', (tester) async {
        final store = LocalStore.memory();
        addTearDown(store.close);
        await shoot(
          tester,
          'breathing-plan-$tag',
          BreathingHarness(store).app(
            const BreathingPlanScreen(),
            brightness: brightness,
            textScale: scale,
          ),
          size: Size(390, scale == 1 ? 1900 : 2500),
          dpr: 3,
        );
      });

      testWidgets('render player $tag', (tester) async {
        final store = LocalStore.memory();
        addTearDown(store.close);
        await shoot(
          tester,
          'breathing-player-$tag',
          BreathingHarness(store).app(
            const BreathingPlayerScreen(item: 'night'),
            brightness: brightness,
            textScale: scale,
          ),
          size: Size(390, scale == 1 ? 844 : 1000),
          dpr: 3,
          beforeShot: (tester) => tester.pump(const Duration(seconds: 231)),
        );
      });
    }
  }
  // Keeps the route name in a render's imports honest.
  test('the player route exists', () {
    expect(Routes.breathingPlayer, isNotEmpty);
  });
}
