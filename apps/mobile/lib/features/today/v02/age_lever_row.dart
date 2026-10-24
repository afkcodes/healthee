/// One row of the lever card: a lever that was counted, one the server could
/// not count today, or one the model never counts.
///
/// A term that was not counted is drawn as words ("Not counted", "Left out")
/// and never as a zone bar or a `0.0`: one says "we could not price this", the
/// other says "we priced it and it came to nothing".
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/shared/format/age_lever_format.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/instruments/zone_bar.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:solar_icons/solar_icons.dart';

/// The right column's minimum width, logical px.
const double kLeverYearsWidth = 76;

/// The chevron's size, logical px.
const double kLeverChevron = 16;

/// Vertical padding inside a row, logical px.
const double kLeverRowPad = 16;

/// The gap between a row's lines, logical px.
const double kLeverLineGap = 8;

/// What a row that was not priced says in its right column.
enum LeverAbsence {
  /// The server could not compute it today.
  notCounted('Not counted'),

  /// The model never prices it.
  leftOut('Left out');

  const LeverAbsence(this.words);

  /// The right-column text.
  final String words;
}

/// What a withheld row says when its reason is printed above the card.
const String kReasonAbove = 'Reason above';

/// The key a row is found by in tests.
Key leverRowKey(String term) => ValueKey<String>('lever-row-$term');

/// The first sentence of [message], verbatim, up to the first ". ".
String firstSentence(String message) {
  final cut = message.indexOf('. ');
  return cut < 0 ? message : message.substring(0, cut + 1);
}

/// A lever that was counted.
class AgeLeverRow extends StatelessWidget {
  const AgeLeverRow({
    required this.contribution,
    required this.reveals,
    this.onOpen,
    super.key,
  });

  /// The lever.
  final AgeContribution contribution;

  /// Where the zone bar's reveal is remembered.
  final RevealRegistry reveals;

  /// Called with the term when the row is tapped.
  final void Function(String term)? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final delta = c.deltaYears;
    if (delta == null || (c.value == null && c.comparedAs == null)) {
      return AgeAbsentRow(
        term: c.term,
        absence: LeverAbsence.notCounted,
        onOpen: onOpen,
      );
    }
    final colors = context.colors;
    final shown = leverValue(c);
    final term = c.term.toLowerCase();
    final isFitness = term == 'fitness';
    final isSleep = term.contains('sleep');
    final bar = isFitness || isSleep;
    final ink = switch (verdictForDelta(delta)) {
      VerdictTone.better => colors.fav,
      VerdictTone.worse => colors.alert,
      VerdictTone.neutral => colors.ink2,
    };
    final years = Text.rich(
      signedYearsSpan(delta, TypeLadder.title1.copyWith(color: ink)),
    );
    final yearsColumn = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: kLeverYearsWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          years,
          Text('years', style: TypeLadder.callout.copyWith(color: colors.ink2)),
        ],
      ),
    );
    final Widget main = bar
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: _bar(shown, isFitness)),
              const SizedBox(width: Insets.sm),
              yearsColumn,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${shown.value}$kNbsp${shown.unit}',
                  style: TypeLadder.callout.copyWith(color: colors.ink2),
                ),
              ),
              yearsColumn,
            ],
          );
    final caption = _caption(c, isFitness, isSleep);
    return _RowFrame(
      rowKey: leverRowKey(c.term),
      term: c.term,
      onOpen: onOpen,
      semantics: _spoken(c, shown, delta),
      children: <Widget>[
        main,
        if (caption != null) ...<Widget>[
          const SizedBox(height: kLeverLineGap),
          Text(caption, style: TypeLadder.caption.copyWith(color: colors.ink2)),
        ],
      ],
    );
  }

  Widget _bar(({String value, String unit}) shown, bool isFitness) {
    final c = contribution;
    final at = isFitness ? c.value! : (c.comparedAs ?? c.value!);
    final target = c.target;
    return ToneScope(
      tone: isFitness ? Tone.fitness : Tone.sleep,
      child: RevealOnce(
        id: 'body.lever.${c.term}',
        registry: reveals,
        builder: (context, t) => ZoneBar(
          value: at,
          low: isFitness ? kVo2ScaleLow : kSleepScaleLow,
          high: isFitness ? kVo2ScaleHigh : kSleepScaleHigh,
          shape: isFitness ? ZoneShape.rising : ZoneShape.peak,
          target: target,
          targetLabel: target == null
              ? null
              : isFitness
              ? '${plainNumber(target)} median for your age group'
              : 'low point ${plainNumber(target)}${kNbsp}h',
          valueText: shown.value,
          unitText: shown.unit,
          lowLabel: isFitness
              ? plainNumber(kVo2ScaleLow)
              : '${plainNumber(kSleepScaleLow)}${kNbsp}h',
          highLabel: isFitness
              ? plainNumber(kVo2ScaleHigh)
              : '${plainNumber(kSleepScaleHigh)}${kNbsp}h',
          progress: t,
        ),
      ),
    );
  }

  static String? _caption(AgeContribution c, bool isFitness, bool isSleep) {
    if (isFitness) {
      final method = c.method;
      return method == null ? null : 'From ${methodLabel(method)}';
    }
    if (isSleep && c.value != null) {
      final measured = '${c.value!.toStringAsFixed(1)}${kNbsp}h';
      final counted = c.comparedAs;
      const window = 'average over the last 14 days';
      return counted == null
          ? 'Measured $measured a night · $window'
          : 'Measured $measured a night, counted as '
                '${counted.toStringAsFixed(1)}${kNbsp}h on the study’s '
                'self-report scale · $window';
    }
    final method = c.method;
    return method == null ? null : 'From ${methodLabel(method)}';
  }

  static String _spoken(
    AgeContribution c,
    ({String value, String unit}) shown,
    double delta,
  ) {
    final term = c.term.toLowerCase();
    final name = term == 'fitness' ? 'Fitness VO2max' : leverLabel(c.term);
    final unit = switch (shown.unit) {
      'mL/kg/min' => 'millilitres per kilo per minute',
      'h' => 'hours',
      final String other => other,
    };
    final years = spokenYears(delta);
    return '$name ${shown.value} $unit, $years';
  }
}

