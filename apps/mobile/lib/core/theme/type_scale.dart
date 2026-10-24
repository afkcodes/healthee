/// **v02's type scale: every role named, every one a step on the ladder.**
///
/// `typography.dart` builds the Material [TextTheme] the un-migrated screens are
/// written against; this file names the roles the v02 primitives use. Both are
/// aliases of `type_ladder.dart`: a role here says WHAT the text is (a panel's
/// title, a tile's number), and the ladder says how big that is. The prototype's
/// CSS sizes (8.5, 10, 10.5, 27, 36, 68 px and the rest) are gone; each role
/// was snapped to its ladder step, which is the only size it can now have.
///
/// **Every style here is colourless.** The tone system supplies the colour at the
/// point of use (`context.family`, `context.colors.ink2`), so a style cannot
/// carry a hue that disagrees with the card it is in.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// v02's type scale. Colourless; see the library docstring.
abstract final class TypeScale {
  /// `.page-header h1` — the screen's name.
  static final TextStyle pageTitle = TypeLadder.title1;

  /// `.page-header .date` — the date above it.
  static final TextStyle pageDate = TypeLadder.caption;

  /// The date when it IS the header — Today's one-row head. Between [pageDate]
  /// and [pageTitle] on purpose: it carries the row on its own, and at
  /// [pageTitle]'s size it leaves no width for the strap and the avatar at 320.
  static final TextStyle pageDateStrong = TypeLadder.headline;

  /// `.section-head h2` — a section's name.
  static final TextStyle sectionTitle = TypeLadder.headline;

  /// `.panel-title` — a panel's own title, beside its icon.
  static final TextStyle panelTitle = TypeLadder.calloutStrong;

  /// `.panel-value` — the number a panel exists to show.
  static final TextStyle panelValue = TypeLadder.metric;

  /// `.panel-value > small` — its unit.
  static final TextStyle panelUnit = TypeLadder.caption;

  /// `.panel-note` — the sentence under a panel's chart.
  static final TextStyle panelNote = TypeLadder.caption;

  /// `.panel .text-button` — a panel head's action. Small, so [TypeLadder.caption]:
  /// the ladder has no bold caption.
  static final TextStyle textButton = TypeLadder.caption;

  /// `.summary-tile .tile-title` — a tile's label, in its family colour.
  static final TextStyle tileTitle = TypeLadder.caption;

  /// `.summary-tile strong` — a tile's number.
  static final TextStyle tileValue = TypeLadder.title1;

  /// `.summary-tile .tile-meta` — the qualifier under it.
  static final TextStyle tileMeta = TypeLadder.caption;

  /// `.colour-key` — a chart's axis labels and the legend under a chart.
  /// Chart-only, which is what lets it be [TypeLadder.micro].
  static final TextStyle colourKey = TypeLadder.micro;

  /// `.context-bridge p` — the connective sentence between two panels.
  static final TextStyle bridge = TypeLadder.caption;

  /// `.panel-summary p` — the right-hand qualifier beside a panel's number.
  static final TextStyle panelContext = TypeLadder.caption;

  /// `.twin-panels .panel-title` — a half-width panel's name. Small, so
  /// [TypeLadder.caption]: the ladder has no bold caption.
  static final TextStyle panelTitleCompact = TypeLadder.caption;

  /// `.twin-panels .panel-value`.
  static final TextStyle panelValueCompact = TypeLadder.title1;

  /// `.twin-panels .panel-value > small`.
  static final TextStyle panelUnitCompact = TypeLadder.caption;

  /// `.twin-panels .panel-note`.
  static final TextStyle panelNoteCompact = TypeLadder.caption;

  /// `.panel .stat-label` — the label over a statistic in a `.three` row.
  static final TextStyle statLabel = TypeLadder.caption;

  /// `.panel .three .stat-number`.
  static final TextStyle statValue = TypeLadder.title2;

  /// `.stat-number > span` — its unit.
  static final TextStyle statUnit = TypeLadder.caption;

  /// `.chapter-heading h2` — a chapter's name.
  static final TextStyle chapterTitle = TypeLadder.title2;

  /// `.metric-list strong` — a reading in a metric list.
  static final TextStyle metricListValue = TypeLadder.title2;

