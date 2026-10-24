/// Every uploaded track, on the v02 detail frame.
///
/// **This screen has no prototype counterpart.** `#record` links straight to a
/// single `#route`, because the preview holds exactly one fixture track; a real
/// account has as many as it has recorded, so the list is the app's and is drawn
/// from the vocabulary the prototype's own list screens use — `workouts` is the
/// nearest, and its rows are the same `V02ListRow` inside a `FlushCard`.
///
/// It was one of the last three legacy `Scaffold`/`AppBar` screens in the app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/data/gps/route_repository.dart';
import 'package:healthee/data/gps/route_summary.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/states/account_async_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/full_button.dart';
import 'package:healthee/shared/v02/list_rows.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:solar_icons/solar_icons.dart';

/// The screen's own h1 and eyebrow.
const String kRoutesTitle = 'Your recorded routes.';

/// Its eyebrow.
const String kRoutesEyebrow = 'Uploaded tracks';

/// What an account with nothing uploaded is told, and why it is not an error.
const String kNoRoutes =
    'No uploaded tracks yet. Record an outdoor workout and upload it, and it '
    'will be listed here.';

/// The saved-route list.
class RoutesScreen extends ConsumerWidget {
  /// Builds the screen.
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `panels.js:3` files the whole workout group under movement.
    return ToneScope(
      tone: Tone.movement,
      child: DetailPage(
        title: kRoutesTitle,
        eyebrow: kRoutesEyebrow,
        children: <Widget>[
          AccountAsyncView<List<RouteSummary>>(
            value: ref.watch(recordedRoutesProvider),
            onRetry: () => ref.invalidate(recordedRoutesProvider),
            builder: (context, routes) => routes.isEmpty
                // "Nothing recorded" and "we could not read it" are different
                // sentences, and `AccountAsyncView` already owns the second.
                ? const EmptyState(
                    message: 'No uploaded tracks yet',
                    hint: kNoRoutes,
                  )
                : FlushCard(
                    rows: <Widget>[
                      for (final RouteSummary route in routes)
                        _RouteRow(route: route),
                    ],
                  ),
          ),
          const SectionGap(),
          V02FullButton(
            label: 'Record another route',
            onPressed: () => unawaited(context.push(Routes.gps)),
          ),
          const DataFooter(),
        ],
      ),
    );
  }
}

/// One track: when it was, and how far it went.
class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.route});

  final RouteSummary route;

  @override
  Widget build(BuildContext context) {
    final DateTime local = route.start.toLocal();
    return V02ListRow(
      icon: SolarIconsOutline.routing,
      title: '${shortDate(local.toIso8601String())} · ${clockLabel(local)}',
      detail: _detail(),
      tone: Tone.movement,
      onOpen: () => unawaited(
        context.push('${Routes.route}/${Uri.encodeComponent(route.id)}'),
      ),
    );
  }

  /// Distance and duration, and only the ones the server actually sent.
  ///
  /// A track whose summary carried neither says so rather than printing `0 km`,
  /// which is a distance rather than the absence of one.
  String _detail() {
    final List<String> parts = <String>[
      if (route.distanceKm case final double km) '${km.toStringAsFixed(2)} km',
      if (route.durationS case final int seconds) durationText(seconds ~/ 60),
    ];
    return parts.isEmpty
        ? 'Distance and duration unavailable'
        : parts.join(' · ');
  }
}
