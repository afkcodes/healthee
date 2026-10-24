/// **v02's type scale, second half: the forms, rows and prose.**
///
/// Split out of `type_scale.dart` at the 400-line gate (Standards §1). That
/// file's one reason to change is a **panel's** typography, and this one's is a
/// **form's**: the supporting screens are almost entirely list rows, switches,
/// fields and sentences. Each role is an alias of a step on `type_ladder.dart`.
///
/// **Every style here is colourless**, for the reason `type_scale.dart` gives:
/// the colour arrives at the point of use, so a style cannot carry a hue that
/// disagrees with the container it is drawn in.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The form and list half of v02's scale. Colourless; see the library docstring.
abstract final class FormType {
  /// `h1` — the one display title, on Welcome.
  static final TextStyle displayTitle = TypeLadder.title1;

  /// `.page-header.detail h1` — a sub-screen's name, beside its back button.
  static final TextStyle detailTitle = TypeLadder.title2;

  /// `h2` — a centred heading on the device and pairing screens, and the brand.
  static final TextStyle heading2 = TypeLadder.title2;

  /// `h3` — a card's own heading.
  static final TextStyle heading3 = TypeLadder.body;

  /// `body` — the default. Rare on these screens; almost everything is smaller.
  static final TextStyle body = TypeLadder.callout;

  /// `small`, `.small` — the sentence under a heading.
  static final TextStyle small = TypeLadder.caption;

  /// `.list-row strong` — a settings row's name.
  static final TextStyle rowTitle = TypeLadder.calloutStrong;

  /// `.list-row small` — what the row leads to. Wraps; see `list_row.dart`.
  static final TextStyle rowSubtitle = TypeLadder.caption;

  /// `.toggle-row strong` — a switch's name.
  static final TextStyle toggleTitle = TypeLadder.calloutStrong;

  /// `.toggle-row p` — what turning it on does.
  static final TextStyle toggleBody = TypeLadder.caption;

  /// `.field` — a field's label.
  static final TextStyle fieldLabel = TypeLadder.calloutStrong;

  /// `.field input` — what is typed into it. The prototype's 16 px was there to
  /// stop iOS Safari zooming a focused web field; a Flutter field is not a web
  /// page and does not zoom, so it is [TypeLadder.body] like other prose.
  static final TextStyle fieldInput = TypeLadder.body;

  /// `.field small` — the note under a field.
  static final TextStyle fieldHint = TypeLadder.caption;

  /// `.form-note` — the sentence under a whole form.
  static final TextStyle formNote = TypeLadder.caption;

  /// `.button` — every filled and outlined button's label.
  static final TextStyle button = TypeLadder.calloutStrong;

  /// `.text-button` — a link with an arrow.
  static final TextStyle linkButton = TypeLadder.calloutStrong;

  /// `.badge` — a short mixed-case stamp beside a value. Small, so
  /// [TypeLadder.caption].
  static final TextStyle badge = TypeLadder.caption;

  /// `.notice strong` — the headline of a banner.
  static final TextStyle noticeTitle = TypeLadder.calloutStrong;

  /// `.notice p` — its sentence.
  static final TextStyle noticeBody = TypeLadder.caption;

  /// `.stat-label` — the label over a statistic.
  static final TextStyle statLabel = TypeLadder.caption;

  /// `.stat-number` — the statistic.
  static final TextStyle statNumber = TypeLadder.title1;

  /// `.stat-number > span` — its unit.
  static final TextStyle statUnit = TypeLadder.caption;

  /// `.timeline-item h3` — one step of the pairing journey.
  static final TextStyle timelineTitle = TypeLadder.callout;

  /// `.timeline-item p` — what that step does.
  static final TextStyle timelineBody = TypeLadder.caption;

  /// `.timeline-item .node` — the number in the circle.
  static final TextStyle timelineNode = TypeLadder.caption;

  /// `.theme-option` — one of Light · Dark · System.
  static final TextStyle themeOption = TypeLadder.caption;

  /// `.sync-stages > div` — one stage of strap → phone → server.
  static final TextStyle syncStage = TypeLadder.caption;

  /// `.observation h3` — one row of the data-freshness list.
  static final TextStyle observationTitle = TypeLadder.headline;

  /// `.observation p` — how old that reading is.
  static final TextStyle observationBody = TypeLadder.caption;
}
