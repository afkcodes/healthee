/// The Insights pattern tile opens the finding, and carries it there.
///
/// The owner, on the installed build: *"click ing on it nothing happens where as
/// in our design demo on clicked it shows data related."* The card had carried
/// an `onOpen` since it was built and nothing ever passed it, so the card looked
/// complete and did nothing. Nothing failed, because a widget that is never
/// handed a callback cannot fail.
///
/// This is the guard: tap the tile, assert the location changed to the finding's
/// own route, and assert the finding travelled with it — the screen must draw
/// the numbers the card was showing rather than re-deriving them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/features/insights/v02/finding_detail_screen.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';

const Finding _finding = Finding(
  kind: 'pairwise_lag',
  metricA: 'hrv_sleep_avg',
  metricB: 'recovery_score',
  eventKind: null,
  description: '',
  effectSize: 0.7794,
  effectMetric: 'spearman_r',
  qValue: 3.15e-27,
  nSamples: 138,
  lagDays: 0,
  researchNoteIds: <String>['slow_breathing_hrv_acute'],
);

void main() {
  testWidgets('THE PATTERN TILE OPENS THE FINDING', (tester) async {
    String? landed;
    Object? carried;
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Center(child: PatternHeroTile(finding: _finding)),
          ),
        ),
        GoRoute(
          path: '${Routes.insight}/:key',
          builder: (context, state) {
            landed = state.pathParameters['key'];
            carried = state.extra;
            return const Scaffold(body: Text('opened'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    // The tile is one tap target; its words are in the semantics, for a reader
    // who cannot see it.
    expect(
      find.bySemanticsLabel(RegExp('HRV and Recovery')),
      findsOneWidget,
      reason: 'the destination must still be announced',
    );

    await tester.tap(find.byType(PatternHeroTile));
    await tester.pumpAndSettle();

    expect(find.text('opened'), findsOneWidget);
    expect(landed, findingKey(_finding));
    // Not merely "a finding" — THIS finding. Re-resolving by key would be a
    // second source of truth for numbers already on screen.
    expect(identical(carried, _finding), isTrue);
  });

  testWidgets('a cold start with no finding says so, and does not invent one', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '${Routes.insight}/nothing~here~0',
      routes: <RouteBase>[
        GoRoute(
          path: '${Routes.insight}/:key',
          builder: (context, state) =>
              FindingDetailScreen(routeKey: state.pathParameters['key'] ?? ''),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('isn’t in your current results'),
      findsOneWidget,
    );
    // The path segment holds two names and a lag. It must not become a claim.
    expect(find.textContaining('0.'), findsNothing);
  });
}
