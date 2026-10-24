/// A look-at-it harness for the biological-age ruler. **Not a test**: it is
/// named without the `_test` suffix so `flutter test` never picks it up.
///
/// ```bash
/// flutter test test/render/render_ruler.dart
/// ls build/renders/ruler-*.png
/// ```
///
/// Each PNG stacks the four cases (younger, older, about your age, outside the
/// base scale) at logical width 390 and device pixel ratio 3, in one theme and
/// accent, with the app's own fonts.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/v02/instruments/age_ruler.dart';

/// A phone's logical width.
const double _width = 390;

/// The pixel ratio the renders are made at.
const double _pixelRatio = 3;

/// The page's side margin around each ruler.
const double _gutter = 20;

/// Space under each ruler.
const double _rowGap = 28;

/// The four cases: estimate, actual.
const List<(double, double)> _cases = <(double, double)>[
  (34.3, 36),
  (38.1, 36),
  (36.2, 36),
  (27, 36),
];

const String _outputDirectory = 'build/renders';
const Key _boundary = Key('render-boundary');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadBundledFonts);

  final themes = <String, ThemeData>{
    for (final accent in <int>[0, 4])
      for (final entry in <(String, Brightness, BackgroundVariant)>[
        ('light', Brightness.light, BackgroundVariant.espresso),
        ('espresso', Brightness.dark, BackgroundVariant.espresso),
        ('amoled', Brightness.dark, BackgroundVariant.amoled),
      ])
        '${entry.$1}-${AppearanceVariant.accentNames[accent]}':
            AppTheme.customized(
              entry.$2,
              AppearanceVariant(accent: accent, background: entry.$3),
            ),
  };

  for (final theme in themes.entries) {
    testWidgets('render ruler - ${theme.key}', (tester) async {
      const rowHeight = AgeRuler.height + _rowGap;
      tester.view
        ..physicalSize =
            Size(_width, _cases.length * rowHeight + 2 * _gutter) * _pixelRatio
        ..devicePixelRatio = _pixelRatio;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.value,
            home: Builder(
              builder: (context) => Material(
                color: context.colors.bg,
                child: ListView(
                  padding: const EdgeInsets.all(_gutter),
                  children: <Widget>[
                    for (final c in _cases)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _rowGap),
                        child: AgeRuler(estimate: c.$1, actual: c.$2),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_boundary),
      );
      final ByteData? png = await tester.runAsync<ByteData?>(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: _pixelRatio);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      if (png == null) fail('no bytes for ${theme.key}');
      Directory(_outputDirectory).createSync(recursive: true);
      File('$_outputDirectory/ruler-${theme.key}.png').writeAsBytesSync(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    });
  }
}

/// Registers the app's own fonts under the names `pubspec.yaml` gives them.
Future<void> _loadBundledFonts() async {
  for (final face in <String, String>{
    'Figtree': 'assets/fonts/Figtree.ttf',
    'HealtheeSymbols': 'assets/fonts/InterFallback.ttf',
  }.entries) {
    final file = File(face.value);
    if (!file.existsSync()) {
      fail('${face.value} is missing - the render would use a fallback face');
    }
    final loader = FontLoader(face.key)
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    await loader.load();
  }
}
