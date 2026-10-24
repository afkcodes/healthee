/// The paused biological-age hero: why, in the server's words, and the one
/// button that would bring the number back.
///
/// Hosted on a real `GoRouter` because the button navigates: the assertion is
/// the location it lands on (`/profile?focus=weight`), not that something was
/// tapped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/models/age_pause.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/age_paused.dart';
import 'package:healthee/features/today/v02/today_hero_withheld.dart';
import 'package:healthee/shared/v02/buttons.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';
import '_today_host.dart';
import '_today_overrides.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  /// Today on a real router, with `/profile` recording where it was sent.
  Future<List<Uri>> pumpRouted(
    WidgetTester tester, {
    required Map<String, Object?> Function(Map<String, Object?>) mutate,
    HealthProfile? profile,
    bool profileFails = false,
    double textScale = 1.0,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 1500)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final visited = <Uri>[];
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => TodayScreen(now: now),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) {
            visited.add(state.uri);
            return const Scaffold(body: Text('profile screen'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      todayScoped(
        store,
        server: todayView(mutate: mutate),
        profile: profile,
        profileFails: profileFails,
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return visited;
  }

  group('a stale weight', () {
    testWidgets(
      'SHOWS THE HEADLINE, THE SERVER LINE, THE AGE OF THE WEIGHT AND THE BUTTON',
      (tester) async {
        await pumpRouted(
          tester,
          mutate: pausedToday(absentTerms: [staleWeightTerm()]),
          profile: profileFixture(
            mutate: (json) => <String, Object?>{...json, 'weight_age_days': 41},
          ),
        );

        expect(find.text(kAgePausedTitle), findsOneWidget);
        expect(find.text(kStaleWeightMessage), findsOneWidget);
        expect(find.text('Weight last updated 41 days ago'), findsOneWidget);
        expect(find.widgetWithText(HButton, 'Update weight'), findsOneWidget);
      },
    );

    testWidgets('THE BUTTON OPENS THE PROFILE ON THE WEIGHT', (tester) async {
      final visited = await pumpRouted(
        tester,
        mutate: pausedToday(absentTerms: [staleWeightTerm()]),
      );

      await tester.tap(find.text('Update weight'));
      await tester.pumpAndSettle();

      expect(visited.single.toString(), '/profile?focus=weight');
    });

    testWidgets('A SINGLE DAY IS NOT "1 days"', (tester) async {
      await pumpRouted(
        tester,
        mutate: pausedToday(absentTerms: [staleWeightTerm()]),
        profile: profileFixture(
          mutate: (json) => <String, Object?>{...json, 'weight_age_days': 1},
        ),
      );
      expect(find.text('Weight last updated 1 day ago'), findsOneWidget);
    });

    testWidgets('NO NUMBER IS DRAWN ON THE HERO', (tester) async {
      await pumpRouted(
        tester,
        mutate: pausedToday(absentTerms: [staleWeightTerm()]),
      );

      expect(find.text('YEARS'), findsNothing);
      expect(find.textContaining('years younger'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(TodayBioHeroWithheld),
          matching: find.text('34.3'),
        ),
        findsNothing,
      );
    });

    testWidgets('DOES NOT CLIP AT 1.3x TEXT', (tester) async {
      await pumpRouted(
        tester,
        mutate: pausedToday(absentTerms: [staleWeightTerm()]),
        textScale: 1.3,
      );

      // Today's illness banner overflows at this scale on its own (it does
      // with no estimate paused too); that is another widget's defect, so the
      // exception is drained and this notice is measured directly.
      tester.takeException();
      final notice = tester.getRect(find.byType(AgePausedNotice));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(notice.left, greaterThanOrEqualTo(screen.left));
      expect(notice.right, lessThanOrEqualTo(screen.right));
    });
  });

  group('the profile cannot be read', () {
    testWidgets(
      'THE SERVER LINE STILL SHOWS AND THE BUTTON OPENS THE PROFILE',
      (tester) async {
        final visited = await pumpRouted(
          tester,
          mutate: pausedToday(absentTerms: [profileMissingTerm()]),
          profileFails: true,
        );

        expect(find.text(kProfileMissingMessage), findsOneWidget);
        expect(find.textContaining('Weight last updated'), findsNothing);

        await tester.tap(find.widgetWithText(HButton, kOpenProfileLabel));
        await tester.pumpAndSettle();
        expect(visited.single.toString(), '/profile');
      },
    );
  });

  group('time is the only fix', () {
    testWidgets('TOO FEW NIGHTS SHOWS THE SENTENCE AND NO BUTTON', (
      tester,
    ) async {
      await pumpRouted(
        tester,
        mutate: pausedToday(absentTerms: [noNightsTerm()], keepSleep: false),
      );

      expect(find.text(kNoNightsMessage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AgePausedNotice),
          matching: find.byType(HButton),
        ),
        findsNothing,
      );
    });
  });

  group('a block the server sent as null', () {
    testWidgets('NO DATE OF BIRTH SAYS SO AND OFFERS TO FIX IT', (
      tester,
    ) async {
      final visited = await pumpRouted(
        tester,
        mutate: nullBioAge,
        profile: profileFixture(
          mutate: (json) => <String, Object?>{
            ...json,
            'dob': null,
            'dob_date': null,
          },
        ),
      );

      expect(find.text(kNoDobLine), findsOneWidget);
      expect(find.textContaining('a bug on our side'), findsNothing);

      await tester.tap(find.widgetWithText(HButton, 'Update date of birth'));
      await tester.pumpAndSettle();
      expect(visited.single.toString(), '/profile?focus=dob');
    });

    testWidgets('A COMPLETE PROFILE GETS THE TWO-READINGS SENTENCE', (
      tester,
    ) async {
      await pumpRouted(tester, mutate: nullBioAge);

      expect(find.text(kBothTermsLine), findsOneWidget);
      expect(find.byType(HButton), findsNothing);
    });
  });

  testWidgets('THE PAUSED HERO CAN OPEN THE CALCULATION LIKE THE LIVE ONE', (
    tester,
  ) async {
    await pumpRouted(
      tester,
      mutate: pausedToday(absentTerms: [staleWeightTerm()]),
    );

    final hero = tester.widget<TodayBioHeroWithheld>(
      find.byType(TodayBioHeroWithheld),
    );
    expect(hero.onOpen, isNotNull);
  });
}
