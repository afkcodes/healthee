/// The small pieces the biological-age screen is assembled from: the nav row,
/// the line under the title, and the "How this is calculated" row.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:solar_icons/solar_icons.dart';

/// The line under the title, before the receipt.
const String kAgeEstimateLine = 'Estimate, not a clinical age';

/// The footnote at the foot of the screen.
const String kAgeFootnote =
    'Built from population research. A difference of a few years is within '
    'its noise.';

/// The row that opens the calculation.
const String kAgeCalculationRow = 'How this is calculated';

/// A nav glyph's size, logical px.
const double kAgeNavIcon = 24;

/// A nav control's touch target, logical px.
const double kAgeNavTarget = 48;

/// The row's chevron, logical px.
const double kAgeRowChevron = 16;

/// `Estimate, not a clinical age · Updated today`, or the first part alone when
/// the server sent no receipt (or one that is not a time).
String ageUpdatedLine(String? derivedAt, DateTime now) {
  final at = derivedAt == null ? null : DateTime.tryParse(derivedAt);
  return at == null
      ? kAgeEstimateLine
      : '$kAgeEstimateLine · ${updatedLabel(at, now: now)}';
}

/// Back at the left, info at the right, both 24 px in `ink2`.
class AgeNavRow extends StatelessWidget {
  const AgeNavRow({required this.onBack, required this.onInfo, super.key});

  /// Null draws no back control: a screen with nothing beneath it.
  final VoidCallback? onBack;

  /// Opens the explainer.
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The glyph, not its touch target, lines up with the page's gutter: the row
    // is laid out a target's overhang wider than the page and moved back.
    const overhang = (kAgeNavTarget - kAgeNavIcon) / 2;
    Widget control(IconData icon, String label, VoidCallback tap) => HTap(
      onTap: tap,
      semanticLabel: label,
      child: SizedBox(
        width: kAgeNavTarget,
        height: kAgeNavTarget,
        child: Icon(icon, size: kAgeNavIcon, color: colors.ink2),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => Transform.translate(
        offset: const Offset(-overhang, 0),
        child: SizedBox(
          width: box.maxWidth + 2 * overhang,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              if (onBack case final VoidCallback back)
                control(SolarIconsOutline.altArrowLeft, 'Go back', back)
              else
                const SizedBox(width: kAgeNavTarget, height: kAgeNavTarget),
              control(
                SolarIconsOutline.infoCircle,
                'What biological age means, and what backs it',
                onInfo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-row card: [label] and a chevron, the whole row a button.
class AgeCalculationCard extends StatelessWidget {
  const AgeCalculationCard({required this.onTap, super.key});

  /// Opens the sheet.
  final VoidCallback onTap;

  /// The row's minimum height, logical px.
  static const double minHeight = 48;

  /// The card's corner radius, logical px.
  static const double radius = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: kAgeCalculationRow,
      excludeSemantics: true,
      onTap: onTap,
      child: HTap(
        onTap: onTap,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.surface,
            shape: hSquircle(radius),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.card,
                vertical: Insets.lg,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      kAgeCalculationRow,
                      style: TypeLadder.body.copyWith(color: colors.ink),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  Icon(
                    SolarIconsOutline.altArrowRight,
                    size: kAgeRowChevron,
                    color: colors.ink2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
