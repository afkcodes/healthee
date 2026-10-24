/// Look-at-it renders of the coach, settings, profile and setup screens, both
/// themes, for comparison with the design prototype. **Not a test.**
///
/// ```bash
/// flutter test test/render/render_group_b.dart
/// ```
///
/// Every screen is drawn at 390 logical wide and 3 device pixels per logical
/// one, in a viewport taller than the screen so the whole scroll lands in one
/// PNG (the trailing empty ground is trimmed afterwards by the cutting script).
/// Themes are light Forest and dark espresso Forest, built the way `app.dart`
/// builds them. Output goes to `$RENDER_B_OUT` (default `build/renders/b`) as
/// `<prototype-name>-<light|dark>.png`. Fonts, sample data and the pumping rules
/// are `render_support.dart`'s and `render_group_b_hosts.dart`'s.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/profile_field.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/coach/coach_history_screen.dart';
import 'package:healthee/features/coach/coach_screen.dart';
import 'package:healthee/features/diagnostics/diagnostics_screen.dart';
import 'package:healthee/features/pairing/pairing_screen.dart';
import 'package:healthee/features/profile/profile_screen.dart';
import 'package:healthee/features/settings/about_screen.dart';
import 'package:healthee/features/settings/appearance_screen.dart';
import 'package:healthee/features/settings/background_screen.dart';
import 'package:healthee/features/settings/data_freshness_screen.dart';
import 'package:healthee/features/settings/device_screen.dart';
import 'package:healthee/features/settings/reminders_screen.dart';
import 'package:healthee/features/settings/settings_screen.dart';
import 'package:healthee/features/signin/server_signin_screen.dart';
import 'package:healthee/features/welcome/welcome_screen.dart';

import '../features/_coach_overrides.dart' show sendButton;
import '../features/_today_host.dart' show now, seedDevice, todayHost;
import 'render_group_b_hosts.dart';
import 'render_support.dart';

const double _dpr = 3;
const Size _phone = Size(390, 844);
const Size _tall = Size(390, 4200);
final DateTime _coachNow = DateTime(2026, 8, 5, 9);
const String _question = 'How did I sleep this week?';

/// One screen to draw: its prototype [name], how to build it for a [theme], and
/// what to do (type, tap) before the picture.
class _Case {
  const _Case(this.name, this.build, {this.size = _tall, this.act});

  final String name;
  final Widget Function(ThemeData theme, LocalStore store) build;
  final Size size;
  final Future<void> Function(WidgetTester tester)? act;
}

Widget _settings(ThemeData t, LocalStore s, Widget screen) =>
    settingsHost(s, t, screen);

Widget _coach(ThemeData t, CoachClient client) =>
    coachHost(t, CoachScreen(now: _coachNow), client: client);

Future<void> _ask(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), _question);
  await tester.tap(sendButton);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _findStraps(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'owner@example.test');
  await tester.enterText(find.byType(TextField).last, 'sample-password');
  await tester.tap(find.text('Find my straps'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final List<_Case> _cases = <_Case>[
  _Case(
    'coach-start',
    (t, s) => _coach(t, ScriptedCoach(balance: entitlementWith())),
    size: _phone,
  ),
  _Case(
    'coach-working',
    (t, s) => _coach(
      t,
      ScriptedCoach(balance: entitlementWith(used: 3), hangs: true),
    ),
    size: _phone,
    act: _ask,
  ),
  _Case(
    'coach',
    (t, s) => _coach(
      t,
      ScriptedCoach(
        balance: entitlementWith(used: 3),
        answer: snapshotAnswer(),
      ),
    ),
    size: const Size(390, 1400),
    act: _ask,
  ),
  _Case(
    'coach-problem',
    (t, s) => _coach(
      t,
      ScriptedCoach(
        balance: entitlementWith(
          used: 20,
          resetsAt: _coachNow.add(const Duration(hours: 30)),
        ),
      ),
    ),
    size: _phone,
  ),
  _Case(
    'coach-problem-unreachable',
    (t, s) => _coach(
      t,
      ScriptedCoach(
        balance: entitlementWith(used: 3),
        failure: const CoachUnreachable(
          "Couldn't reach your server. Nothing was spent.",
          CoachCharge.notCharged,
        ),
      ),
    ),
    size: _phone,
    act: _ask,
  ),
  _Case(
    'coach-history',
    (t, s) => coachHost(
      t,
      const CoachHistoryScreen(),
      client: ScriptedCoach(balance: entitlementWith()),
      threads: sampleThreads(),
    ),
    size: _phone,
  ),
  _Case('settings', (t, s) => _settings(t, s, const SettingsScreen())),
  _Case(
    'settings-appearance',
    (t, s) => _settings(t, s, const AppearanceScreen()),
  ),
  _Case(
    'settings-reminders',
    (t, s) => _settings(t, s, const RemindersScreen()),
  ),
  _Case(
    'settings-background',
    (t, s) => _settings(t, s, const BackgroundScreen()),
  ),
  _Case('settings-device', (t, s) => _settings(t, s, const DeviceScreen())),
  _Case(
    'settings-sync',
    (t, s) => _settings(t, s, const DataFreshnessScreen()),
  ),
  _Case('settings-about', (t, s) => _settings(t, s, const AboutScreen())),
  _Case(
    'diagnostics',
    (t, s) => todayHost(
      s,
      themeOverride: t,
      home: DiagnosticsScreen(now: now),
    ),
  ),
  _Case('profile', (t, s) => _settings(t, s, const ProfileScreen())),
  _Case(
    'profile-weight',
    (t, s) => _settings(t, s, const ProfileScreen(focus: ProfileField.weight)),
  ),
  _Case('welcome', (t, s) => _settings(t, s, const WelcomeScreen())),
  _Case('pairing', (t, s) => setupHost(t, PairingScreen(onDone: () {}))),
  _Case(
    'pairing-found',
    (t, s) => setupHost(t, PairingScreen(onDone: () {})),
    act: _findStraps,
  ),
  _Case('server', (t, s) => setupHost(t, ServerSignInScreen(onDone: () {}))),
  _Case(
    'server-account',
    (t, s) => setupHost(t, ServerSignInScreen(onDone: () {}), identity: true),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetsApp.debugAllowBannerOverride = false;
  setUpAll(loadBundledFonts);

  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  final out = Platform.environment['RENDER_B_OUT'] ?? 'build/renders/b';
  final themes = <String, ThemeData>{
    'light': AppTheme.customized(Brightness.light, const AppearanceVariant()),
    'dark': AppTheme.customized(Brightness.dark, const AppearanceVariant()),
  };
  for (final c in _cases) {
    for (final theme in themes.entries) {
      final name = '${c.name}-${theme.key}';
      testWidgets('render $name', (tester) async {
        await shoot(
          tester,
          'groupb-$name',
          c.build(theme.value, store),
          size: c.size,
          dpr: _dpr,
          beforeShot: c.act,
        );
        Directory(out).createSync(recursive: true);
        File(
          '$renderOutputDirectory/groupb-$name.png',
        ).copySync('$out/$name.png');
      });
    }
  }
}
