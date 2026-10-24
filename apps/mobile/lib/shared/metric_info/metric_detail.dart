/// What a card used to print on its own face, on its way to the ⓘ sheet.
///
/// ## The defect this type exists to fix
///
/// The owner, on the installed v02 build: *"that reference pill can we remove
/// those from cards please info sheets are for that"* and *"all these
/// unnecessary Sleep regularity long text and other texts in pills in
/// evrycard"*. Two reports, one shape: a card carrying its own **method and
/// provenance** — the reference it is read against, the sources behind it, the
/// paragraph explaining what the bars are — inline, under the number.
///
/// The ⓘ sheet already existed for exactly that material. What was missing was a
/// way to get a card's OWN, payload-derived provenance into it: [MetricInfo] is a
/// compile-time map, and `health.researchNotes` / `mvpa.weekTarget` /
/// `vo2max.standardErrorSource` are things only the payload knows.
///
/// So a card hands its head one of these, the head hands it to the ⓘ, and the
/// sheet renders it beside the static explainer. One destination for every kind
/// of long-form method text, which is what the owner asked for.
///
/// ## The rule that makes this a move rather than a deletion
///
/// **Nothing may be dropped on the way.** A claim whose grounding becomes
/// unreachable is a regression, not a tidy-up: it leaves a number on screen with
/// its licence removed. So every card that loses a citation must gain a reachable
/// ⓘ carrying it, and `MetricInfoDot` therefore draws itself for a card with
/// **no explainer at all** as long as this bundle is non-empty — an ⓘ that opens
/// a sheet holding only the sources is still the sources, reachable.
/// `test/features/card_provenance_test.dart` enumerates the cards and asserts it.
///
/// ## What does NOT belong here
///
/// A caveat signpost, a withheld reason, clinical routing, "not a diagnosis",
/// and the naming of the instrument behind a reading all stay **on the card**.
/// Those are not method detail; they are the qualifications that make the number
/// on the card readable at all, and this project has already fixed one round of
/// hiding them (`states/caveat_disclosure.dart`). The line is: text that
/// *teaches or describes* moves; text that *qualifies the number beside it*
/// stays.
library;

import 'package:flutter/widgets.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/data/honesty/disclosure.dart';

/// One card's own provenance, bound for its ⓘ sheet.
@immutable
class MetricDetail {
  /// Builds a bundle. Every field is optional; an empty one draws no ⓘ.
  const MetricDetail({
    this.title,
    this.notes = const <String>[],
    this.personalFindings = const <String>[],
    this.unresolved = const <String>[],
    this.grade,
    this.source,
    this.references = const <String>[],
    this.method = const <String>[],
    this.disclosures = const <Disclosure>[],
    this.disclosuresLabel,
    this.figure,
    this.action,
  });

  /// The bundle for a card whose prose was written by a model.
  ///
  /// Takes the [Grounding] **whole** rather than its three lists, and that is
  /// the point of the constructor existing at all. A card routing its sources to
  /// its ⓘ has to carry three different kinds of thing — the corpus, this
  /// owner's own history, and the brackets we could not read — and only the
  /// first of them flatters the app. There is no parameter here for two of the
  /// three, so a call site cannot keep the sources and quietly leave the
  /// single-subject framing or an unreadable citation behind.
  factory MetricDetail.grounded(
    Grounding grounding, {
    String? title,
    String? grade,
    String? source,
    List<String> references = const <String>[],
    List<String> method = const <String>[],
    List<Disclosure> disclosures = const <Disclosure>[],
    String? disclosuresLabel,
    Widget? figure,
    MetricAction? action,
  }) => MetricDetail(
    title: title,
    notes: grounding.noteIds,
    personalFindings: grounding.personalFindings,
    unresolved: grounding.unresolved,
    grade: grade,
    source: source,
    references: references,
    method: method,
    disclosures: disclosures,
    disclosuresLabel: disclosuresLabel,
    figure: figure,
    action: action,
  );

  /// The bundle a card with nothing to disclose passes. Also the default.
  static const MetricDetail none = MetricDetail();

  /// The sheet's heading when this card has no [MetricInfo] entry to name it.
  ///
  /// Null is fine when there IS an explainer — the explainer's own title wins,
  /// because two names for one metric is the drift `metric_names.dart` exists to
  /// prevent.
  final String? title;

