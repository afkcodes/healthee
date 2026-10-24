/// The water card alone at dpr 3, 390 wide, light and dark. **Not a test**:
/// run by hand with `flutter test test/render/render_water.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';

import '../features/coach/water_fakes.dart';
import 'render_support.dart';

const Size _frame = Size(390, 260);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetsApp.debugAllowBannerOverride = false;
  setUpAll(loadBundledFonts);

  final cases = <String, (Brightness, double, int)>{
    'water-light': (Brightness.light, 1, 3),
    'water-dark': (Brightness.dark, 1, 3),
    'water-light-text13': (Brightness.light, 1.3, 3),
    'water-light-over': (Brightness.light, 1, 10),
  };
  for (final c in cases.entries) {
    testWidgets('render ${c.key}', (tester) async {
      final store = LocalStore.memory();
      addTearDown(store.close);
      final times = <(int, int)>[(9, 10), (11, 40), (13, 5)];
      final server = FakeWaterServer([
        for (var i = 0; i < c.value.$3; i++)
          waterEntry(
            'e$i',
            i < 3 ? times[i].$1 : 6 + i,
            i < 3 ? times[i].$2 : 0,
          ),
      ]);
      await shoot(
        tester,
        c.key,
        waterHost(server, store, brightness: c.value.$1, textScale: c.value.$2),
        size: c.value.$2 > 1 ? const Size(390, 400) : _frame,
        dpr: 3,
      );
    });
  }
}
