/// Today's three key numbers, full width: recovery, sleep and movement.
///
/// The redesign the owner approved (`design/mobile-preview/proposal.js`,
/// `#p-today`) replaced the three small tiles with three cards that each say,
/// in one look, whether the number is usual for this owner. Every band is
/// `usual_range.dart`'s, built from the owner's own history:
///
///   * **recovery** from `recovery_score` in the dated history;
///   * **sleep** from the nights on the Sleep page, total sleep time;
///   * **movement** from `steps_total` in the dated history.
///
/// Both reads are the ones other screens already make, so on a warm session
/// nothing new is fetched. While either is loading, or when it fails, a card
/// draws its bar without a band and says it is learning, rather than holding
/// up the figure the server already sent.
///
/// ## Steps on a day that is not over
///
/// A morning's step count against whole days would say "Below your usual"
/// every morning. On the owner's today the movement card gives no verdict: its
/// chip says `So far today` and its band is named "by day's end". A past day
/// is a whole day and gets the verdict.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/features/today/steps_plateau.dart';
import 'package:healthee/features/today/today_facts.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:healthee/shared/v02/range_bar.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/steps_bar.dart';
import 'package:solar_icons/solar_icons.dart';

/// The heading over the three cards, `proposal.js`'s own.
const String kKeyNumbersTitle = "Today's three";

/// The track's ends for a night: four to nine hours, `proposal.js`'s scale.
const int kSleepTrackMin = 240;
const int kSleepTrackMax = 540;

/// `.p-keys { gap: 10px }`.
const double kKeyGap = 10;

/// The three cards, stacked.
class TodayKeyNumbers extends ConsumerWidget {
  /// [facts] is the screen's one parse of the payload.
  const TodayKeyNumbers({
    required this.facts,
    this.onOpenRecovery,
    this.onOpenSleep,
    this.onOpenActivity,
    this.onOpenTrends,
    super.key,
  });

  /// The figures this render is built from.
  final TodayFacts facts;

  /// Where each card goes.
  final VoidCallback? onOpenRecovery;
  final VoidCallback? onOpenSleep;
  final VoidCallback? onOpenActivity;