  /// The corpus note ids the payload sent for THIS card, e.g.
  /// `sleep_health.research_notes`. Merged with the explainer's own in the sheet
  /// and de-duplicated, so a note cited by both is one chip.
  final List<String> notes;

  /// `[personal_finding:<name>]` names the card's prose cited.
  ///
  /// Kept apart from [notes] all the way to the sheet. A pattern found by
  /// searching one owner's history is not a literature review, and the sheet
  /// draws it with `kSingleSubjectFraming` under it — the one wording, shared
  /// with `findings_section.dart`, because a caveat written twice is a caveat
  /// that can be softened in one place.
  final List<String> personalFindings;

  /// Bracketed runs in the card's prose that resolved to no citation at all.
  ///
  /// **Carried, never dropped.** A citation we cannot read is our failure, not a
  /// fact about the owner's body; hiding it would let the app delete a claim's
  /// grounding on a guess. The marker also stays in the sentence — see
  /// `data/honesty/citations.dart`.
  final List<String> unresolved;

  /// An evidence grade the payload sent for this card's claim, or null.
  ///
  /// **Never inferred from an id**, here or in the sheet. `citation_row.dart`
  /// has the argument: deriving one would rebuild the split that once published
  /// a `Myth` note as `Established` (#83), in the layer with no access to the
  /// corpus. A recommendation's `evidence_grade` and a coach answer's
  /// `grade_floor` are the live cases — both computed by the server from the
  /// notes actually cited.
  final String? grade;

  /// A human sentence about the source, when the payload carried one —
  /// VO₂max's `see_source` is the live example. Rendered verbatim.
  final String? source;

  /// The published references the card's figures are read against —
  /// `Efficiency — reference ≥ 85%`, `Active minutes — reference 150 min/week`.
  ///
  /// These were the "reference pills" the owner asked us to take off the cards.
  /// They are **kept**, not deleted: a cutoff with no source is a number this
  /// app made up, and the sheet is where a reader who wants it can find it.
  final List<String> references;

  /// The explanatory prose that used to sit under the card's chart — what the
  /// bars are, what the colours mean, how the model divides.
  final List<String> method;

  /// Server disclosures too long to print on the card: the withheld
  /// `consequence` and its per-term messages, and the permanent exclusions.
  ///
  /// The card keeps a short signpost naming them; this is the full text, one tap
  /// behind it. Same shape as the caveat fix (`states/caveat_disclosure.dart`).
  final List<Disclosure> disclosures;

  /// What to call [disclosures] on the sheet. Defaults in the sheet itself.
  final String? disclosuresLabel;

  /// A picture the sheet draws above its text blocks: the ladder a number was
  /// read off, the rail it sits on. Drawn at rest, never animated.
  final Widget? figure;

  /// One button at the foot of the heading: where the owner can go from here.
  /// For a metric with a history the sheet's own history button is enough.
  final MetricAction? action;

  /// True when there is nothing here worth an ⓘ of its own.
  bool get isEmpty =>
      notes.isEmpty &&
      personalFindings.isEmpty &&
      unresolved.isEmpty &&
      grade == null &&
      source == null &&
      references.isEmpty &&
      method.isEmpty &&
      disclosures.isEmpty &&
      figure == null &&
      action == null;

  /// The negation, for a call site that reads better positively.
  bool get isNotEmpty => !isEmpty;

  /// This bundle with different disclosures.
  ///
  /// Only the two disclosure fields, because only they are merged: `Panel`
  /// publishes the caveats of the reading a card is about, and its head folds
  /// them into whatever the call site already gave. A general `copyWith` would
  /// invite a card to rewrite its own grade or its own sources, which is the
  /// one thing a bundle of provenance must not let a caller do.
  MetricDetail withDisclosures(
    List<Disclosure> disclosures, {
    String? disclosuresLabel,
  }) => MetricDetail(
    title: title,
    notes: notes,
    personalFindings: personalFindings,
    unresolved: unresolved,
    grade: grade,
    source: source,
    references: references,
    method: method,
    disclosures: disclosures,
    disclosuresLabel: disclosuresLabel ?? this.disclosuresLabel,
    figure: figure,
    action: action,
  );
}

/// A sheet's one button: its words and where it goes.
///
/// The sheet closes itself before calling [onTap], so the callback may push a
/// route from the screen that opened the sheet.
@immutable
class MetricAction {
  /// Builds the button.
  const MetricAction(this.label, this.onTap);

  /// The button's words.
  final String label;

  /// Where it goes.
  final VoidCallback onTap;
}
