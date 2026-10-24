/// The illness flag — the only place in this product that spends red.
///
/// Brief §2: *"Reserve true red for the illness/safety flag alone."* Brief §4.1:
/// *"if present, it outranks everything. Deterministic, safety-critical, not
/// AI."* Both are honoured here and nowhere else.
///
/// [IllnessFlag.framing] is rendered **verbatim**. It is a calibrated safety
/// sentence — "possible early signal", "consider lighter activity" — and the UI
/// layer has no access to the evidence that calibrated it. Re-wording it here is
/// how a hedge becomes a diagnosis or a warning becomes a shrug.
///
/// ## The DATE is on the face, because the flag reaches two days back
///
/// `read/health_metrics.py` selects the newest flag in `[anchor − 2 days, anchor]`
/// and ships `date` precisely so a reader can tell which day it is about. This
/// banner parsed it and drew everything except that — while the framing sentence it
/// prints verbatim is present-tense (*"consider lighter activity today"*). So a flag
/// raised on Monday rendered on Wednesday as advice about Wednesday, with nothing on
/// screen able to say otherwise: stale-as-current, on the one safety-critical block
/// on the Today screen.
///
/// The comparison is `shared/format/other_day.dart`'s — the same one `ActionsSection`
/// already made and the v02 Actions screen now makes. Three surfaces needing one
/// decision is what that file is for.
///
/// ## The deltas are the server's sentence, and only the server's
///
/// The flag is deterministic and the owner is entitled to see what fired it:
/// respiratory rate and skin temperature, each against **their own** baseline, not a
/// population's. That is already in [IllnessFlag.framing], with the WINDOW named —
/// `read/health_metrics.py` builds *"breathing rate +2.4 bpm vs your 14-day
/// baseline"* and records why: `[[respiratory_rate_normal]]` Coach Directive 1,
/// *"never quote a '+X br/min above baseline' without saying which baseline"*,
/// because that note ships **three** baseline windows (14 nights here, 42 days in
/// `recovery_score`, 30 in the anomaly layer).
///
/// This banner used to print that sentence and then print the same two numbers again
/// from the parsed fields, client-side, with the window dropped. A second copy of a
/// number can only ever agree less than the first, and this one broke the directive
/// its own first line exists to satisfy. It is gone (audit C4); the deltas stay on
/// the model, where the ⓘ and a log line still want them.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/illness_flag.dart';
import 'package:healthee/shared/format/other_day.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

/// A possible early illness signal, with what fired it.
/// What the banner's own ⓘ sheet is called. Its heading, in sentence case.
const String kIllnessBannerTitle = 'Possible early signal';

class IllnessBanner extends StatelessWidget {
  /// Renders [flag]. Callers show this only when the payload carried one.
  const IllnessBanner({required this.flag, this.viewedDay, super.key});

  /// The flag, with its calibrated sentence.
  final IllnessFlag flag;

  /// The day the payload answers for — `as_of.day`, never a device clock.
  ///
  /// Null means the payload carried no `as_of` (an older server), and then the banner
  /// claims nothing about which day the flag is for rather than guessing one.
  final String? viewedDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return StateCard(
      border: colors.alert,
      fill: colors.alertSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expanded, so the 20 px card padding wraps the title rather
              // than overflowing a narrow screen.
              Expanded(
                child: Text(
                  'POSSIBLE EARLY SIGNAL',
                  style: text.labelSmall?.copyWith(
                    color: colors.alert,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              if (flag.sustained)
                Text(
                  'sustained',
                  style: text.labelSmall?.copyWith(color: colors.alert),
                ),
              // This banner had citations and no ⓘ. Taking the chips off its
              // face without giving it one would have removed the grounding
              // from the single most consequential claim on the screen — so the
              // dot is the sheet, and the sheet is the sources.
              MetricInfoDot(
                null,
                detail: MetricDetail(
                  title: kIllnessBannerTitle,
                  notes: flag.researchNoteIds,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          // Verbatim. See the library docstring.
          Text(flag.framing, style: text.bodyLarge),
          // The day the signal was RAISED, whenever that is not the day on screen.
          // The sentence above is present-tense and the server's window reaches two
          // days back, so without this the two disagree silently.
          if (otherDay(flag.date, viewedDay) case final String day) ...[
            const SizedBox(height: Insets.sm),
            Text(
              raisedOnDay(day),
              style: text.bodySmall?.copyWith(color: colors.ink2),
            ),
          ],
        ],
      ),
    );
  }
}
