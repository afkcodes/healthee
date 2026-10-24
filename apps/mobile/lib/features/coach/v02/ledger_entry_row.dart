/// One checked yes: a verdict glyph, the title, and what the strap saw.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// The line under a no-data entry that has no measurement.
const String kLedgerNoReading = 'No strap reading that night';

/// The line under an entry the strap cannot see.
const String kLedgerUncheckable =
    'The strap cannot see this. Log it in the journal and it counts.';

/// The detail under [entry]'s title: the response's own measurement, else a
/// neutral line fixed by the verdict, else nothing.
String? ledgerDetail(LedgerEntry entry) {
  final measured = entry.measured.text;
  if (measured != null) {
    return measured;
  }
  return switch (entry.verdict) {
    LedgerVerdict.noData => kLedgerNoReading,
    LedgerVerdict.uncheckable => kLedgerUncheckable,
    _ => null,
  };
}

/// How a verdict is judged: done is better, missed worse, partial watch, and
/// no proof draws no colour.
ReadingState ledgerState(LedgerVerdict verdict) => switch (verdict) {
  LedgerVerdict.done => ReadingState.better,
  LedgerVerdict.partial => ReadingState.watch,
  LedgerVerdict.missed => ReadingState.worse,
  LedgerVerdict.noData || LedgerVerdict.uncheckable => ReadingState.noData,
};

/// The row.
class LedgerEntryRow extends StatelessWidget {
  /// Draws [entry].
  const LedgerEntryRow({required this.entry, super.key});

  /// The entry.
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detail = ledgerDetail(entry);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VerdictGlyph(verdict: entry.verdict),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.title,
                style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
              ),
              if (detail != null)
                Text(
                  detail,
                  style: TypeLadder.callout.copyWith(color: colors.ink2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A 24 px glyph for a verdict: check, x, a dash for half credit, or a question
/// mark for no proof.
class VerdictGlyph extends StatelessWidget {
  /// The glyph for [verdict].
  const VerdictGlyph({required this.verdict, super.key});

  /// Glyph box.
  static const double size = 24;

  /// The verdict.
  final LedgerVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final colour = ledgerState(verdict).colourIn(colors);
    final (IconData? icon, String label) = switch (verdict) {
      LedgerVerdict.done => (Icons.check_rounded, 'Done'),
      LedgerVerdict.partial => (Icons.remove_rounded, 'Partly done'),
      LedgerVerdict.missed => (Icons.close_rounded, 'Missed'),
      LedgerVerdict.noData => (null, 'No reading'),
      LedgerVerdict.uncheckable => (null, 'Not checkable'),
    };
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: icon == null
                ? Text('?', style: TypeLadder.headline.copyWith(color: colour))
                : Icon(icon, size: size, color: colour),
          ),
        ),
      ),
    );
  }
}
