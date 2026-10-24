/// Look-at-it harness, group A: one picture of every screen in the group, in
/// light Forest and dark espresso Forest, at 390 logical wide and dpr 3.
///
/// **Not a test** (no `_test` suffix). Run by hand:
///
/// ```bash
/// flutter test test/render/render_group_a.dart
/// ```
///
/// PNGs land in `build/renders/ga-<name>-<theme>.png` and a tab-separated
/// `ga-cases.tsv` says what each one drew; the scratchpad script crops them,
/// cuts them into phone-sized parts and writes the manifest. The screens that
/// need no extra data come from `todayHost`; the rest pin their own providers
/// to the committed contract snapshots (`render_group_a_support.dart`).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';

import '../features/_today_host.dart';
import 'render_group_a_movement.dart';
import 'render_group_a_records.dart';
import 'render_group_a_support.dart';
import 'render_group_a_today.dart';
import 'render_support.dart';

const double _dpr = 3;

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

  final File index = File('$renderOutputDirectory/ga-cases.tsv');
  setUpAll(() {
    Directory(renderOutputDirectory).createSync(recursive: true);
    index.writeAsStringSync('');
  });

  for (final theme in groupThemes.entries) {
    final cases = <GroupCase>[
      ...todayCases(() => store),
      ...movementCases(() => store),
      ...recordCases(() => store),
    ];

    for (final c in cases) {
      testWidgets('render ${c.name} — ${theme.key}', (tester) async {
        await shoot(
          tester,
          'ga-${c.name}-${theme.key}',
          c.build(theme.value),
          size: c.size,
          dpr: _dpr,
          beforeShot: c.beforeShot,
        );
        if (theme.key == 'light') {
          index.writeAsStringSync(
            '${c.name}\t${c.route}\t${c.data}\t${c.status}\n',
            mode: FileMode.append,
          );
        }
      });
    }
  }
}
