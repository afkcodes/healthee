/// What the render harnesses share: the shot, and the app's real fonts.
///
/// **Not a test.** `render_screens.dart` and `render_today_cases.dart` both
/// take their pictures here, so the boundary, the dpr and the font loading
/// cannot differ between them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone's width, and enough height that nothing is left unbuilt.
const Size renderSize = Size(390, 3400);

/// Where the PNGs land. Ignored by git: this is a look, not an artefact.
const String renderOutputDirectory = 'build/renders';

/// Pumps [app] at [size] and writes `<name>.png`, at [dpr] device pixels per
/// logical one (1 unless a render asks for more). [beforeShot] runs once the
/// screen has settled, for a tap that opens something before the picture.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget app, {
  Size size = renderSize,
  double dpr = 1,
  Future<void> Function(WidgetTester tester)? beforeShot,
}) async {
  tester.view
    ..physicalSize = size * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RepaintBoundary(key: _boundary, child: app));
  // Charts animate on a real ticker. Pump past every reveal for a fixed time
  // rather than settle: one screen's ticker never idles.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await beforeShot?.call(tester);

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  // Real work, so it runs on the real clock: inside the test's fake async
  // zone `toImage` never completes and the render hangs until the timeout.
  final ByteData? png = await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: dpr);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  if (png == null) {
    fail('the render produced no bytes for $name');
  }
  final Directory directory = Directory(renderOutputDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File('$renderOutputDirectory/$name.png').writeAsBytesSync(
    png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
  );
}

const Key _boundary = Key('render-boundary');

/// Registers the app's fonts with the test engine, under the names the app
/// asks for, so widths are the real ones and icons are icons: the two bundled
/// families `pubspec.yaml` declares, the `solar_icons` package's three (a
/// package font is asked for as `packages/<name>/<family>`), and Material's.
Future<void> loadBundledFonts() async {
  final String solar = _packageRoot('solar_icons');
  final String flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  for (final MapEntry<String, String> face in <String, String>{
    'Figtree': 'assets/fonts/Figtree.ttf',
    'HealtheeSymbols': 'assets/fonts/InterFallback.ttf',
    for (final String style in <String>['Bold', 'Broken', 'Outline'])
      'packages/solar_icons/SolarIcons$style':
          '$solar/fonts/SolarIcons$style.ttf',
    'MaterialIcons':
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final File file = File(face.value);
    if (!file.existsSync()) {
      fail(
        '${face.value} is missing — the render would measure a fallback face',
      );
    }
    final FontLoader loader = FontLoader(face.key)
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    await loader.load();
  }
}

/// Where pub put [package], read from the resolved package config.
String _packageRoot(String package) {
  final Map<String, Object?> config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, Object?>;
  for (final Object? entry in config['packages']! as List<Object?>) {
    final Map<String, Object?> row = entry! as Map<String, Object?>;
    if (row['name'] == package) {
      return Uri.parse(row['rootUri']! as String).toFilePath();
    }
  }
  fail(
    '$package is not in .dart_tool/package_config.json; run flutter pub get',
  );
}