  /// The head's `Trends` link. Null draws the head without it.
  final VoidCallback? onOpenTrends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = currentAccountValue(ref.watch(datedHistoryProvider)).value;
    final nights = currentAccountValue(ref.watch(sleepPageProvider)).value;
    final day = facts.snapshot.date;
    final sleepValues = <double>[
      for (final SleepNight night in nights?.nights ?? const <SleepNight>[])
        if (night.tstMin.valueOrNull case final double minutes)
          if (_before(night.date, day)) minutes,
    ];
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHead(
            title: kKeyNumbersTitle,
            actionLabel: onOpenTrends == null ? null : 'Trends',
            onAction: onOpenTrends,
          ),
          _recovery(history),
          const SizedBox(height: kKeyGap),
          _sleep(nights == null ? null : usualRangeOf(sleepValues)),
          const SizedBox(height: kKeyGap),
          _movement(history),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: TypeScale.panelContext.copyWith(color: colors.ink2),
              children: <InlineSpan>[
                const TextSpan(
                  text: 'The shaded part of each bar is the middle half of ',
                ),
                TextSpan(
                  text: 'your own last $kUsualWindowDays days',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
                const TextSpan(text: '. The mark is today.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Within the usual window before [day], by date alone.
  static bool _before(String date, String day) {
    final at = DateTime.tryParse(date);
    final end = DateTime.parse(day);
    return at != null &&
        at.isBefore(end) &&
        !at.isBefore(end.subtract(const Duration(days: kUsualWindowDays)));
  }

  UsualRange? _band(DatedHistory? history, String metric) =>
      history == null || !history.covers(metric)
      ? null
      : usualRangeOf(windowBefore(history[metric], facts.snapshot.date));

  Widget _recovery(DatedHistory? history) {
    final score = facts.snapshot.recovery.valueOrNull;
    if (score == null) {
      return _hole(Tone.recovery, SolarIconsOutline.heartPulse, 'Recovery');
    }
    final band = _band(history, 'recovery_score');
    final side = band?.sideOf(score.recovery.toDouble());
    return KeyNumberCard(
      tone: Tone.recovery,
      icon: SolarIconsOutline.heartPulse,
      name: 'Recovery',
      value: '${score.recovery}',
      unit: ' / 100',
      verdict: _verdict(side, worse: UsualSide.below, better: UsualSide.above),
      bar: RangeBar(
        value: score.recovery.toDouble(),
        min: 0,
        max: 100,
        band: band,
        startLabel: '0',
        endLabel: '100',
        usualLabel: _usual(band, (v) => '${v.round()}'),
        pendingLabel: kLearningUsual,
        semanticLabel: _spokenBand(
          'Recovery ${score.recovery}',
          band,
          (v) => '${v.round()}',
        ),
      ),
      lead: _remaining(score),
      line: switch (side) {
        UsualSide.below => 'You started lower than most of your mornings.',
        UsualSide.above => 'You started higher than most of your mornings.',
        UsualSide.within => 'A usual start for you.',
        null => null,
      },
      onOpen: onOpenRecovery,
    );
  }

  static String? _remaining(RecoveryScore score) =>
      score.readiness == null ? null : '${score.readiness} left for today.';

  Widget _sleep(UsualRange? band) {
    final minutes = facts.sleepDurationMin.valueOrNull;
    if (minutes == null) {
      return _hole(Tone.sleep, SolarIconsOutline.moonSleep, 'Sleep');
    }
    final need = facts.snapshot.sleepDebt.valueOrNull?.needMin;
    final side = band?.sideOf(minutes.toDouble());
    return KeyNumberCard(
      tone: Tone.sleep,
      icon: SolarIconsOutline.moonSleep,
      name: 'Sleep',
      value: durationText(minutes),
      // More sleep than usual is not scored better: long sleep is its own
      // question, so above the band is said in neutral ink.
      verdict: _verdict(side, worse: UsualSide.below),
      bar: RangeBar(
        value: minutes.toDouble(),
        min: kSleepTrackMin.toDouble(),
        max: kSleepTrackMax.toDouble(),
        band: band,
        startLabel: hoursText(4),
        endLabel: hoursText(9),
        usualLabel: _usual(band, durationText),
        pendingLabel: kLearningUsual,
        semanticLabel: _spokenBand(
          'Asleep ${durationText(minutes)}',
          band,
          durationText,
        ),
      ),
      lead: _needLead(minutes, need),
      line: need == null || need <= 0 || minutes == need
          ? null
          : '${minutes < need ? 'of' : 'over'} your ${durationText(need)} need.',
      onOpen: onOpenSleep,
    );
  }

  static String? _needLead(int minutes, int? need) {
    if (need == null || need <= 0) {
      return null;
    }
    if (minutes == need) {
      return 'Exactly your ${durationText(need)} need.';
    }
    final gap = durationText((need - minutes).abs());
    return minutes < need ? '$gap short' : gap;
  }

  Widget _movement(DatedHistory? history) {
    final steps = facts.steps.valueOrNull;
    if (steps == null) {
      return _hole(Tone.movement, SolarIconsOutline.walking, 'Movement');
    }
    final count = steps.round();
    final band = _band(history, 'steps_total');
    final live = facts.snapshot.asOf?.isToday ?? true;
    final plateau = stepsPlateauTop(
      facts.snapshot.biologicalAge.valueOrNull?.chronologicalAge,
    );
    return KeyNumberCard(
      tone: Tone.movement,
      icon: SolarIconsOutline.walking,
      name: 'Movement',
      value: commaGrouped(count),
      unit: ' steps',
      verdict: live
          ? const Verdict('So far today', VerdictTone.neutral)
          : _verdict(
              band?.sideOf(steps),
              worse: UsualSide.below,
              better: UsualSide.above,
            ),
      bar: stepsBar(count, band, live: live),
      lead: plateau == null || count >= plateau
          ? null
          : '${commaGrouped(plateau - count)} to go',
      line: plateau == null
          ? null
          : count >= plateau
          ? 'Past the ${commaGrouped(plateau)} plateau.'
          : 'to the ${commaGrouped(plateau)} plateau.'
                '${live ? ' The day is not over.' : ''}',
      onOpen: onOpenActivity,
    );
  }

  /// `usual 55 to 72`, or `usual about 6h 20m` when both ends say the same.
  static String? _usual(
    UsualRange? band,
    String Function(double) say, {
    String prefix = 'usual',
  }) {
    if (band == null) {
      return null;
    }
    final low = say(band.low);
    final high = say(band.high);
    return low == high ? '$prefix about $low' : '$prefix $low to $high';
  }

  static Verdict? _verdict(
    UsualSide? side, {
    required UsualSide worse,
    UsualSide? better,
  }) {
    if (side == null) {
      return null;
    }
    final tone = side == worse
        ? VerdictTone.worse
        : side == better
        ? VerdictTone.better
        : VerdictTone.neutral;
    return Verdict(side.words, tone);
  }

  static String _spokenBand(
    String reading,
    UsualRange? band,
    String Function(double) say,
  ) => band == null
      ? '$reading. Your usual range is still being learned.'
      : '$reading. Your usual range, the middle half of the last '
            '$kUsualWindowDays days, is ${say(band.low)} to ${say(band.high)}.';

  static Widget _hole(Tone tone, IconData icon, String name) => KeyNumberCard(
    tone: tone,
    icon: icon,
    name: name,
    value: '—',
    lead: 'Not measured.',
  );
}
