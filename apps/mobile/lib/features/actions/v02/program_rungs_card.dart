/// The program's ladder: one numbered row per rung, the current one lit.
///
/// Everything on a row is the rung's own field: its target and metric, its
/// cadence, its status, and its dates when it has been started. A rung that was
/// never started carries no dates and none are guessed.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/shared/format/date_range.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The chip on the current rung.
const String kThisWeek = 'This week';

/// The word on a rung not yet reachable.
const String kLocked = 'locked';

/// The rung card.
class ProgramRungsCard extends StatelessWidget {
  /// Draws [rungs] in order.
  const ProgramRungsCard({required this.rungs, super.key});

  /// The ladder.
  final List<Challenge> rungs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ToneScope(
      tone: Tone.activity,
      child: SurfaceCard(
        child: Column(
          children: <Widget>[
            for (var i = 0; i < rungs.length; i++) ...<Widget>[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.md),
                  child: Divider(
                    height: hairline,
                    thickness: hairline,
                    color: colors.line,
                  ),
                ),
              _RungRow(ordinal: i + 1, rung: rungs[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// `80 min`, `8,900 steps`: the rung's target in its own unit.
String rungHeadline(Challenge rung) {
  final target = rung.target;
  final number = target == target.roundToDouble()
      ? _grouped(target.round())
      : '$target';
  final given = rung.progress?.unit;
  final unit =
      (given != null && given.isNotEmpty ? given : null) ??
      metricUnitWord(rung.metric);
  return '$number $unit';
}

/// Cadence, then the span the rung runs when it has started.
String rungCaption(Challenge rung) {
  final cadence = rung.cadence.isEmpty
      ? ''
      : rung.cadence[0].toUpperCase() + rung.cadence.substring(1);
  final start = rung.adoptedAt;
  if (start == null) {
    return cadence;
  }
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final end = start.add(
    Duration(days: rung.windowDays > 0 ? rung.windowDays - 1 : 0),
  );
  final span = dateRangeLabel(iso(start), iso(end));
  return cadence.isEmpty ? span : '$cadence · $span';
}

String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(digits[i]);
  }
  return out.toString();
}

class _RungRow extends StatelessWidget {
  const _RungRow({required this.ordinal, required this.rung});

  final int ordinal;
  final Challenge rung;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = rung.status == 'active';
    final progress = rung.progress;
    final fraction =
        current && progress?.current != null && progress!.target > 0
        ? (progress.current! / progress.target).clamp(0.0, 1.0)
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Ordinal(ordinal: ordinal, current: current),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                rungHeadline(rung),
                style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
              ),
              Text(
                rungCaption(rung),
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
              if (fraction != null) ...<Widget>[
                const SizedBox(height: Insets.sm),
                _Bar(fraction: fraction),
              ],
            ],
          ),
        ),
        const SizedBox(width: Insets.sm),
        if (current)
          _ThisWeek()
        else
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Text(
              rung.status,
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
          ),
      ],
    );
  }
}

class _Ordinal extends StatelessWidget {
  const _Ordinal({required this.ordinal, required this.current});

  final int ordinal;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: current ? context.family : colors.surface2,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$ordinal',
        style: TypeLadder.callout.copyWith(
          color: current ? (dark ? colors.bg : colors.ink) : colors.ink2,
        ),
      ),
    );
  }
}

class _ThisWeek extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: context.familySoft,
      shape: const StadiumBorder(),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.xs,
      ),
      child: Text(
        kThisWeek,
        style: TypeLadder.caption.copyWith(color: context.family),
      ),
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(Radii.pill),
    child: SizedBox(
      height: 4,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: ColoredBox(color: context.colors.surface2)),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: ColoredBox(color: context.family),
            ),
          ),
        ],
      ),
    ),
  );
}
