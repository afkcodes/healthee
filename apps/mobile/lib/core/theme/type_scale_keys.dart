/// The redesign's type: the three key numbers, the range bar and the verdict.
///
/// Named after `design/mobile-preview/proposal.css`'s rules, the way
/// `type_scale.dart` names `richer.css`'s, and like every role in the scale an
/// alias of a step on `type_ladder.dart`. Colourless: the tone supplies the
/// colour.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The key-number cards and the range bar. Colourless; see the docstring.
abstract final class KeyType {
  /// `.p-key-name` — Recovery, Sleep, Movement.
  static final TextStyle name = TypeLadder.calloutStrong;

  /// `.p-key-value` — the reading.
  static final TextStyle value = TypeLadder.metric;

  /// `.p-key-value small` — its unit.
  static final TextStyle unit = TypeLadder.callout;

  /// `.p-key-line` — the sentence that reads the reading.
  static final TextStyle line = TypeLadder.callout;

  /// `.p-chip` — the verdict in words, mixed case. Small, so
  /// [TypeLadder.caption].
  static final TextStyle chip = TypeLadder.caption;

  /// `.p-range-ends` — the track's two ends. Chart-only: [TypeLadder.micro].
  static final TextStyle rangeEnd = TypeLadder.micro;

  /// `.p-range-usual` — the usual range, named under its band. Chart-only:
  /// [TypeLadder.micro], whose weight is 400 like every micro label.
  static final TextStyle rangeUsual = TypeLadder.micro;
}
