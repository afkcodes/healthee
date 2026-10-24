/// A look-at-it harness for the biological-age sphere alone.
///
/// **Not a test** (no `_test` suffix): run by hand with
/// `flutter test test/render/render_sphere.dart`, then read `build/renders/`.
/// It asserts nothing; the point is to look at the PNGs at 3x, where dot
/// crispness, banding and clumping are visible.
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
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';

/// A phone's logical width; the height is the sphere plus margin.
const Size _renderSize = Size(390, 420);

/// Pixels per logical pixel, as on a current phone.
const double _dpr = 3;

/// The sphere's canvas on the detail screen.
const double _canvas = 330;

/// Half the painted width of "34.3" at Display, in px, as the hero measures it.
const double _clearHalfWidth = 62;

/// Gap between the number and the verdict.
const double _gap = 8;

/// Where the PNGs land. Ignored by git.
const String _outputDirectory = 'build/renders';

/// The accent indices rendered: Forest and Indigo.
const int _forest = 0, _indigo = 4;

const Key _boundary = Key('sphere-boundary');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadBundledFonts);

  final cases = <String, (ThemeData, bool)>{
    'light-forest': (_theme(Brightness.light, _forest, null), false),
    'espresso-forest': (
      _theme(Brightness.dark, _forest, BackgroundVariant.espresso),
      false,
    ),
    'amoled-forest': (
      _theme(Brightness.dark, _forest, BackgroundVariant.amoled),
      false,
    ),
    'light-indigo': (_theme(Brightness.light, _indigo, null), false),
    'espresso-indigo': (
      _theme(Brightness.dark, _indigo, BackgroundVariant.espresso),
      false,
    ),
    'amoled-indigo': (
      _theme(Brightness.dark, _indigo, BackgroundVariant.amoled),
      false,
    ),
    'withheld-espresso-forest': (
      _theme(Brightness.dark, _forest, BackgroundVariant.espresso),
      true,
    ),
  };
  for (final entry in cases.entries) {
    testWidgets('render sphere ${entry.key}', (tester) async {
      await _shoot(
        tester,
        'sphere-${entry.key}',
        entry.value.$1,
        entry.value.$2,
      );
    });
  }
}

ThemeData _theme(Brightness b, int accent, BackgroundVariant? background) =>
    AppTheme.customized(
      b,
      AppearanceVariant(
        accent: accent,
        background: background ?? BackgroundVariant.espresso,
      ),
    );

Future<void> _shoot(
  WidgetTester tester,
  String name,
  ThemeData theme,
  bool withheld,
) async {
  tester.view
    ..physicalSize = _renderSize * _dpr
    ..devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: RepaintBoundary(
        key: _boundary,
        child: Scaffold(
          body: Center(
            child: AgeSphere(
              canvas: _canvas,
              withheld: withheld,
              clearHalfWidth: _clearHalfWidth,
              centre: withheld ? const SizedBox.shrink() : const _Centre(),
            ),
          ),
        ),
      ),
    ),
  );
  // The sphere turns forever, so settling never ends: pump past the 950 ms
  // entry instead.
  await tester.pump(const Duration(milliseconds: 1200));

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  final ByteData? png = await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: _dpr);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  if (png == null) fail('the render produced no bytes for $name');
  Directory(_outputDirectory).createSync(recursive: true);
  File('$_outputDirectory/$name.png').writeAsBytesSync(
    png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
  );
}

/// The hero's centre: the number, a gap, the verdict.
class _Centre extends StatelessWidget {
  const _Centre();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('34.3', style: TypeLadder.display.copyWith(color: colors.ink)),
        const SizedBox(height: _gap),
        Text(
          '1.7 years younger',
          style: TypeLadder.bodyStrong.copyWith(color: colors.fav),
        ),
      ],
    );
  }
}

/// The bundled faces and the family each is declared under in `pubspec.yaml`.
///
/// `render_screens.dart` derives the family from the file name, which for
/// `Figtree.ttf` yields `Figtree.ttf`; here the pubspec's own mapping is used so
/// the glyph widths are the app's.
const Map<String, String> _faces = <String, String>{
  'assets/fonts/Figtree.ttf': 'Figtree',
  'assets/fonts/InterFallback.ttf': 'HealtheeSymbols',
};

/// Registers the bundled faces with the test engine so widths are real.
Future<void> _loadBundledFonts() async {
  for (final MapEntry<String, String> face in _faces.entries) {
    final File file = File(face.key);
    if (!file.existsSync()) fail('missing font ${face.key}');
    final FontLoader loader = FontLoader(face.value)
      ..addFont(
        Future<ByteData>.value(file.readAsBytesSync().buffer.asByteData()),
      );
    await loader.load();
  }
}
