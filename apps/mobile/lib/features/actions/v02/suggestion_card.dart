/// `.focus-card` carrying one cited recommendation — the prototype's
/// **Today's suggestion**.
///
/// ```js
/// // screens-actions.js
/// <div class="focus-card" data-tone="sleep">
///   <span class="focus-title">Today’s suggestion</span> ⌄icon
///   <h3>Sleep earlier tonight.</h3>
///   <p>Your sample history has 2 hours of modelled sleep debt…</p>
///   <button class="check-action" aria-pressed="…">
///     <strong>I’ll try this tonight</strong>
///     <small>One manageable change to start with.</small>
///   </button>
///   H.evidence('sleep_need_debt', 'Why this suggestion')
/// </div>
/// ```
///
/// ## Three things this card will not do
///
/// **The tone is the rec's own category, never a colour a call site picked.** The
/// prototype hard-codes `data-tone="sleep"` because its fixture is a sleep
/// suggestion; ours reads `category` off the wire. That is data choosing the
/// family, which is the whole point of the cascade.
///
/// **Adopting says intent and nothing more.** The `small` under the checkbox is
/// the prototype's own sentence and it is the honest one — the server records an
/// intention, not a completed action, and `recommendation_history.dart` says so
/// too. A tick that read "done" would be this app inventing an observation.
///
/// **A rec with no server id gets no checkbox.** There is nowhere to write the
/// adoption to, and a control that silently does nothing is worse than none.
///
/// ## Where this card's sources are
///
/// Behind `Why this suggestion` — the prototype's `H.evidence()`, and this
/// card's ⓘ. The action, the rationale and the expected effect are three
/// sentences about ONE suggestion sharing one `research_note_ids`, so they are
/// grounded together and the card face carries no chip at all.
///
/// The link therefore draws for a rec with sources and no rationale, and for
/// neither it draws nothing: an ⓘ opening an empty sheet is worse than no ⓘ.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/problem_message.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/data/models/recommendation.dart';
import 'package:healthee/data/recommendations/recommendation_history.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/actions/v02/evidence_sheet.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/states/grounded_text.dart';
import 'package:healthee/shared/v02/choices.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// What the checkbox says before and after it is ticked. The prototype's own.
const String kAdoptLabel = 'I’ll try this';

/// The same, once the intention is recorded.
const String kAdoptedLabel = 'Added to your intentions';

/// The line under the box, ticked. **Not** "completed".
///
/// There is no unticked counterpart. It used to be `One manageable change to
/// start with.` under EVERY suggestion the app had ever drawn — the same
/// sentence, on a line of its own, saying nothing about the card above it.
const String kAdoptedNote = 'An intention, not a completed action.';

/// `Raised by your recovery score (32)` — the reading behind a suggestion.
///
/// **Never the raw id.** `metric_names.dart` argues that an unknown id should
/// keep its id, and that is right where the id is the SUBJECT of a statistic a
/// reader may want to look up. It is wrong here: this is a provenance line on a
/// card, where `recovery_score` is a log line and nothing else.
///
/// ## `signal_source` carries the value as well as the metric
///
/// The server sends `"recovery_score = 32"`, not `"recovery_score"` — the id AND
/// what it read when the suggestion was raised. This looked the whole string up
/// in the name table, found nothing, and fell back to *"Raised by a reading this
/// build cannot name yet"*, which is what the owner actually saw on both cards
/// of the Actions screen. A sentence about the build's limitations, printed to
/// somebody who does not have one, about data that was nameable all along.
///
/// So the id and the value are split apart and both are used. The value is shown
/// because it is the more useful half: "raised by your recovery score" says which
/// dial, and "(32)" says what it read — which is the fact that makes the
/// suggestion make sense.
///
/// The fallback survives for a signal that genuinely is not a metric, and says
/// so plainly rather than printing an id or inventing a phrase.
String? signalLabel(String? signal) {
  if (signal == null) {
    return null;
  }
  final (String id, String? reading) = _splitSignal(signal);
  if (!hasMetricName(id)) {
    return 'Raised by a reading with no name in this app';
  }
  final String named = 'Raised by your ${metricName(id)}';
  return reading == null ? named : '$named ($reading)';
}

/// `"recovery_score = 32"` -> `("recovery_score", "32")`.
///
/// Split on the FIRST `=` only, so a value that contains one survives intact.
/// A signal with no `=` is returned whole with no reading, which is the shape
/// this function was written for before the server began sending both.
(String, String?) _splitSignal(String signal) {
  final int at = signal.indexOf('=');
  if (at < 0) {
    return (signal.trim(), null);
  }
  final String reading = signal.substring(at + 1).trim();
  return (signal.substring(0, at).trim(), reading.isEmpty ? null : reading);
}

/// What the evidence link says. The prototype's own label.
const String kWhyLabel = 'Why this suggestion';

/// The heading of the sheet it opens.
const String kWhyTitle = 'Behind this suggestion';

