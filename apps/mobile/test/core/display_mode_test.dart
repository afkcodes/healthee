/// Opening or closing the app must never change the panel's resolution.
///
/// The `refresh_rate` plugin asked for a display mode by refresh rate alone. On a
/// Pixel 8 Pro set to "High resolution" it picked 1344×2992@120 over the
/// 1008×2244@120 the phone was using, so the panel switched resolution on every
/// open and switched back on every close. That showed up as a flash or a garbled
/// frame (`dumpsys display`: mActiveModeId 3 → 2 → 3). `MainActivity` now asks
/// for the peak rate only among modes at the current physical size.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the refresh_rate plugin is not a dependency', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('refresh_rate')),
    );
  });

  test('MainActivity only picks modes at the current resolution', () {
    final activity = File(
      'android/app/src/main/kotlin/codes/afk/healthee/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('it.physicalWidth == current.physicalWidth'));
    expect(activity, contains('it.physicalHeight == current.physicalHeight'));
    expect(activity, contains('preferredDisplayModeId = peak.modeId'));
  });
}
