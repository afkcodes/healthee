/// `Patterns → small changes` — fitness, the day's own log, and the way out.
///
/// `screens-overview.js`, after the second chapter: the VO₂max panel with its
/// rail, the daily journal, and the two relationship cards that end the screen.
///
/// ## The rail names its instrument, because VO₂max has three
///
/// `derive/vo2max_tier.py` writes one metric from a graded fit, a heart-rate
/// reserve inversion, or Jurca's non-exercise model, and sends which one it used
/// (`method`, `see_source`, `measured_as_of`, `n_sessions`). All of it is on the
/// panel. An estimate that does not say how it was made is the failure the whole
/// tier system exists to stop, and 43.0 from a graded session is a different
/// claim from 43.0 from a questionnaire.
///
/// `standard_error` is drawn as an error magnitude on the rail and named as one:
/// `Vo2maxRail` calls it an error magnitude, not a confidence interval, because
/// it is a model's published SEE and not an interval computed for this owner.
///
/// ## The journal counts what was logged and never scores it
///
/// Caffeine, meditation and an open fast are a **log**, not a judgement. The
/// panel prints the counts and the link to add another, and says nothing about
/// whether the day was a good one.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/journal/log_kind.dart';
import 'package:healthee/data/models/routine.dart';
import 'package:healthee/data/models/vo2max.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/instruments/vo2max_rail.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// `Cardiorespiratory fitness` — the estimate, its rail, and its instrument.
class FitnessPanel extends StatelessWidget {
  /// [vo2max] is the payload's block.
  const FitnessPanel({
    required this.vo2max,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Cardiorespiratory fitness';

  /// The estimate and everything the server said about how it was made.
  final Vo2max vo2max;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the fitness screen.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.fitness,
      label: 'VO₂max · estimate',
      // The server's `method_caveat` is 300+ characters of prose about how this
      // number was made. Printed inline it is the essay the owner asked us to
      // stop printing (`today_caveat_surface_test.dart`); dropped it is a
      // qualification on a number, silently lost. So it travels as a
      // disclosure: a counted signpost inside this card, and the full sentence
      // one tap behind it — which is what that machinery is for.
      caveats: <Disclosure>[vo2max.methodDisclosure],
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.graphUp,
        infoKey: 'vo2max',
        detail: MetricDetail(
          references: <String>[
            if (vo2max.medianForAge case final double median)
              'Age/sex reference ${median.toStringAsFixed(1)} ml/kg/min',
          ],
          notes: vo2max.researchNotes,
          source: vo2max.standardErrorSource,
        ),
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            vo2max.estimate.toStringAsFixed(1),
            unit: 'ml/kg/min',
            context_: _instrument(vo2max),
          ),
          RevealOnce(
            id: 'today.vo2max-rail',
            registry: reveals,
            builder: (context, t) => Vo2maxRail(
              estimate: vo2max.estimate,
              medianForAge: vo2max.medianForAge,
              errorMagnitude: vo2max.standardErrorMlKgMin,
              progress: t,
            ),
          ),
          PanelNote(_qualifiers(vo2max)),
        ],
      ),
    );
  }

  /// What still qualifies the figure after the reference moved to the ⓘ.
  ///
  /// Both survivors are **about this number**, not about the metric: how many
  /// sessions are behind it, and what the ± beside it is not. The second is the
  /// live example of the line this sweep must not cross — an error magnitude
  /// silently read as a confidence interval is a reader mis-reading the
  /// uncertainty of a number they are looking at, so the correction stays where
  /// the number is.
  ///
  /// Built from the payload's structured fields rather than from its prose, so
  /// a server that lengthens `method_caveat` cannot lengthen this card.
  static String _qualifiers(Vo2max vo2max) {
    final sessions = vo2max.sessionCount;
    return <String>[
      if (sessions != null && sessions > 0)
        '$sessions ${sessions == 1 ? 'session' : 'sessions'}',
      if (vo2max.standardErrorMlKgMin != null)
        'error magnitude is not a confidence interval',
    ].join(' · ');
  }

  /// `VO₂max estimate` over the method that produced it, in the server's words.
  ///
  /// The measurement day appears only when it is not the day the estimate is
  /// offered for. A graded session speaks for up to fourteen days, so without
  /// this line the panel read as today's fitness over a run recorded a fortnight
  /// ago — the freshness horizon's own argument depends on saying which day.
  static String _instrument(Vo2max vo2max) {
    final sessions = vo2max.sessionCount;
    return <String>[
      'VO₂max estimate',
      // Named, never the raw tier id: `gps_graded` on a health screen is a log
      // line where an instrument's name belongs.
      'Read by ${methodLabel(vo2max.method)}',
      if (vo2max.measuredEarlier case final String day)
        'Measured ${prettyDate(day)}',
      if (sessions != null && sessions > 0)
        '$sessions ${sessions == 1 ? 'session' : 'sessions'}',
    ].join('\n');
  }
}