/// A lever that was not priced: [LeverAbsence.notCounted] when the server
/// withheld it today, [LeverAbsence.leftOut] when the model never counts it.
class AgeAbsentRow extends StatelessWidget {
  const AgeAbsentRow({
    required this.term,
    required this.absence,
    this.message,
    this.note,
    this.onOpen,
    super.key,
  });

  /// Which lever.
  final String term;

  /// How it was not counted.
  final LeverAbsence absence;

  /// The sentence shown under the name, verbatim; null shows none.
  final String? message;

  /// A Caption in place of [message], for a reason said elsewhere on screen.
  final String? note;

  /// Called with the term when the row is tapped.
  final void Function(String term)? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = message;
    final aside = note;
    return _RowFrame(
      rowKey: leverRowKey(term),
      term: term,
      onOpen: onOpen,
      semantics:
          '${leverLabel(term)}, ${absence.words.toLowerCase()}'
          '${text == null || text.isEmpty ? '' : '. $text'}'
          '${aside == null ? '' : '. $aside'}',
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: text != null && text.isNotEmpty
                  ? Text(
                      text,
                      style: TypeLadder.callout.copyWith(color: colors.ink2),
                    )
                  : aside == null
                  ? const SizedBox.shrink()
                  : Text(
                      aside,
                      style: TypeLadder.caption.copyWith(color: colors.ink2),
                    ),
            ),
            const SizedBox(width: Insets.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: kLeverYearsWidth),
              child: Text(
                absence.words,
                textAlign: TextAlign.right,
                style: TypeLadder.caption.copyWith(color: colors.ink2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The shared top line (Label and chevron), padding, tap and semantics.
class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.rowKey,
    required this.term,
    required this.children,
    required this.semantics,
    this.onOpen,
  });

  final Key rowKey;
  final String term;
  final List<Widget> children;
  final String semantics;
  final void Function(String term)? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final open = onOpen;
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: kLeverRowPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  leverLabel(term).toUpperCase(),
                  style: TypeLadder.label.copyWith(color: colors.ink),
                ),
              ),
              if (open != null)
                Icon(
                  SolarIconsOutline.altArrowRight,
                  size: kLeverChevron,
                  color: colors.ink2,
                ),
            ],
          ),
          const SizedBox(height: kLeverLineGap),
          ...children,
        ],
      ),
    );
    return KeyedSubtree(
      key: rowKey,
      child: Semantics(
        container: true,
        button: open != null,
        label: semantics,
        excludeSemantics: true,
        onTap: open == null ? null : () => open(term),
        child: HTap(onTap: open == null ? null : () => open(term), child: body),
      ),
    );
  }
}
