/// A look-at-it harness for the lever card and the "What moves it" dropdown.
/// **Not a test**: named without the `_test` suffix so `flutter test` never
/// picks it up.
///
/// ```bash
/// flutter test test/render/render_levers.dart
/// ls build/renders/levers-*.png
/// ```
///
/// Each PNG stacks, at logical width 390 and device pixel ratio 3: the lever
/// card on the contract snapshot, the dropdown collapsed and expanded, and the
/// same two with one lever withheld ("Not counted"), in one theme and accent.
/// `levers-large-*` is the same at text scale 1.3.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/features/today/v02/age_levers.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/shared/reveal_once.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';

const double _width = 390;
const double _height = 1900;
const double _pixelRatio = 3;
const double _gutter = 20;
const double _gap = 28;
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

  for (final scale in <double>[1, 1.3]) {
    for (final theme in themes.entries) {
      if (scale != 1 && theme.key != 'light-Forest') continue;
      final name = '${scale == 1 ? 'levers' : 'levers-large'}-${theme.key}';
      testWidgets('render $name', (tester) async {
        tester.view
          ..physicalSize = const Size(_width, _height) * _pixelRatio
          ..devicePixelRatio = _pixelRatio;
        addTearDown(tester.view.reset);
        final snapshot = BioAgeBlock.fromJson(
          loadTodayJson()['biological_age'],
        );
        final withheld = BioAgeBlock.fromJson(
          withheldBioAge(
            absentTerms: <Map<String, Object?>>[staleWeightTerm()],
          ),
        );
        final reveals = RevealRegistry();
        await tester.pumpWidget(
          ProviderScope(
            child: RepaintBoundary(
              key: _boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.value,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => Material(
                    color: context.colors.bg,
                    child: ListView(
                      padding: const EdgeInsets.all(_gutter),
                      children: <Widget>[
                        AgeLeverCard(
                          block: snapshot,
                          reveals: reveals,
                          onOpenLever: (_) {},
                        ),
                        const SizedBox(height: _gap),
                        WhatMovesIt(
                          block: snapshot,
                          reveals: RevealRegistry(),
                          openByDefault: false,
                        ),
                        const SizedBox(height: _gap),
                        WhatMovesIt(
                          block: snapshot,
                          reveals: RevealRegistry(),
                          openByDefault: true,
                          onOpenLever: (_) {},
                        ),
                        const SizedBox(height: _gap),
                        WhatMovesIt(
                          block: withheld,
                          reveals: RevealRegistry(),
                          openByDefault: false,
                        ),
                        const SizedBox(height: _gap),
                        AgeLeverCard(block: withheld, reveals: reveals),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1200));
        await tester.pump(const Duration(milliseconds: 1200));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_boundary),
        );
        final ByteData? png = await tester.runAsync<ByteData?>(() async {
          final image = await boundary.toImage(pixelRatio: _pixelRatio);
          return image.toByteData(format: ui.ImageByteFormat.png);
        });
        if (png == null) fail('no bytes for $name');
        Directory(_outputDirectory).createSync(recursive: true);
        File('$_outputDirectory/$name.png').writeAsBytesSync(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      });
    }
  }
}

/// Registers the app's own fonts under the names `pubspec.yaml` gives them.
Future<void> _loadBundledFonts() async {
  for (final face in <String, String>{
    'Figtree': 'assets/fonts/Figtree.ttf',
    'HealtheeSymbols': 'assets/fonts/InterFallback.ttf',
    'packages/solar_icons/SolarIconsOutline':
        '${_packageRoot('solar_icons')}/fonts/SolarIconsOutline.ttf',
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

/// Where pub put [package], read from the resolved package config.
String _packageRoot(String package) {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, Object?>;
  for (final entry in config['packages']! as List<Object?>) {
    final row = entry! as Map<String, Object?>;
    if (row['name'] == package) {
      return Uri.parse(row['rootUri']! as String).toFilePath();
    }
  }
  fail('$package is not in .dart_tool/package_config.json');
}