  /// `.chapter-nav button` — one jump target.
  static final TextStyle chapterNav = TypeLadder.caption;

  /// `.factor-row` — a model component's name and its score, beside its bar.
  /// Chart-only, which is what lets it be [TypeLadder.micro].
  static final TextStyle factorRow = TypeLadder.micro;

  /// `.dimension-cell > span` — an independent reading's name.
  static final TextStyle dimensionLabel = TypeLadder.caption;

  /// `.dimension-cell strong` — the reading.
  static final TextStyle dimensionValue = TypeLadder.title2;

  /// The same reading in a LIST row rather than a grid cell: a step below
  /// [dimensionValue], because on a row beside a name and a reference the grid's
  /// size stops being a figure and becomes a headline (the owner: *"too big"*).
  static final TextStyle dimensionReading = TypeLadder.headline;

  /// `.dimension-cell small` — the reference under it.
  static final TextStyle dimensionNote = TypeLadder.caption;

  /// `.device-strip` — the strap row under the title.
  static final TextStyle deviceStrip = TypeLadder.caption;

  /// `.relationship-card h3` — an entry point's name.
  static final TextStyle entryTitle = TypeLadder.bodyStrong;

  /// `.relationship-card p` — what it leads to.
  static final TextStyle entryBody = TypeLadder.caption;

  /// `.data-footer` — the closing line.
  static final TextStyle footer = TypeLadder.caption;

  /// `.page-header.detail h1` — a pushed screen's name, smaller than a tab's.
  static final TextStyle detailTitle = TypeLadder.title2;

  /// `.small` — the prototype's one step down from body copy.
  static final TextStyle small = TypeLadder.caption;

  /// `.observation h3` — the finding detail's two-line statement.
  static final TextStyle observationTitle = TypeLadder.headline;

  /// `.observation p` — the caveat under it, the paragraph that says a
  /// correlation is not a cause.
  static final TextStyle observationBody = TypeLadder.caption;

  /// `.tiny-label`, `.list-row small`, `.timeline-item p`, `.stat-label`.
  static final TextStyle tinyLabel = TypeLadder.caption;

  /// `.badge` — a short mixed-case stamp. Small, so [TypeLadder.caption]; an
  /// UPPERCASE stamp is a [TypeLadder.label] instead.
  static final TextStyle badge = TypeLadder.caption;

  /// `.notice strong`.
  static final TextStyle noticeTitle = TypeLadder.calloutStrong;

  /// `.notice p`, `.focus-card p`, `.challenge-card p`.
  static final TextStyle noticeBody = TypeLadder.caption;

  /// `.focus-card .focus-title` — a mixed-case eyebrow. Small, so
  /// [TypeLadder.caption].
  static final TextStyle focusEyebrow = TypeLadder.caption;

  /// `.focus-card h3` — the focus card's heading.
  static final TextStyle focusTitle = TypeLadder.calloutStrong;

  /// `.sleep-hero .hero-number`.
  static final TextStyle heroNumber = TypeLadder.display;

  /// `.hero-number .duration-unit`.
  static final TextStyle heroUnit = TypeLadder.title1;

  /// `.metric-hero .hero-number` — the metric screen's hero figure.
  static final TextStyle metricHeroNumber = TypeLadder.display;

  /// `.hero-number .unit` — its unit.
  static final TextStyle metricHeroUnit = TypeLadder.title1;

  /// `.list-row strong`, `.timeline-item h3`, `.journal-strip h3`,
  /// `.check-action strong`.
  static final TextStyle rowTitle = TypeLadder.calloutStrong;

  /// `.challenge-card h3`.
  static final TextStyle challengeTitle = TypeLadder.headline;

  /// `.button`.
  static final TextStyle buttonLabel = TypeLadder.calloutStrong;

  /// `.text-button` — the page-level link.
  static final TextStyle textLink = TypeLadder.calloutStrong;

  /// `.coach-intro p` and `.coach-message`.
  static final TextStyle coachBody = TypeLadder.caption;

  /// `.form-note`, `.journal-strip p`.
  static final TextStyle formNote = TypeLadder.caption;

  /// `.field input` — what is typed into a field.
  static final TextStyle inputText = TypeLadder.body;
}
