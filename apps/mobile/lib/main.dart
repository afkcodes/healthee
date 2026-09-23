/// Entry point. Wiring only — everything else lives where it belongs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/app.dart';
import 'package:healthee/core/licences.dart';
import 'package:healthee/core/provider_logger.dart';
import 'package:healthee/data/api/provider_retry.dart';
import 'package:healthee/data/sync/device_lease.dart';

void main() {
  // The peak refresh rate is requested natively in `MainActivity.kt`, at the
  // display's current resolution. (The `refresh_rate` plugin that used to do it
  // here switched the panel's resolution on every open and close.)
  //
  // The vendored font's SIL OFL notice, added to Flutter's own licence registry
  // so `showLicensePage` can find it. Registration is lazy — the stream is not
  // run until somebody opens the page — so this costs nothing at start-up, and
  // it has to happen before `runApp` because the registry is read from there on.
  registerAssetLicences();
  // Only this isolate runs `main()`; WorkManager's starts at its own entry
  // point. Stamping the strap lease lets the NEXT UI isolate in this process
  // (after Back, then reopen) reclaim a lease this one never got to release.
  DeviceLease.markUiIsolate();
  // The ProviderScope is the app's whole dependency graph. riverpod_lint's
  // `missing_provider_scope` fails the build if this is ever dropped.
  runApp(
    const ProviderScope(
      retry: apiProviderRetry,
      // Every provider failure reaches the one logging path from here, so no
      // repository has to remember to log its own.
      observers: [ProviderLogger()],
      child: HealtheeApp(),
    ),
  );
}
