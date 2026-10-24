/// The evidence line under a claim: which sources back it, and how strongly.
///
/// ## Grades are shown only where the server sent one
///
/// This is the first rule the file exists to hold. `/api/today` carries a real
/// evidence grade in exactly one place — `recommendations[].evidence_grade`,
/// which `jobs/recs.py::_provable_grade` has already replaced with the weakest
/// grade among the notes the rec actually cites. Everywhere else the payload
/// carries `research_notes`: **citation ids, with no grade attached**.
///
/// So [grade] is optional and is never inferred from an id. Deriving one would
/// rebuild the `evidence_grade`-vs-`grade` split that once published a `Myth`
/// note as `Established` (#83) — a second grade that can disagree with the
/// first — and it would do it in the one layer with no access to the corpus.
///
/// ## A chip is a SOURCE NAME, never an id
///
/// It used to be the id: `recovery_readiness` under the gauge,
/// `cardio_load_trimp` on Activity. Those are internal identifiers, and a
/// snake_case string on a health screen is a log line where a source should be.
/// `shared/format/note_names.dart` resolves each to the corpus's OWN name — a
/// transcription, not a second opinion — and the id stays reachable in the
/// chip's tooltip for anyone debugging. An id this build cannot name keeps its
/// id and is logged: showing it is honest about the app being older than the
/// corpus, and inventing a title for it would not be.
///
/// Ids are rendered as chips rather than hidden behind a "sources" toggle,
/// because brief §4.5 is explicit: sources are a feature, not clutter. They are
/// not tappable yet — the note reader is a later screen — and a chip that looks
/// tappable and is not would be its own small lie, so they are drawn as stamps.
///
/// ## A personal finding is NOT a research note, and does not look like one
///
/// `[personal_finding:<name>]` is a pattern found in this one owner's history —
/// single-subject, observational, discovered by searching many metric pairs. It
/// arrives in the same brackets as a corpus citation and it is not one. So it
/// gets its own stamp, its own label, and [kSingleSubjectFraming] underneath:
/// the same sentence `findings_section.dart` puts above the findings themselves,
/// because the framing has to travel with the claim rather than live on one
/// screen that happens to show it.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/format/note_names.dart';

/// What a claim from the owner's own data is, said plainly.
///
/// Lives here rather than in the findings section because two surfaces now make
/// the claim — the findings list and any cited `[personal_finding:…]` — and one
/// sentence in two files is one sentence that can be softened in one of them.
const String kSingleSubjectFraming =
    'Single-subject and observational: these are patterns found in your '
    'history, not effects shown in a trial. They say what moved together, '
    'never what caused what.';

/// Ids already reported as unnameable, so one unknown note is one log line and
/// not one per frame.
final Set<String> _warnedIds = <String>{};

/// The sources behind a claim, with an optional evidence grade.
class CitationRow extends StatelessWidget {
  /// [noteIds] are corpus ids; [grade] is shown only when the server sent one.
  const CitationRow({
    required this.noteIds,
    this.personalFindings = const <String>[],
    this.unresolved = const <String>[],
    this.grade,
    this.source,
    super.key,
  });

  /// The research-note ids licensing the claim above.
  final List<String> noteIds;

  /// `[personal_finding:<name>]` names cited by the claim above. Never mixed in
  /// with [noteIds] — see the library docstring.
  final List<String> personalFindings;

  /// Bracketed runs that resolved to no citation at all. Announced, never
  /// silently dropped.
  final List<String> unresolved;

  /// `Established` / `Probable`, when the payload carried a grade. Never guessed.
  final String? grade;

  /// A human sentence about the source, when the payload carried one — VO₂max's
  /// `see_source` ("Carrier 2023: MAPE 6.85% vs lab CPET") is the live example.
  /// Rendered verbatim; it is the server's calibrated wording.
  final String? source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    if (noteIds.isEmpty &&
        personalFindings.isEmpty &&
        unresolved.isEmpty &&
        grade == null &&
        source == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (grade case final String label) _GradeStamp(label: label),
            for (final id in noteIds) _NoteStamp(id: id),
            for (final name in personalFindings) _PersonalStamp(name: name),
          ],
        ),
        if (personalFindings.isNotEmpty) ...[
          const SizedBox(height: Insets.xs),
          Text(
            kSingleSubjectFraming,
            style: text.labelSmall?.copyWith(color: colors.ink2),
          ),
        ],
        if (source case final String sentence) ...[
          const SizedBox(height: Insets.xs),
          Text(sentence, style: text.labelSmall?.copyWith(color: colors.ink2)),
        ],
        if (unresolved.isNotEmpty) ...[
          const SizedBox(height: Insets.xs),
          _UnresolvedNotice(markers: unresolved),
        ],
      ],
    );
  }
}

/// The grade, as a word. Accent-outlined, never filled — it is a qualification
/// on a claim, not a badge to be pleased about.
class _GradeStamp extends StatelessWidget {
  const _GradeStamp({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.accent, width: hairline),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.accent, letterSpacing: 0.7),
      ),
    );
  }
}

/// One corpus source, named, drawn as a quiet stamp.
class _NoteStamp extends StatelessWidget {
  const _NoteStamp({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = noteName(id);
    if (name == null && _warnedIds.add(id)) {
      // Once per id per run. A note the corpus has and this build has not is the
      // app being behind, and it is worth a line — it is silently unreadable on
      // screen otherwise.
      AppLog.warning('citations', 'no name for research note "$id"');
    }
    return Tooltip(
      // The id, reachable and not shown. Debugging a citation means knowing
      // which note it is; reading the screen does not.
      message: id,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: colors.surface2,
          border: Border.all(color: colors.line2, width: hairline),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Text(
          name ?? id,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.ink2),
        ),
      ),
    );
  }
}

/// One pattern from the owner's own history. Outlined rather than filled, and
/// labelled, so it cannot be read as a corpus source at a glance.
class _PersonalStamp extends StatelessWidget {
  const _PersonalStamp({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: 'personal_finding:$name',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.line, width: hairline),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Text(
          'your own data · ${metricName(name)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.ink2),
        ),
      ),
    );
  }
}

/// A bracket that grounded nothing. Said out loud, in ordinary ink.
///
/// **No colour.** A broken citation is our failure, not a fact about the owner's
/// body, and `README.md`'s rule is that `fav`/`unf`/`alert` are the only colours
/// allowed to say something about a reading — `ErrorState` sets the same
/// precedent by being greyscale. Loud here means *stated*, not tinted.
///
/// The marker's own text is quoted rather than paraphrased, because the whole
/// point is that we could not tell what it was meant to be.
class _UnresolvedNotice extends StatelessWidget {
  const _UnresolvedNotice({required this.markers});

  final List<String> markers;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final quoted = markers.map((marker) => '“$marker”').join(', ');
    return Text(
      'Left as written: $quoted ${markers.length == 1 ? 'is' : 'are'} in the '
      'brackets a citation uses, and ${markers.length == 1 ? 'it names' : 'they '
          'name'} no source we can resolve. Nothing was removed from the '
      'sentence — an unreadable reference is worth seeing, and quietly deleting '
      'one would hide a claim losing its grounding.',
      style: text.labelSmall?.copyWith(color: colors.ink2),
    );
  }
}
