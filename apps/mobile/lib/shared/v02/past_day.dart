/// What a date-aware screen draws where a judgement it cannot date belongs.
///
/// ```css
/// .history-missing    { padding:20px; border:1px dashed var(--rule);
///                       border-radius:18px; margin:12px 0; }
/// .history-missing h3 { font-size:13px; }
/// .history-missing p  { font-size:11px; margin-top:8px; }
/// ```
///
/// `history-screens.js` opens every past-day screen with one of these, and the
/// dashed edge is the same load-bearing signal `withheld_panel.dart` argues:
/// every other v02 container has a solid hairline, so a visibly broken outline
/// is the one shape that reads as absence before a word is read.
///
/// ## Why the app needs it on more screens than the prototype does
///
/// The prototype refuses a past day's analysis because its fixture holds one
/// day of it. This app refuses for a structural reason and permanently:
/// `/api/today` and `/api/activity` take **no day parameter at all**, and
/// `/api/sleep` takes a window rather than a target day. So recovery, sleep
/// health, debt, VO₂max, biological age, the correlations and the day's
/// suggestion exist for the current day and no other — there is no request that
/// would produce yesterday's.
///
/// The alternative was to draw today's numbers under yesterday's date. That is
/// stale-as-current: the failure `vo2max_tier`'s
/// freshness horizon exists for, and the one this repo has already swept three
/// times. So the screens say what is missing and why, which is also why this is
/// a *titled* block rather than a blank space — a screen that simply ends is
/// read as a bad day.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';

/// Why every one of these refusals exists, in the one sentence they share.
///
/// One constant rather than fourteen paraphrases: the reason is the same on
/// every screen, and a paraphrase that drifted would be a second account of why
/// the app will not answer.
const String kPastDayReason =
    'It is worked out for the current day only, so nothing is shown here rather '
    'than today’s figures under an older date.';

/// `.history-missing` — a heading, a sentence, and a broken outline.
class PastDayNotice extends StatelessWidget {
  /// [title] names what is absent; [body] says why.
  const PastDayNotice({required this.title, required this.body, super.key});

  /// `.history-missing { padding: 20px }`.
  static const double padding = 20;

  /// `.history-missing { border-radius: 18px }`.
  static const double radius = 18;

  /// `.history-missing { margin: 12px 0 }`.
  static const double margin = 12;

  /// `.history-missing p { margin-top: 8px }`.
  static const double bodyGap = 8;

  /// The dash length of the broken edge, and the gap between dashes.
  static const double dash = 4;

  /// What is not here.
  final String title;

  /// Why it is not, in one sentence about us rather than about the day.
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: margin),
      child: CustomPaint(
        painter: _DashedEdge(colour: colors.rule),
        child: Padding(
          padding: const EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: TypeScale.panelTitle.copyWith(color: colors.ink),
              ),
              const SizedBox(height: bodyGap),
              Text(
                body,
                style: TypeScale.panelNote.copyWith(color: colors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `border: 1px dashed`, which Flutter's `Border` cannot draw.
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.colour});

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(PastDayNotice.radius),
    );
    final Paint paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = hairline;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        final double end = (at + PastDayNotice.dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(at, end), paint);
        at = end + PastDayNotice.dash;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge oldDelegate) => oldDelegate.colour != colour;
}