/// The eyebrow over the first suggestion of the day.
const String kFirstEyebrow = 'Today’s suggestion';

/// The eyebrow over every suggestion after it.
///
/// The prototype's fixture carries ONE recommendation and `/api/today` carries a
/// ranked set. The element is repeated rather than a new one invented; only the
/// eyebrow can say which of the two it is, so only the eyebrow changes.
const String kAlsoEyebrow = 'Also suggested today';

/// The family a category names.
Tone toneForCategory(String? category) => switch (category) {
  'sleep' => Tone.sleep,
  'activity' || 'movement' || 'steps' => Tone.movement,
  'heart' => Tone.heart,
  'breathing' || 'oxygen' => Tone.oxygen,
  'stress' => Tone.stress,
  _ => Tone.fitness,
};

/// The glyph a category wears on the eyebrow row.
IconData iconForCategory(String? category) => switch (category) {
  'sleep' => SolarIconsOutline.moonSleep,
  'activity' || 'movement' || 'steps' => SolarIconsOutline.walking,
  'heart' => SolarIconsOutline.heart,
  'breathing' || 'oxygen' => SolarIconsOutline.wind,
  'stress' => SolarIconsOutline.sun,
  _ => SolarIconsOutline.leaf,
};

/// One recommendation, in the prototype's focus card.
class SuggestionCard extends ConsumerStatefulWidget {
  /// [first] picks the eyebrow; see [kAlsoEyebrow].
  const SuggestionCard({
    required this.recommendation,
    this.first = true,
    super.key,
  });

  /// The rec being drawn.
  final Recommendation recommendation;

  /// Whether this is the top of the ranked set.
  final bool first;

  @override
  ConsumerState<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends ConsumerState<SuggestionCard> {
  bool _busy = false;
  String? _trouble;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rec = widget.recommendation;
    final adopted = rec.adopted ?? false;
    final grounding = rec.grounding;
    return FocusCard(
      tone: toneForCategory(rec.category),
      icon: iconForCategory(rec.category),
      eyebrow: widget.first ? kFirstEyebrow : kAlsoEyebrow,
      // The evidence link, moved off the footer and onto the row the eyebrow
      // already occupies. See `FocusCard.action`.
      // Drawn for a rec with sources but no rationale too — the sources are
      // the content in that case. With neither, nothing.
      action:
          rec.rationale != null ||
              grounding.isNotEmpty ||
              rec.gradeLabel != null
          ? _why(context, rec, grounding)
          : null,
      title: GroundedProse(
        text: rec.action,
        style: TypeScale.focusTitle.copyWith(color: colors.ink),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (rec.expectedEffect case final String effect) Text(effect),
          // The part that does not fit on Today's index: which reading raised
          // this one.
          if (signalLabel(rec.signalSource) case final String raised)
            Text(
              raised,
              style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
            ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (rec.id case final int id)
            CheckAction(
              pressed: adopted,
              title: adopted ? kAdoptedLabel : kAdoptLabel,
              // Only once it IS adopted, where the line says something this
              // card does not already — see `kAdoptedNote`.
              note: adopted ? kAdoptedNote : null,
              onPressed: _busy ? null : () => unawaited(_toggle(id, adopted)),
            ),
          if (_trouble case final String message)
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
              ),
            ),
        ],
      ),
    );
  }

  /// The evidence dot, in the eyebrow row rather than under the card.
  ///
  /// The sheet is unchanged — `showEvidenceSheet` with the rationale, the
  /// grounding and the grade. What changed is that reaching it no longer costs
  /// the card a labelled row of its own: `Why this suggestion ⓘ` was a line and
  /// a gap on every suggestion, and the ⓘ is the app's word for that everywhere
  /// else.
  Widget _why(BuildContext context, Recommendation rec, Grounding grounding) =>
      HTap(
        onTap: () => showEvidenceSheet(
          context,
          title: kWhyTitle,
          prose: rec.rationale ?? '',
          grounding: grounding,
          grade: rec.gradeLabel,
        ),
        semanticLabel: kWhyLabel,
        child: Icon(
          SolarIconsOutline.infoCircle,
          size: FocusCard.iconSize,
          color: context.family,
        ),
      );

  /// Writes the adoption, then re-reads. Never flips the box on its own: the
  /// tick has to mean "the server has this", not "the tap happened".
  Future<void> _toggle(int id, bool adopted) async {
    setState(() {
      _busy = true;
      _trouble = null;
    });
    try {
      final api = await ref.read(accountApiProvider.future);
      await setRecommendationAdoption(api, id, adopted ? 'dismiss' : 'adopt');
      if (!mounted) {
        return;
      }
      ref.invalidate(todaySnapshotProvider);
      ref.invalidate(recommendationHistoryProvider);
    } on Exception catch (error, stack) {
      AppLog.failure('actions', 'recording an intention', error, stack);
      if (mounted) {
        setState(() => _trouble = apiProblem(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