/// `Daily journal` — what was logged today, counted and not judged.
///
/// The counts come from three places and each is drawn once: `workouts` from the strap,
/// `meditation_today` and `open_fast` from their own keys, and every OTHER manual-entry
/// kind from `logs_summary` via [Routine.otherLogs]. The last of those was dropped at the
/// client boundary, which is why a caffeine-only day used to render nothing at all.
class JournalPanel extends StatelessWidget {
  /// [routine] is the payload's block. An empty one draws nothing at all —
  /// `today_body.dart` holds that gate.
  const JournalPanel({required this.routine, this.onAdd, super.key});

  /// The prototype's title.
  static const String title = 'Daily journal';

  /// The prototype's own line under the counts.
  static const String note =
      'Your everyday context, alongside the strap’s measurements.';

  /// Today's logged sessions, meditation and fast.
  final Routine routine;

  /// Opens the log sheet, when there is one.
  final VoidCallback? onAdd;

  /// `30 min · strap`, dropping either half the server did not send.
  static String sessionDetail(RoutineEvent session) => <String>[
    if (session.durationMin case final int minutes) '$minutes min',
    if (session.source case final String source) source,
  ].join(' · ');

  /// A logged kind's own name — the app's word for it, or the server's id.
  ///
  /// `LogKind` is the vocabulary the journal sheet writes with, so a kind it knows is
  /// named the same way here as where it was entered. A kind it does not know keeps the
  /// server's id rather than being prettified into prose — `metric_names.dart` makes the
  /// same argument: an id is honest about being one, an invented name is not.
  static String logTitle(LogTally tally) {
    for (final kind in LogKind.values) {
      if (kind.name == tally.kind) {
        return kind.label;
      }
    }
    return tally.kind;
  }

  /// `240 mg · 2 entries`, dropping the amount for a kind that carries none.
  ///
  /// The unit is `LogKind`'s, never guessed: a kind the app does not know shows its count
  /// alone rather than a bare number under no unit. `mood`, `symptom` and `habit` have no
  /// unit by design and their totals are meaningless, so only the count is drawn.
  static String logDetail(LogTally tally) {
    final entries = '${tally.count} ${tally.count == 1 ? 'entry' : 'entries'}';
    for (final kind in LogKind.values) {
      if (kind.name != tally.kind) {
        continue;
      }
      if (kind.unit case final String unit) {
        final amount = tally.total == tally.total.roundToDouble()
            ? tally.total.round().toString()
            : tally.total.toStringAsFixed(1);
        return '$amount $unit · $entries';
      }
      return entries;
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.stress,
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.book,
        actionLabel: onAdd == null ? null : 'Add a moment',
        onAction: onAdd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StatRow(<Stat>[
            if (routine.workouts.isNotEmpty)
              Stat('Sessions', '${routine.workouts.length}'),
            if (routine.meditationCount > 0)
              Stat('Meditation', '${routine.meditationMinutes}', unit: 'min'),
            if (routine.openFast != null)
              Stat(
                'Fasting',
                '${routine.openFast!.elapsedMin ~/ 60}',
                unit: 'h',
              ),
          ]),
          // Each session by name, with the instrument that recorded it. The
          // counts alone would lose the one thing the block carries that
          // nothing else does — that a run came off the strap and a meditation
          // was typed in, which is the difference between a measurement and a
          // note to self.
          for (final session in routine.workouts)
            _LoggedRow(
              title: session.type ?? 'Session',
              detail: sessionDetail(session),
            ),
          if (routine.meditationCount > 0)
            _LoggedRow(
              title: 'Meditation',
              detail:
                  '${routine.meditationMinutes} min · '
                  '${routine.meditationCount} '
                  '${routine.meditationCount == 1 ? 'session' : 'sessions'}',
            ),
          if (routine.openFast case final OpenFast fast)
            _LoggedRow(
              title: 'Fasting, still open',
              detail: durationText(fast.elapsedMin),
            ),
          // Everything else the day carried, from `routine.logs_summary`. Without it a
          // day whose only entry was caffeine drew no panel at all while the wire was
          // reporting that entry (audit C6). The kinds with a block of their own above
          // are excluded by `Routine.otherLogs`, not filtered again here.
          for (final tally in routine.otherLogs)
            _LoggedRow(title: logTitle(tally), detail: logDetail(tally)),
          const PanelNote(note),
        ],
      ),
    );
  }
}

/// One logged thing: what it was, and how much of it.
class _LoggedRow extends StatelessWidget {
  const _LoggedRow({required this.title, required this.detail});

  /// The gap above each row.
  static const double gap = 10;

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: gap),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: TypeScale.panelNote.copyWith(color: colors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(detail, style: TypeScale.panelNote.copyWith(color: colors.ink2)),
        ],
      ),
    );
  }
}
