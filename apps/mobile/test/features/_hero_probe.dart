/// What the biological-age hero suites share: the real face and real widths.
///
/// ## The real font, because the default one is a square
///
/// `flutter test` renders every glyph in a placeholder font whose characters are
/// all one em wide. In it `34.3` is 336 px wide at 84 px, so any claim about
/// what fits beside the figure would be a claim about the wrong box. Figtree is
/// bundled with the app, so [loadFigtree] measures the figure the owner sees.
///
/// ## Four phone widths, and not one of them is 800
///
/// `flutter test` defaults to an 800 x 600 viewport, which is wider than any
/// phone and hides every width-dependent overflow. This project has already
/// shipped a card that overflowed by 110 px behind exactly that default, so
/// every case pumps a real phone width.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// The widths a phone actually is. See the library docstring.
const List<double> kPhoneWidths = <double>[320, 360, 390, 414];

/// Loads the app's own typeface, so the text boxes measured here are the real
/// ones.
Future<void> loadFigtree() async {
  // ONE file: Figtree is a variable font, so there are no static weights to
  // enumerate. The measurements below are of the real face at its default
  // instance, which is what a test can load.
  final loader = FontLoader('Figtree');
  final bytes = File('assets/fonts/Figtree.ttf').readAsBytesSync();
  loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}
