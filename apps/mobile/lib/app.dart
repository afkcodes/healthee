/// The root widget: theme, router, nothing else.
///
/// Separate from `main.dart` so tests can pump the app without going through
/// `runApp` — a widget test builds [HealtheeApp] directly inside its own
/// `ProviderScope` and can override any provider on the way in.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/theme_controller.dart';
import 'package:healthee/data/notifications/notification_providers.dart';

/// The Healthee app.
class HealtheeApp extends ConsumerStatefulWidget {
  /// Builds the app.
  const HealtheeApp({super.key});

  @override
  ConsumerState<HealtheeApp> createState() => _HealtheeAppState();
}

class _HealtheeAppState extends ConsumerState<HealtheeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notificationLifecycleProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  // Built once and held: a GoRouter rebuilt on every frame loses its navigation
  // stack, which shows up as the back button doing nothing.
  late final GoRouter _router = buildRouter(ref);

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      ref.listen(notificationDestinationProvider, (previous, next) {
        next.whenData(
          (destination) =>
              unawaited(_router.push(notificationRoute(destination))),
        );
      });
      ref.watch(notificationLifecycleProvider);
    }
    return MaterialApp.router(
      title: 'Healthee',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.customized(
        Brightness.light,
        ref.watch(appearanceControllerProvider),
      ),
      darkTheme: AppTheme.customized(
        Brightness.dark,
        ref.watch(appearanceControllerProvider),
      ),
      themeMode: ref.watch(themeControllerProvider),
      routerConfig: _router,
    );
  }
}
