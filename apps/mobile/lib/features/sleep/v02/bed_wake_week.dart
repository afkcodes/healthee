/// `Bed and wake times` — the week as one bar per night, from falling asleep
/// to waking (`design/mobile-preview/proposal.js::timingCard`).
///
/// The figure is the spread between the earliest and latest bedtime of the
/// measured nights: the one number that says whether the week was regular.
/// Bars that line up are a regular week; the chart says so in words under it.
/// A night with no session draws `no data` in its slot rather than a gap the
/// eye closes.
///
/// The scale is 18:00-origin (`hoursFrom6pm`), so a bedtime either side of
/// midnight stays one run. It shows 21:00 to 10:00 unless a night falls
/// outside that, when it widens to fit.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// The sentence under the bars, `proposal.js`'s own.
const String kBedWakeLine =
    'Each bar runs from when you fell asleep to when you woke. Bars that line '
    'up mean a regular week.';

/// One night on the chart: the day's initials and, when measured, its span.
typedef BedWake = ({String day, double? bed, double? wake});

/// The last seven nights, oldest first, on the 18:00 scale. A bedtime before
/// 18:00 would land at the far end of the scale, after its own wake; it is
/// moved one day back instead, so the bar runs upward past the scale's origin.
List<BedWake> bedWakeWeek(List<SleepNight> recent) => <BedWake>[
  for (final night in recent.take(7).toList().reversed) _bedWake(night),
];

BedWake _bedWake(SleepNight night) {
  final start = night.start;
  final end = night.end;
  if (start == null || end == null) {
    return (day: weekdayInitials(night.date), bed: null, wake: null);
  }
  final bed = hoursFrom6pm(start);
  final wake = hoursFrom6pm(end);
  return (
    day: weekdayInitials(night.date),
    bed: bed > wake ? bed - 24 : bed,
    wake: wake,
  );
}

/// The card.
class BedWakeWeekPanel extends StatelessWidget {
  /// [nights] is [bedWakeWeek]'s.
  const BedWakeWeekPanel({
    required this.nights,
    required this.reveals,
    super.key,
  });

  static const String title = 'Bed and wake times';
  static const double chartHeight = 150;

  final List<BedWake> nights;
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final beds = <double>[
      for (final n in nights)
        if (n.bed != null && n.wake != null) n.bed!,
    ];
    final spread = beds.length < 2
        ? null
        : beds.reduce((a, b) => a > b ? a : b) -
              beds.reduce((a, b) => a < b ? a : b);
    return Panel(
      tone: Tone.sleep,
      label: title,
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.clockCircle,
        infoKey: 'sleep_consistency',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            spread == null ? '—' : durationText((spread * 60).round()),
            context_: 'between your earliest and latest bedtime',
          ),
          RevealOnce(
            id: 'sleep.bedwake',
            registry: reveals,
            builder: (context, t) => Semantics(
              label: _spoken(),
              image: true,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: chartHeight,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _BedWakePainter(
                      nights: nights,
                      progress: t,
                      colors: context.colors,
                      family: context.family,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const PanelNote(kBedWakeLine),
        ],
      ),
    );
  }

  String _spoken() => <String>[
    for (final n in nights)
      n.bed == null || n.wake == null
          ? '${n.day}: no data'
          : '${n.day}: ${_clock(n.bed!)} to ${_clock(n.wake!)}',
  ].join('. ');
}

/// 18:00-origin hours to a 24-hour clock.
String _clock(double hours) {
  final minutes = ((hours + 18) * 60).round() % (24 * 60);
  return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

class _BedWakePainter extends CustomPainter {
  _BedWakePainter({
    required this.nights,
    required this.progress,
    required this.colors,
    required this.family,
  });

  final List<BedWake> nights;
  final double progress;
  final HealtheeColors colors;
  final Color family;

  static const double gutter = 40;
  static const double top = 18;
  static const double bottomPad = 34;
  static const double barWidth = 14;

  @override
  void paint(Canvas canvas, Size size) {
    var first = 3.0; // 21:00
    var last = 16.0; // 10:00
    for (final n in nights) {
      if (n.bed != null && n.wake != null) {
        first = first < n.bed! - 0.5 ? first : n.bed! - 0.5;
        last = last > n.wake! + 0.5 ? last : n.wake! + 0.5;
      }
    }
    final right = size.width - gutter;
    final bottom = size.height - bottomPad;
    double y(double h) => top + (h - first) / (last - first) * (bottom - top);
    final grid = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    for (final h in <double>[first, (first + last) / 2, last]) {
      final at = h.roundToDouble();
      canvas.drawLine(Offset(0, y(at)), Offset(right, y(at)), grid);
      _text(canvas, _clock(at), Offset(size.width, y(at)), align: 1);
    }
    final slot = right / (nights.isEmpty ? 1 : nights.length);
    for (var i = 0; i < nights.length; i++) {
      final n = nights[i];
      final cx = slot * (i + 0.5);
      _text(canvas, n.day, Offset(cx, size.height - 6));
      if (n.bed == null || n.wake == null) {
        _text(canvas, 'no data', Offset(cx, bottom - 6), ink: colors.ink2);
        continue;
      }
      final wake = n.bed! + (n.wake! - n.bed!) * progress.clamp(0, 1);
      canvas.drawRRect(
        RRect.fromLTRBR(
          cx - barWidth / 2,
          y(n.bed!),
          cx + barWidth / 2,
          y(wake),
          const Radius.circular(barWidth / 2),
        ),
        Paint()..color = family,
      );
      _text(canvas, _clock(n.bed!), Offset(cx, y(n.bed!) - 9));
      _text(canvas, _clock(n.wake!), Offset(cx, y(wake) + 9));
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    int align = 0,
    Color? ink,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: KeyType.rangeEnd.copyWith(color: ink ?? colors.ink2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == 1 ? at.dx - painter.width : at.dx - painter.width / 2;
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_BedWakePainter old) =>
      old.progress != progress ||
      old.nights != nights ||
      old.colors != colors ||
      old.family != family;
}
