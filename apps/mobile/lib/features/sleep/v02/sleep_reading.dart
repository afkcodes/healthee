/// The Sleep screen's opening reading — `.sleep-reading` and its `.colour-key`.
///
/// `design/mobile-preview/sleep-history-view.js`, straight after the header:
///
/// ```js
/// <div class="sleep-reading">
///   <div><p class="small">Time asleep</p>
///        <div class="big-duration">${H.duration(night.duration_min)
///                                    .replace(/([hm])/g,'<small>$1</small>')}</div></div>
///   <div class="sleep-device"><strong>${night.zepp_score ?? '—'}</strong>
///        <span>Amazfit score<br>Device estimate</span></div>
/// </div>
/// <div class="colour-key">
///   <span data-tone="sleep"><i></i>${bedtime} bedtime</span>
///   <span data-tone="movement"><i></i>${wake} wake</span>
///   <span>${H.duration(night.tib_min)} in bed</span>
/// </div>
/// ```
///
/// ```css
/// .sleep-reading             { display:flex; align-items:end;
///                              justify-content:space-between; padding:8px 4px 20px }
/// .sleep-reading .big-duration        { font-size:64px; line-height:1;
///                              font-weight:600; letter-spacing:-3px; margin-top:10px }
/// .sleep-reading .big-duration small  { font-size:22px; font-weight:400;
///                              color:var(--sleep) }
/// .sleep-reading .sleep-device        { border-left:1px solid var(--line);
///                              padding-left:16px; text-align:right }
/// .sleep-device strong       { display:block; font-size:27px; color:var(--sleep) }
/// .sleep-device span         { display:block; font-size:9px; color:var(--muted) }
/// ```
///
/// ## `var(--sleep)`, not a parameter
///
/// The CSS names the sleep family directly on three of these elements. This
/// widget resolves it from an enclosing `ToneScope(tone: Tone.sleep)` instead,
/// which is the same hue and cannot be handed a different one.
///
/// ## The refusals are the point of this block
///
/// Both figures are `Reading`s. A withheld time asleep draws the dash the
/// prototype's own `?? '—'` draws, and the server's reason lands **under this
/// block**, attached to it, naming the field it is about. The `in bed` key is
/// dropped rather than written as `—`: it is one entry of a legend, and a legend
/// entry for a value nobody has is not a smaller truth, it is noise.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/features/today/v02/today_key_numbers.dart'
    show kSleepTrackMax, kSleepTrackMin;
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:healthee/shared/v02/range_bar.dart';
import 'package:healthee/shared/v02/steps_bar.dart' show kLearningUsual;

/// What the strap's own number is, said where the number is.
const String kDeviceScoreCaption = 'Amazfit score\nDevice estimate';

/// The night's headline: time asleep, and the strap's own score beside it.
class SleepReading extends StatelessWidget {
  /// [night] is the most recent session on the payload.
  const SleepReading({
    required this.night,
    this.usual,
    this.needMin,
    super.key,
  });

  /// The night being read.
  final SleepNight night;

  /// The owner's usual time asleep (`sleep_usual.dart`), or null while there
  /// are too few nights to have one.
  final UsualRange? usual;

  /// The server's sleep need, minutes, when it sent one.
  final int? needMin;

  /// Between the range bar's line and the three small figures.
  static const double statsGap = 14;

  /// The three small figures' gap, corner and padding.
  static const double statGap = 8;
  static const double statRadius = 16;
  static const EdgeInsets statPadding = EdgeInsets.fromLTRB(12, 10, 12, 12);

  /// `padding: 8px 4px 20px`.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(4, 8, 4, 20);

  /// `.sleep-device { padding-left:16px }`.
  static const double devicePad = 16;

  /// `.big-duration { margin-top:10px }`.
  static const double figureGap = 10;

  /// The gap between the reading and its key.
  static const double keyGap = 4;

  /// The gap between the key and a refusal note under it.
  static const double noteGap = 10;

  @override
  Widget build(BuildContext context) => ToneScope(
    tone: Tone.sleep,
    child: Builder(builder: _body),
  );

