/// `.icon-tile` — now a bare 24 px glyph, no tile.
///
/// **The owner's brief removed the container.** The prototype drew a 40 px
/// rounded square in `--surface-soft` with the icon in the family colour. An
/// icon is not a reading and not interactive by itself, so it is drawn bare, in
/// ink2, with nothing behind it: no tile, no circle, no tint. The family hue is
/// for data marks only.
///
/// The widget keeps its name and constructors so no call site changes, and
/// `chrome` no longer changes the colour (both variants are ink2). The box is
/// transparent and exists only so a row's leading edge stays a fixed width.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';

/// One bare icon, ink2, 24 px.
class IconTile extends StatelessWidget {
  /// Builds the glyph around [icon].
  const IconTile(
    this.icon, {
    this.iconSize = defaultIconSize,
    this.boxSize = size,
    super.key,
  }) : chrome = false;

  /// The same glyph for APP CHROME (a settings row). Identical to the default:
  /// kept so call sites that name the intent still read.
  const IconTile.chrome(
    this.icon, {
    this.iconSize = defaultIconSize,
    this.boxSize = size,
    super.key,
  }) : chrome = true;

  /// The leading box, equal to the glyph so the icon sits flush.
  static const double size = 24;

  /// The box on a compact row. The same as [size]: the glyph is the box.
  static const double compactSize = 24;

  /// A navigation or row-leading icon is 24 px.
  static const double defaultIconSize = 24;

  /// The glyph.
  final IconData icon;

  /// Its size. An inline icon beside text passes 16.
  final double iconSize;

  /// Whether this is chrome. Paints identically; recorded for the call site.
  final bool chrome;

  /// The leading box width and height.
  final double boxSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Center(
        child: Icon(icon, size: iconSize, color: context.colors.ink2),
      ),
    );
  }
}
