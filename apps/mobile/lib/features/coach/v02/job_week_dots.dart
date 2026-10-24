/// The seven day dots under the job: one per day, Monday first.
///
/// Every verdict dot is the strap's verdict from the ledger, never a tap.
/// A day with no verdict yet is a ring in the domain colour when it is today,
/// and an empty well when it is still to come (or left no entry).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/review_week.dart';
import 'package:healthee/shared/charts/v02/hatch.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// What one day's dot shows.
enum DotKind {
  /// Met the target.
  done,

  /// Met the floor.
  partial,

  /// Checked and not met.
  missed,

  /// No reading, or the strap cannot see it.
  noProof,

  /// Today, no verdict yet.
  today,

  /// Nothing yet.
  empty,
}

/// One dot per day of the week starting [weekFrom], from [entries] already
/// narrowed to the job. [today] is the owner's ISO day.
List<DotKind> weekDots({
  required String weekFrom,
  required String today,
  required Iterable<LedgerEntry> entries,
}) {
  final start = DateTime.tryParse(weekFrom);
  if (start == null) {
    return List<DotKind>.filled(7, DotKind.empty);
  }
  final verdicts = <String, LedgerVerdict>{
    for (final entry in entries) entry.date: entry.verdict,
  };
  return <DotKind>[
    for (var i = 0; i < 7; i++)
      _kind(
        verdicts[isoDay(DateTime(start.year, start.month, start.day + i))],
        isoDay(DateTime(start.year, start.month, start.day + i)) == today,
      ),
  ];
}

DotKind _kind(LedgerVerdict? verdict, bool isToday) => switch (verdict) {
  LedgerVerdict.done => DotKind.done,
  LedgerVerdict.partial => DotKind.partial,
  LedgerVerdict.missed => DotKind.missed,
  LedgerVerdict.noData || LedgerVerdict.uncheckable => DotKind.noProof,
  null => isToday ? DotKind.today : DotKind.empty,
};

/// The row of seven.
class JobWeekDots extends StatelessWidget {
  /// Draws [kinds], seven of them, Monday first.
  const JobWeekDots({required this.kinds, required this.todayIndex, super.key});

  /// Largest dot diameter; narrower rows shrink the dots, not the row.
  static const double size = 40;

  /// The dots.
  final List<DotKind> kinds;

  /// Which one is today, or -1.
  final int todayIndex;

  static const List<String> _letters = <String>[
    'M', 'T', 'W', 'T', 'F', 'S', 'S', //
  ];
  static const List<String> _names = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday', //
  ];

  static String _meaning(DotKind kind) => switch (kind) {
    DotKind.done => 'done',
    DotKind.partial => 'half done',
    DotKind.missed => 'missed',
    DotKind.noProof => 'no reading',
    DotKind.today => 'today',
    DotKind.empty => 'not yet',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final dot = ((box.maxWidth - 6 * Insets.xs) / 7).clamp(24.0, size);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (var i = 0; i < 7; i++)
              Semantics(
                label: '${_names[i]}: ${_meaning(kinds[i])}',
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DayDot(kind: kinds[i], size: dot),
                      const SizedBox(height: Insets.xs),
                      Text(
                        _letters[i],
                        style:
                            (i == todayIndex
                                    ? TypeLadder.calloutStrong
                                    : TypeLadder.callout)
                                .copyWith(
                                  color: i == todayIndex
                                      ? colors.ink
                                      : colors.ink2,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One dot.
class DayDot extends StatelessWidget {
  /// Draws [kind].
  const DayDot({required this.kind, this.size = JobWeekDots.size, super.key});

  /// What it shows.
  final DotKind kind;

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final watch = ReadingState.watch.colourIn(colors);
    return SizedBox(
      width: size,
      height: size,
      child: switch (kind) {
        DotKind.done => _Disc(
          state: ReadingState.better,
          glyph: Icons.check_rounded,
          size: size,
        ),
        DotKind.missed => _Disc(
          state: ReadingState.worse,
          glyph: Icons.close_rounded,
          size: size,
        ),
        DotKind.partial => CustomPaint(
          painter: _HalfPainter(well: colors.surface2, fill: watch),
        ),
        DotKind.noProof => CustomPaint(
          painter: _HatchDiscPainter(well: colors.surface2, ink: colors.ink3),
          child: Center(
            child: Text(
              '?',
              style: TypeLadder.headline.copyWith(color: colors.ink2),
            ),
          ),
        ),
        DotKind.today => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: context.family, width: 2),
          ),
        ),
        DotKind.empty => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface2,
          ),
        ),
      },
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.state, required this.glyph, required this.size});

  final ReadingState state;
  final IconData glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state.colourIn(colors),
      ),
      child: Center(
        child: Icon(glyph, size: size * 0.55, color: colors.bg),
      ),
    );
  }
}

class _HalfPainter extends CustomPainter {
  const _HalfPainter({required this.well, required this.fill});

  final Color well;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Offset.zero & size;
    canvas
      ..drawOval(circle, Paint()..color = well)
      ..save()
      ..clipRect(Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2))
      ..drawOval(circle, Paint()..color = fill)
      ..restore();
  }

  @override
  bool shouldRepaint(_HalfPainter old) => old.well != well || old.fill != fill;
}

class _HatchDiscPainter extends CustomPainter {
  const _HatchDiscPainter({required this.well, required this.ink});

  final Color well;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(Offset.zero & size, Paint()..color = well);
    paintHatch(canvas, Offset.zero & size, ink: ink, radius: size.width / 2);
  }

  @override
  bool shouldRepaint(_HatchDiscPainter old) =>
      old.well != well || old.ink != ink;
}