  Widget _body(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: _Asleep(night: night)),
              const SizedBox(width: devicePad),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colors.line, width: hairline),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: devicePad),
                  child: _DeviceScore(reading: night.deviceScore),
                ),
              ),
            ],
          ),
        ),
        if (night.tstMin.valueOrNull case final double minutes) ...<Widget>[
          const SizedBox(height: keyGap),
          _bar(minutes),
          const SizedBox(height: 10),
          _verdictLine(colors, minutes),
        ],
        if (stats(night) case final List<(String, String)> figures
            when figures.isNotEmpty) ...<Widget>[
          const SizedBox(height: statsGap),
          _stats(colors, figures),
        ],
        if (refusals(night) case final List<String> lines when lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: noteGap),
            child: Text(
              lines.join('\n'),
              style: TypeScale.panelNote.copyWith(color: colors.ink2),
            ),
          ),
      ],
    );
  }

  /// The night against the owner's usual, on the 4 to 9 hour track Today uses.
  Widget _bar(double minutes) {
    final band = usual;
    return RangeBar(
      value: minutes,
      min: kSleepTrackMin.toDouble(),
      max: kSleepTrackMax.toDouble(),
      band: band,
      startLabel: hoursText(4),
      endLabel: hoursText(9),
      usualLabel: band == null
          ? null
          : 'usual ${durationText(band.low)} to ${durationText(band.high)}',
      pendingLabel: kLearningUsual,
      semanticLabel: 'Asleep ${durationText(minutes)}.',
    );
  }

  /// The verdict, and how far the night was from the server's need.
  Widget _verdictLine(HealtheeColors colors, double minutes) {
    final side = usual?.sideOf(minutes);
    final need = needMin;
    final gap = need == null ? null : (need - minutes).round();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (side != null)
          VerdictChip(
            Verdict(
              side.words,
              side == UsualSide.below ? VerdictTone.worse : VerdictTone.neutral,
            ),
          ),
        if (need != null && gap != null)
          Text.rich(
            TextSpan(
              style: KeyType.line.copyWith(color: colors.ink2),
              children: <InlineSpan>[
                TextSpan(
                  text: gap == 0
                      ? 'Exactly'
                      : '${durationText(gap.abs())} ${gap > 0 ? 'short' : 'over'}',
                  style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
                ),
                TextSpan(
                  text:
                      ' ${gap == 0 ? 'your' : 'of your'} ${durationText(need)} need.',
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stats(HealtheeColors colors, List<(String, String)> figures) => Row(
    children: <Widget>[
      for (var i = 0; i < figures.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(width: statGap),
        Expanded(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(statRadius),
              ),
            ),
            child: Padding(
              padding: statPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    figures[i].$1,
                    style: TypeScale.small.copyWith(color: colors.ink2),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      figures[i].$2,
                      style: KeyType.name.copyWith(color: colors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );

  /// `In bed`, `Up`, `Time in bed` — each dropped when it was not recorded.
  static List<(String, String)> stats(SleepNight night) => <(String, String)>[
    if (night.start case final DateTime start) ('In bed', clock(start)),
    if (night.end case final DateTime end) ('Up', clock(end)),
    if (night.tibMin.valueOrNull case final double minutes)
      ('Time in bed', durationText(minutes)),
  ];

  /// The server's own reason for every field this block could not draw.
  static List<String> refusals(SleepNight night) => <String>[
    for (final field in <String, Reading<double>>{
      'Time asleep': night.tstMin,
      "The strap's sleep score": night.deviceScore,
      'Time in bed': night.tibMin,
    }.entries)
      if (field.value case Withheld<double>(:final disclosure))
        '${field.key}: ${disclosure.message}',
  ];
}

/// `Time asleep` over the big duration, with `h` and `m` in the family.
class _Asleep extends StatelessWidget {
  const _Asleep({required this.night});

  final SleepNight night;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final narrow = MediaQuery.sizeOf(context).width < SleepType.narrowWidth;
    final figure = narrow ? SleepType.durationNarrow : SleepType.duration;
    final minutes = night.tstMin.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Time asleep',
          style: TypeScale.small.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: SleepReading.figureGap),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: minutes == null
              ? Text('—', style: figure.copyWith(color: colors.ink2))
              : Text.rich(
                  _spans(
                    minutes,
                    figure.copyWith(color: colors.ink),
                    colors.ink2,
                  ),
                  maxLines: 1,
                ),
        ),
      ],
    );
  }

  /// `7 h 1 min` — the digits at figure size, the units smaller in ink3, each
  /// joined to its figure by U+00A0. The hours and minutes rule is
  /// `durationParts`, shared with `durationText`.
  static TextSpan _spans(double minutes, TextStyle figure, Color unitColor) {
    final unit = SleepType.durationUnit.copyWith(color: unitColor);
    final parts = durationParts(minutes.round());
    return TextSpan(
      style: figure,
      children: <InlineSpan>[
        for (var i = 0; i < parts.length; i++) ...<InlineSpan>[
          if (i > 0) const TextSpan(text: ' '),
          TextSpan(text: '${parts[i].$1}'),
          TextSpan(text: '\u00A0${parts[i].$2}', style: unit),
        ],
      ],
    );
  }
}

/// The strap's own score, named as the strap's.
class _DeviceScore extends StatelessWidget {
  const _DeviceScore({required this.reading});

  final Reading<double> reading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = reading.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          score == null ? '—' : score.round().toString(),
          style: SleepType.deviceScore.copyWith(
            color: score == null ? colors.ink2 : colors.ink,
          ),
        ),
        Text(
          kDeviceScoreCaption,
          textAlign: TextAlign.right,
          style: SleepType.deviceCaption.copyWith(color: colors.ink2),
        ),
      ],
    );
  }
}
