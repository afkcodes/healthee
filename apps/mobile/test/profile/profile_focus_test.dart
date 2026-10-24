/// `/profile?focus=<field>`: the link the paused-age button sends, and what the
/// profile screen does with it.
///
/// The rule that must survive every case: **the weight field opens empty.** A
/// focused weight field is a place to type a new weigh-in, never a prefilled
/// old one (`profile_editor.dart`'s library docstring says why).
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/profile_field.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/profile/profile_repository.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/profile/profile_screen.dart';
import 'package:healthee/shared/v02/buttons.dart';

import '../features/_today_overrides.dart' show profileFixture;

/// A repository whose save waits for the test to let it finish.
class _SlowRepository extends ProfileRepository {
  const _SlowRepository(super.api, this.gate);

  final Completer<void> gate;

  @override
  Future<void> save({
    required String name,
    required double? heightCm,
    required String? sex,
    String? dobDate,
    int? srpa,
    bool updateSrpa = false,
    double? measuredWeightKg,
  }) => gate.future;
}

void main() {
  group('the link', () {
    test(
      'profileLocation spells each field the way profileFocusOf reads it',
      () {
        expect(profileLocation(), '/profile');
        for (final field in ProfileField.values) {
          final location = profileLocation(focus: field);
          expect(location, '/profile?focus=${field.name}');
          expect(profileFocusOf(Uri.parse(location)), field);
        }
      },
    );

    test('a plain or unknown link focuses nothing', () {
      expect(profileFocusOf(Uri.parse('/profile')), isNull);
      expect(profileFocusOf(Uri.parse('/profile?focus=')), isNull);
      expect(profileFocusOf(Uri.parse('/profile?focus=shoe_size')), isNull);
    });
  });

  group('the screen', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      ProfileField? focus,
      ProfileRepository? repository,
      HealthProfile? profile,
      Widget? home,
    }) async {
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = AccountApi(Dio(), await CacheSession.capture(null));
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          key: key,
          overrides: [
            profileRepositoryProvider.overrideWith(
              (ref) async => repository ?? ProfileRepository(api),
            ),
            healthProfileProvider.overrideWith(
              (ref) async => profile ?? profileFixture(),
            ),
            todaySnapshotProvider.overrideWith(
              (ref) => Completer<Never>().future,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: home ?? ProfileScreen(focus: focus),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
    }

    bool hasFocus(WidgetTester tester, Finder field) => tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus;

    testWidgets('focus=weight opens the weigh-in field, focused and EMPTY', (
      tester,
    ) async {
      await pump(tester, focus: ProfileField.weight);

      expect(find.text('Log a new weigh-in'), findsNothing);
      final field = find.ancestor(
        of: find.text('New weigh-in today'),
        matching: find.byType(Column),
      );
      final weight = find.descendant(
        of: field.first,
        matching: find.byType(TextField),
      );
      expect(weight, findsOneWidget);
      expect(tester.widget<TextField>(weight).controller!.text, isEmpty);
      expect(hasFocus(tester, field.first), isTrue);
    });

    testWidgets('focus=height focuses the height field', (tester) async {
      await pump(tester, focus: ProfileField.height);

      final height = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == '176.0',
      );
      expect(height, findsOneWidget);
      expect(hasFocus(tester, height), isTrue);
    });

    testWidgets('no focus leaves the keyboard down and the weigh-in a button', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Log a new weigh-in'), findsOneWidget);
      expect(find.byType(EditableText), findsWidgets);
      for (final field in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        expect(field.focusNode.hasFocus, isFalse);
      }
    });

    testWidgets('focus=dob opens the date picker', (tester) async {
      await pump(tester, focus: ProfileField.dob);

      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('a save finished after the owner left still refreshes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = AccountApi(Dio(), await CacheSession.capture(null));
      final container = await pump(
        tester,
        repository: _SlowRepository(api, gate),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const ProfileScreen(focus: ProfileField.weight),
                ),
              ),
              child: const Text('open profile'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open profile'));
      await tester.pumpAndSettle();
      var profileReads = 0;
      container.listen(healthProfileProvider, (previous, next) {
        profileReads++;
      });
      await tester.pumpAndSettle();
      final before = profileReads;

      await tester.enterText(find.byType(TextField).last, '73.1');
      await tester.tap(find.widgetWithText(HButton, 'Save profile'));
      await tester.pump();

      // The owner navigates away while the write is in flight.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();

      expect(
        profileReads,
        greaterThan(before),
        reason: 'the refresh must not depend on the editor still being mounted',
      );
    });
  });
}
