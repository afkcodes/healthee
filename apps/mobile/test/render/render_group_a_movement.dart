/// Activity, workout and GPS cases of the group A render harness. **Not a test**; see
/// `render_group_a.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/gps/gps_local_store.dart';
import 'package:healthee/data/gps/gps_repository.dart';
import 'package:healthee/data/gps/route_repository.dart';
import 'package:healthee/data/history/history_repository.dart';
import 'package:healthee/data/map/basemap_source.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/workouts/workout_repository.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/activity/fitness_screen.dart';
import 'package:healthee/features/gps/gps_screen.dart';
import 'package:healthee/features/gps/route_detail_screen.dart';
import 'package:healthee/features/gps/routes_screen.dart';
import 'package:healthee/features/trends/trends_period.dart';
import 'package:healthee/features/trends/trends_screen.dart';
import 'package:healthee/features/workouts/workout_detail_screen.dart';
import 'package:healthee/features/workouts/workout_history_screen.dart';

import '../features/_workouts_host.dart'
    show kWorkoutStart, sessionsFixture, workoutFixture;
import 'render_group_a_support.dart';
import 'render_samples.dart';

/// Activity, Fitness, the workouts, GPS and Trends.
List<GroupCase> movementCases(LocalStore Function() getStore) {
  Widget today(
    ThemeData t, {
    Widget? home,
    Map<String, Object?> Function(Map<String, Object?>)? mutate,
  }) => todayOn(getStore(), t, home: home, mutate: mutate);
  Widget screen(ThemeData t, Widget home) => today(t, home: pushed(home));

  return <GroupCase>[
    GroupCase(
      name: 'activity',
      route: '/activity',
      data: 'today.json; activity.json (fitness_plan)',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            activitySnapshotProvider.overrideWith(
              (ref) async => snap('activity.json'),
            ),
          ],
          child: const ActivityScreen(),
        ),
      ),
    ),
    GroupCase(
      name: 'fitness',
      route: '/fitness',
      data: 'today.json vo2max block; sampleHistory',
      build: (t) => screen(t, const FitnessScreen()),
    ),
    GroupCase(
      name: 'workouts',
      route: '/workouts',
      data: 'activity.json workouts; today.json strength',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            workoutHistoryProvider.overrideWith(
              (ref) async => sessionsFixture(),
            ),
          ],
          child: pushed(const WorkoutHistoryScreen()),
        ),
      ),
    ),
    GroupCase(
      name: 'workout',
      route: '/workout?start=$kWorkoutStart',
      data: 'workout.json',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            workoutDetailProvider(
              kWorkoutStart,
            ).overrideWith((ref) async => workoutFixture()),
          ],
          child: pushed(const WorkoutDetailScreen(start: kWorkoutStart)),
        ),
      ),
    ),
    GroupCase(
      name: 'gps',
      route: '/gps',
      data:
          'FixedGps (idle recorder, no fixes); no saved recordings on the phone',
      status: 'empty state',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            gpsRepositoryProvider.overrideWith(
              (ref) async => GpsRepository(
                local: GpsLocalStore(getStore(), 'render'),
                api: await idleApi(),
              ),
            ),
            localGpsRecordingsProvider.overrideWith(
              (ref) => Stream.value(const <GpsRecordingRow>[]),
            ),
          ],
          child: pushed(const GpsScreen()),
        ),
      ),
    ),
    GroupCase(
      name: 'routes',
      route: '/routes',
      data: 'gps_list.json',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            recordedRoutesProvider.overrideWith((ref) async => routesFixture()),
          ],
          child: pushed(const RoutesScreen()),
        ),
      ),
    ),
    GroupCase(
      name: 'route',
      route: '/route/<track_id>',
      data: 'gps_detail.json; no basemap tiles (plain ground)',
      build: (t) {
        final route = routeFixture();
        return today(
          t,
          home: ProviderScope(
            overrides: [
              recordedRouteProvider(
                route.id,
              ).overrideWith((ref) async => route),
              basemapStyleProvider.overrideWith((ref) async => null),
            ],
            child: pushed(RouteDetailScreen(id: route.id)),
          ),
        );
      },
    ),
    GroupCase(
      name: 'trends',
      route: '/trends',
      data: 'sampleSeries for every trend spec and period',
      size: const Size(390, 4200),
      build: (t) => ProviderScope(
        overrides: [
          todayProvider.overrideWithValue('2026-07-31'),
          for (final spec in kTrendSpecs)
            for (final period in TrendPeriod.values)
              metricHistoryProvider(
                spec.metric,
                period.fetchDays,
              ).overrideWith((ref) async => sampleSeries(spec.metric.id)),
        ],
        child: MaterialApp(theme: t, home: pushed(const TrendsScreen())),
      ),
    ),
  ];
}
