import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/review_models.dart';
import 'package:healthee/data/coach/review_repository.dart';
import 'package:healthee/features/coach/v02/home_review_card.dart';
import 'package:healthee/shared/skeletons/h_skeleton.dart';

import '../_settings_harness.dart' show tallViewport;
import '_coach_home_fakes.dart';

Future<CoachHost> _open(
  WidgetTester tester, {
  Future<CoachReview> Function(int call)? respond,
}) async {
  tallViewport(tester);
  final host = await CoachHost.create();
  if (respond != null) {
    host.respond = respond;
  }
  await tester.pumpWidget(host.wrap(const WeeklyReviewCard()));
  await tester.pumpAndSettle();
  return host;
}

void main() {
  testWidgets('opening the screen asks the server for nothing', (tester) async {
    final host = await _open(tester);
    expect(host.reviews.calls, 0);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(
      find.text('19 to 25 Oct · written when you open it'),
      findsOneWidget,
    );
    expect(find.textContaining('Straight talk'), findsNothing);
  });

  testWidgets('expanding asks once, shows review then pattern, fresh footer', (
    tester,
  ) async {
    final host = await _open(tester);
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();

    expect(host.reviews.calls, 1);
    final review = tester.getTopLeft(find.textContaining('Straight talk'));
    final pattern = tester.getTopLeft(
      find.textContaining('say yes on Mondays'),
    );
    expect(pattern.dy, greaterThan(review.dy));
    expect(find.text('Written just now, when you opened it'), findsOneWidget);
    expect(find.text('Kept until Sunday'), findsOneWidget);
    // Opened: the subtitle is the range alone.
    expect(find.text('19 to 25 Oct'), findsOneWidget);
  });

  testWidgets('closing and opening again does not ask again', (tester) async {
    final host = await _open(tester);
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Straight talk'), findsNothing);
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Straight talk'), findsOneWidget);
    expect(host.reviews.calls, 1);
  });

  testWidgets('a stored review is footed with its weekday, not just now', (
    tester,
  ) async {
    await _open(
      tester,
      respond: (_) async => review(
        cached: true,
        generatedAt: DateTime(2026, 10, 19, 9, 30).toUtc(),
      ),
    );
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(find.text('Written Monday'), findsOneWidget);
    expect(find.textContaining('just now'), findsNothing);
  });

  testWidgets('no review: the honest line, no number, no footer', (
    tester,
  ) async {
    await _open(
      tester,
      respond: (_) async => review(text: null, pattern: null),
    );
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(find.text(kNoReview), findsOneWidget);
    expect(find.text('Kept until Sunday'), findsNothing);
  });

  testWidgets('while the first call is pending a skeleton shows', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _open(
      tester,
      respond: (_) async {
        await gate.future;
        return review();
      },
    );
    await tester.tap(find.text('Weekly review'));
    await tester.pump();
    expect(find.byType(HSkeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(HSkeleton), findsNothing);
    expect(find.textContaining('Straight talk'), findsOneWidget);
  });

  testWidgets('a 402 is the gate speaking: its words, no retry', (
    tester,
  ) async {
    await _open(
      tester,
      respond: (_) async => throw CoachRefusal(
        message: 'You have used all 20 coach questions in this window.',
        resetsAt: DateTime(2026, 11, 2),
      ),
    );
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(
      find.text('You have used all 20 coach questions in this window.'),
      findsOneWidget,
    );
    expect(find.text('Your window reopens 2 Nov.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a failure says so and Try again asks a second time', (
    tester,
  ) async {
    final host = await _open(
      tester,
      respond: (call) async => call == 1
          ? throw const ReviewFailure('The review is still being written.')
          : review(),
    );
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(find.text('The review is still being written.'), findsOneWidget);
    expect(host.reviews.calls, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(host.reviews.calls, 2);
    expect(find.textContaining('Straight talk'), findsOneWidget);
  });
}
