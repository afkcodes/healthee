/// "Why this" evidence: a chip naming the note and its grade, and the program's
/// own `why` as the claim. The chip's id comes from the rungs' research notes
/// and its grade from the corpus table; no id, or an id with no grade, draws no
/// grade rather than a guessed one.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/shared/format/note_grades.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The chip's words: `Probable · mvpa_minutes_mortality`.
String evidenceChipText(String noteId) {
  final grade = kNoteGrades[noteId];
  return grade == null ? noteId : '$grade · $noteId';
}

/// The card.
class ProgramEvidenceCard extends StatelessWidget {
  /// [why] is the program's own sentence; [noteId] the first real note behind it.
  const ProgramEvidenceCard({
    required this.why,
    required this.noteId,
    this.onOpen,
    super.key,
  });

  /// The claim, citation markers stripped.
  final String why;

  /// The note the chip names, or null for no chip.
  final String? noteId;

  /// Opens the sources sheet.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final id = noteId;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (id != null) ...<Widget>[
            GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: colors.surface2,
                  shape: hSquircle(Radii.badge),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.md,
                    vertical: Insets.xs,
                  ),
                  child: Text(
                    evidenceChipText(id),
                    style: TypeLadder.caption.copyWith(color: colors.ink2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Insets.md),
          ],
          Text(
            parseGrounded(why).prose.trim(),
            style: TypeLadder.body.copyWith(color: colors.ink),
          ),
        ],
      ),
    );
  }
}
