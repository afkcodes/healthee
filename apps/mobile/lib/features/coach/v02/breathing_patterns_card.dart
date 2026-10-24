/// The pattern list on the plan screen: the five presets with their evidence,
/// and the owner's own.
///
/// Only the two slow-breathing presets carry the citation. Box and 4-7-8 are
/// not in the knowledge base and say so; no row makes a health claim of its
/// own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/features/coach/v02/breathing_custom_editor.dart';
import 'package:healthee/features/coach/v02/breathing_format.dart';
import 'package:healthee/shared/v02/surface_panels.dart';
import 'package:solar_icons/solar_icons.dart';

/// One card listing the patterns.
class BreathingPatternsCard extends ConsumerWidget {
  /// Draws the presets and the custom row.
  const BreathingPatternsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(breathingSettingsControllerProvider).value?.custom;
    return SurfaceCard(
      flush: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Column(
          children: <Widget>[
            for (final pattern in kBreathPresets) PatternRow(pattern: pattern),
            if (custom != null) PatternRow(pattern: custom),
            _CustomRow(custom: custom),
          ],
        ),
      ),
    );
  }
}

/// A pattern: name, counts, blurb and evidence. Tapping starts a session.
class PatternRow extends StatelessWidget {
  /// A row for [pattern].
  const PatternRow({required this.pattern, super.key});

  /// The pattern.
  final BreathPattern pattern;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      hint: 'Start a session',
      child: GestureDetector(
        onTap: () => context.push(breathingPlayerLocation(pattern: pattern.id)),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.card,
            vertical: Insets.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      pattern.name,
                      style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
                    ),
                  ),
                  Text(
                    pattern.dotted,
                    style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xs),
              Text(
                pattern.blurb,
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
              const SizedBox(height: Insets.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: EvidenceChip(pattern.evidence),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomRow extends StatelessWidget {
  const _CustomRow({required this.custom});

  final BreathPattern? custom;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: custom == null ? 'Set a custom pattern' : 'Edit custom pattern',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => showBreathingCustomEditor(context, custom),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.card,
              vertical: Insets.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        custom == null ? 'Custom' : 'Edit custom',
                        style: TypeLadder.bodyStrong.copyWith(
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: Insets.xs),
                      Text(
                        'Set your own in, hold and out counts.',
                        style: TypeLadder.callout.copyWith(color: colors.ink2),
                      ),
                    ],
                  ),
                ),
                Icon(
                  custom == null ? Icons.add_rounded : SolarIconsOutline.pen,
                  size: 20,
                  color: colors.ink2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
