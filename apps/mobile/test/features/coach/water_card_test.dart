import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/coach/v02/water_card.dart';

import 'water_fakes.dart';

Future<FakeWaterServer> _open(
  WidgetTester tester,
  List<dynamic> entries, {
  double textScale = 1,
  bool settle = true,
  void Function(FakeWaterServer)? prepare,
}) async {
  tester.view
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = LocalStore.memory();
  addTearDown(store.close);
  final server = FakeWaterServer(List.of(entries.cast()));
  prepare?.call(server);
  await tester.pumpWidget(waterHost(server, store, textScale: textScale));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return server;
}

final _three = [
  waterEntry('a', 9, 10),
  waterEntry('b', 11, 40),
  waterEntry('c', 13, 5),
];

Finder _glass(int n) => find.bySemanticsLabel(RegExp('^Glass $n,'));

void main() {
  testWidgets('three of eight, times under the full glasses, default label', (
    tester,
  ) async {
    await _open(tester, _three);
    expect(find.text('Water'), findsOneWidget);
    expect(find.textContaining('of 8 glasses'), findsOneWidget);
    expect(find.text('750 of 2,000 ml'), findsOneWidget);
    expect(find.text('default · change'), findsOneWidget);
    expect(find.text('9:10'), findsOneWidget);
    expect(find.text('11:40'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text(kWaterCaption), findsOneWidget);
  });

  testWidgets('a 500 ml entry fills two glasses with no times', (tester) async {
    await _open(tester, [waterEntry('a', 9, 10, 500)]);
    expect(find.text('9:10'), findsNothing);
    expect(find.text('500 of 2,000 ml'), findsOneWidget);
    expect(_glass(2), findsOneWidget);
    expect(
      tester.getSemantics(_glass(2)).label,
      'Glass 2, full. Double tap to undo the last entry',
    );
    expect(
      tester.getSemantics(_glass(3)).label,
      'Glass 3, empty. Double tap to log 250 millilitres',
    );
  });

  testWidgets('no entries: nothing filled, the first glass is the next', (
    tester,
  ) async {
    await _open(tester, const []);
    expect(find.textContaining('of 8 glasses'), findsOneWidget);
    expect(find.text('0 of 2,000 ml'), findsOneWidget);
    expect(
      tester.getSemantics(_glass(1)).label,
      'Glass 1, empty. Double tap to log 250 millilitres',
    );
    expect(tester.getSemantics(_glass(2)).label, 'Glass 2, empty');
  });

  testWidgets('semantics for a full glass names its time', (tester) async {
    await _open(tester, _three);
    expect(
      tester.getSemantics(_glass(3)).label,
      'Glass 3, full, logged 1:05. Double tap to undo the last entry',
    );
  });

  testWidgets('over the count shows the extra filled glasses', (tester) async {
    await _open(tester, [
      for (var i = 0; i < 9; i++) waterEntry('e$i', 6 + i, 0),
    ]);
    expect(find.textContaining('of 8 glasses'), findsOneWidget);
    expect(_glass(9), findsOneWidget);
    expect(tester.getSemantics(_glass(9)).label, contains('full'));
    expect(tester.getSemantics(_glass(10)).label, contains('empty'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text scale 1.3 does not overflow', (tester) async {
    await _open(tester, _three, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap the next glass posts 250 ml once and shows it at once', (
    tester,
  ) async {
    final server = await _open(tester, _three);
    await tester.tap(_glass(4));
    await tester.pump();
    expect(find.text('1000 of 2,000 ml'), findsNothing);
    expect(find.text('1,000 of 2,000 ml'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r == 'POST /api/log'), hasLength(1));
    final body = server.posted.single! as Map<String, Object?>;
    expect(body['type'], 'water');
    expect(body['amount'], 250);
    expect(body['unit'], 'ml');
  });

  testWidgets('a later empty glass does nothing', (tester) async {
    final server = await _open(tester, _three);
    await tester.tap(_glass(6));
    await tester.pumpAndSettle();
    expect(server.requests, isEmpty);
  });

  testWidgets('a failed log rolls back and says so', (tester) async {
    final server = await _open(
      tester,
      _three,
      prepare: (s) => s.failWrites = true,
    );
    await tester.tap(_glass(4));
    await tester.pumpAndSettle();
    expect(server.requests, ['POST /api/log']);
    expect(find.text('750 of 2,000 ml'), findsOneWidget);
    expect(find.text('Could not log that glass. Nothing was saved.'), findsOne);
  });

  testWidgets('tap a full glass deletes the latest entry by id', (
    tester,
  ) async {
    final server = await _open(tester, _three);
    await tester.tap(_glass(1));
    await tester.pump();
    expect(find.text('500 of 2,000 ml'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(server.requests, ['DELETE /api/log/c']);
  });

  testWidgets('undo removes the most recent entry whatever its size', (
    tester,
  ) async {
    final server = await _open(tester, [
      waterEntry('a', 9, 10),
      waterEntry('b', 11, 40, 500),
    ]);
    await tester.tap(_glass(1));
    await tester.pumpAndSettle();
    expect(server.requests, ['DELETE /api/log/b']);
  });

  testWidgets('a failed delete rolls back and says so', (tester) async {
    final server = await _open(
      tester,
      _three,
      prepare: (s) => s.failWrites = true,
    );
    await tester.tap(_glass(2));
    await tester.pumpAndSettle();
    expect(server.requests, ['DELETE /api/log/c']);
    expect(find.text('750 of 2,000 ml'), findsOneWidget);
    expect(
      find.text('Could not undo that glass. It is still logged.'),
      findsOneWidget,
    );
  });

  testWidgets('a 404 on delete refreshes the feed and shows no error', (
    tester,
  ) async {
    final server = await _open(
      tester,
      _three,
      prepare: (s) => s.deleteMissing = true,
    );
    final reads = server.feedReads;
    server.entries = _three.sublist(0, 2);
    await tester.tap(_glass(1));
    await tester.pumpAndSettle();
    expect(server.feedReads, greaterThan(reads));
    expect(find.text('500 of 2,000 ml'), findsOneWidget);
    expect(find.textContaining('Could not'), findsNothing);
  });

  testWidgets('while the feed loads there is a skeleton', (tester) async {
    await _open(
      tester,
      const [],
      settle: false,
      prepare: (s) => s.feedNever = true,
    );
    expect(find.bySemanticsLabel('Loading your water log'), findsOneWidget);
    expect(find.text('Water'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a feed error is one honest line with retry', (tester) async {
    final server = await _open(
      tester,
      const [],
      prepare: (s) => s.failFeed = true,
    );
    expect(find.text('Could not load your water log.'), findsOneWidget);
    server.failFeed = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 2,000 ml'), findsOneWidget);
  });

  testWidgets('change opens the sheet; saving flips the label to set by you', (
    tester,
  ) async {
    await _open(tester, _three);
    await tester.tap(find.text('default · change'));
    await tester.pumpAndSettle();
    expect(
      find.text('Pick your own number. There is no one right amount.'),
      findsOneWidget,
    );
    expect(find.text('2,000 ml'), findsOneWidget);
    await tester.tap(find.byTooltip('Fewer glasses'));
    await tester.pump();
    expect(find.text('7 glasses'), findsOneWidget);
    expect(find.text('1,750 ml'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('set by you · change'), findsOneWidget);
    expect(find.textContaining('of 7 glasses'), findsOneWidget);
    expect(find.text('750 of 1,750 ml'), findsOneWidget);
  });
}
