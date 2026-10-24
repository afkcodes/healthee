/// `.challenge-card` — one commitment, its target and how far along it is.
///
/// ```css
/// .challenge-card   { padding:20px; border:1px solid var(--line);
///                     background:var(--surface); border-radius:22px }
/// .challenge-card h3{ font-size:17px; margin:12px 0 6px }
/// .challenge-card p { font-size:11px; line-height:1.8 }
/// .challenge-card .progress-track { background: var(--accent-soft) }
/// .progress-track   { height:7px; border-radius:8px; margin-block:16px 8px }
/// ```
///
/// The head is `row between`: a badge naming the family, and a `.tiny-label`
/// naming the window. The foot is the same row again: where the reading stands
/// against the target, and the arrow into the detail screen.
///
/// ## The track is drawn only when the server sent progress
///
/// A challenge with no `progress` block draws **no bar** — not an empty one and
/// not one at zero. "Nothing has been observed yet" and "you are at zero" are
/// different days, and a bar sitting at the left edge says the second one.
///
/// ## The title is model prose, so its sources are in the head's ⓘ
///
/// `challenge.title` carries inline `[note_id]` markers and the payload sends
/// `citations` beside it. Both used to be drawn as chips under the title, on the
/// card's face. They are now one tap behind the ⓘ on the head row, which draws
/// nothing at all for a challenge that cites nothing.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/challenge_progress.dart';
import 'package:healthee/features/actions/v02/suggestion_card.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/metric_info/challenge_sources.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/grounded_text.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// One challenge in the prototype's card.
class ChallengeCard extends StatelessWidget {
  /// [onOpen] pushes the challenge's own screen.
  const ChallengeCard({required this.challenge, required this.onOpen, super.key});

  /// `padding: 20px`.
  static const double padding = 20;

  /// `.challenge-card h3 { margin: 12px 0 6px }`.
  static const double titleGap = 12;

  /// The same, below.
  static const double bodyGap = 6;

  /// `.progress-track { margin-block: 16px 8px }`.
  static const double trackTopGap = 16;

  /// The same, below.
  static const double trackBottomGap = 8;

  /// `.icon.small` on the foot row.
  static const double arrowSize = 16;

  /// The commitment.
  final Challenge challenge;

  /// Opens it.
  final VoidCallback onOpen;

  /// What the `.tiny-label` on the head row says.
  ///
  /// An active challenge names its window; a suggested one says so first,
  /// because "7-day challenge" over something nobody has started reads as a
  /// commitment the owner did not make.
  static String windowLabel(Challenge challenge) {
    final window = '${challenge.windowDays}-day';
    return challenge.status == 'active'
        ? '$window challenge'
        : 'Suggested · $window';
  }

  /// Where the reading stands, in the server's own numbers, or null when it has
  /// reported none.
  static String? standing(Challenge challenge) {
    final progress = challenge.progress;
    if (progress == null) {
      return null;
    }
    if (progress.cadence == 'daily') {
      final hit = progress.hitDays;
      final window = progress.window;
      if (hit == null || window == null) {
        return null;
      }
      return '$hit of $window days at the target';
    }
    final current = progress.current;
    return current == null
        ? null
        : '${_trim(current)} of ${_trim(progress.target)} ${progress.unit}';
  }

  /// How full the track is, or null when nothing has been observed.
  static double? fraction(ChallengeProgress? progress) {
    if (progress == null) {
      return null;
    }
    if (progress.cadence == 'daily') {
      final hit = progress.hitDays;
      final window = progress.window;
      return hit == null || window == null || window <= 0
          ? null
          : hit / window;
    }
    final current = progress.current;
    return current == null || progress.target <= 0
        ? null
        : current / progress.target;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = toneForCategory(challenge.metric.split('_').first);
    final filled = fraction(challenge.progress);
    final foot = standing(challenge);
    return ToneScope(
      tone: tone,
      child: Semantics(
        button: true,
        label: challenge.title,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      StatusBadge(
                        metricName(challenge.metric),
                        accented: true,
                      ),
                      const Spacer(),
                      Text(
                        windowLabel(challenge),
                        style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
                      ),
                      if (challengeSources(challenge)
                          case final MetricDetail detail
                          when detail.isNotEmpty)
                        MetricInfoDot(
                          // No explainer key: a challenge is a commitment, not
                          // a metric the corpus has an entry for. Its sources
                          // ARE the content, which is what the dot draws for.
                          null,
                          detail: detail,
                          fallbackTitle: metricName(challenge.metric),
                        ),
                    ],
                  ),
                  const SizedBox(height: titleGap),
                  GroundedProse(
                    text: challenge.title,
                    style: TypeScale.challengeTitle.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: bodyGap),
                  // **`GroundedProse`, not `Text`.** The server writes `why`
                  // with inline `[note_id]` markers, exactly as it writes the
                  // title, and a plain `Text` printed them. The sources go to
                  // the dot above via `challenge.grounding`.
                  GroundedProse(
                    text: challenge.why,
                    style: TypeScale.noticeBody.copyWith(color: colors.ink2),
                  ),
                  if (filled case final double value) ...<Widget>[
                    const SizedBox(height: trackTopGap),
                    ProgressTrack(fraction: value),
                    const SizedBox(height: trackBottomGap),
                  ] else
                    const SizedBox(height: trackTopGap),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          foot ??
                              '${metricName(challenge.metric)} '
                                  '${challenge.comparator} '
                                  '${_trim(challenge.target)}',
                          style: TypeScale.tinyLabel.copyWith(
                            color: colors.ink2,
                          ),
                        ),
                      ),
                      Icon(
                        SolarIconsOutline.arrowRight,
                        size: arrowSize,
                        color: colors.ink2,
                      ),
                    ],
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

/// `9000` rather than `9000.0`, and `8.5` left alone.
String _trim(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
