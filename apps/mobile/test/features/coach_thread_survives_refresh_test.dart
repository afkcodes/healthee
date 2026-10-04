// The answer that "went off": after every answer the meter is re-read, and the
// thread used to live inside the meter's loading/error view. One failed
// re-read on a phone network replaced the answer with an error screen. Now a
// thread that exists stays, on the last known balance, with a one-line notice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_screen.dart';

import '_coach_overrides.dart';

Entitlement _premium() => Entitlement.fromJson(const <String, Object?>{
  'premium': true,
  'status': 'active',
  'locked': <String>[],
  'included': <Object?>[
    <String, Object?>{
      'feature': 'coach',
      'limit': 20,
      'used': 3,
      'remaining': 17,
      'window_days': 30,
      'resets_at': '2026-10-20T00:00:00Z',
    },
  ],
});

const CoachAnswer _answer = CoachAnswer(
  reply: 'You slept 6 h 20 on average this week [sleep_need_debt].',
  citations: <String>['sleep_need_debt'],
  gradeFloor: 'Probable',
  refused: false,
  validated: true,
);

/// The balance reads once, then every re-read fails — a phone losing signal
/// for the one second the app happened to ask.
class _FlakyBalance implements CoachClient {
  int reads = 0;

  @override
  Future<Entitlement> entitlement() async {
    reads++;
    if (reads == 1) {
      return _premium();
    }
    throw const CoachUnreachable(
      'No route to the server.',
      CoachCharge.unknown,
    );
  }

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async =>
      _answer;

  @override
  Stream<CoachStreamEvent> askStream(
    List<CoachTurn> messages, {
    String? topic,
  }) async* {
    yield const CoachAnswerEvent(_answer);
  }
}

void main() {
  testWidgets(
    'a delivered answer stays on screen when the balance re-read fails',
    (tester) async {
      final client = _FlakyBalance();
      await tester.pumpWidget(
        coachScope(
          client: client,
          child: MaterialApp(theme: AppTheme.light, home: const CoachScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How did I sleep?');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(client.reads, greaterThan(1), reason: 'the meter was re-read');
      expect(find.textContaining('You slept 6 h 20'), findsOneWidget);
      expect(find.text('How did I sleep?'), findsOneWidget);
      expect(find.textContaining(kCoachBalanceRefreshFailed), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.textContaining("Couldn't read what your account includes"),
        findsNothing,
      );
    },
  );
}
