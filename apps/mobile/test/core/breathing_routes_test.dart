/// The breathing paths: the plan, the player's two ways in, the notification
/// that opens the plan, and that the router wires them.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';

void main() {
  test('the paths', () {
    expect(Routes.breathingPlan, '/breathing');
    expect(Routes.breathingPlayer, '/breathing/play');
  });

  test('a player location carries an item or a pattern, item first', () {
    expect(
      breathingPlayerLocation(item: 'night'),
      '/breathing/play?item=night',
    );
    expect(
      breathingPlayerLocation(pattern: 'box'),
      '/breathing/play?pattern=box',
    );
    expect(
      breathingPlayerLocation(item: 'onDemand', pattern: 'box'),
      '/breathing/play?item=onDemand',
    );
    expect(breathingPlayerLocation(), '/breathing/play');
  });

  test('every plan item name round-trips through the location', () {
    for (final kind in BreathingItemKind.values) {
      final uri = Uri.parse(breathingPlayerLocation(item: kind.name));
      expect(uri.path, Routes.breathingPlayer);
      expect(uri.queryParameters['item'], kind.name);
    }
  });

  test('the breathing notification payload opens the plan', () {
    expect(notificationRoute('breathing'), Routes.breathingPlan);
    expect(notificationRoute('sleep'), Routes.sleep);
    expect(notificationRoute('actions'), Routes.actions);
    expect(notificationRoute('anything else'), Routes.actions);
  });

  test('the router wires both paths', () {
    final router = File('lib/core/router.dart').readAsStringSync();
    expect(router, contains('path: Routes.breathingPlan'));
    expect(router, contains('path: Routes.breathingPlayer'));
    expect(
      File('lib/app.dart').readAsStringSync(),
      contains('notificationRoute(destination)'),
    );
  });
}
