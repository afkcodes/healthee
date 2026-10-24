/// Sleep's four chapters and the pinned nav that jumps between them
/// (`design/mobile-preview/proposal-sleep.js::jump`): `Last night`,
/// `This week`, `Longer view`, `Your patterns`.
///
/// The anchors are the screen's own chapter headings, keyed; the jump is the
/// one Today uses (`chapter_jump.dart`). A chapter the day does not draw (no
/// patterns on a past day) has no button rather than a button to nowhere.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/shared/v02/chapter.dart';
import 'package:healthee/shared/v02/chapter_jump.dart';

/// The proposal's part titles.
const String kSleepWeekChapter = 'This week';
const String kSleepPatternsChapter = 'In your own data';

/// The four anchors.
class SleepChapters {
  final GlobalKey night = GlobalKey(debugLabel: 'sleep.chapter.night');
  final GlobalKey week = GlobalKey(debugLabel: 'sleep.chapter.week');
  final GlobalKey longer = GlobalKey(debugLabel: 'sleep.chapter.longer');
  final GlobalKey patterns = GlobalKey(debugLabel: 'sleep.chapter.patterns');
}

/// `.p-jump`, wired to [chapters].
class SleepChapterNav extends StatelessWidget {
  /// [patterns] is false when the screen draws no patterns chapter.
  const SleepChapterNav({
    required this.chapters,
    this.patterns = true,
    super.key,
  });

  final SleepChapters chapters;
  final bool patterns;

  @override
  Widget build(BuildContext context) {
    final targets = <(String, GlobalKey)>[
      ('Last night', chapters.night),
      ('This week', chapters.week),
      ('Longer view', chapters.longer),
      if (patterns) ('Your patterns', chapters.patterns),
    ];
    return ToneScope(
      tone: Tone.sleep,
      child: ChapterNav(<ChapterTarget>[
        for (final (label, key) in targets)
          ChapterTarget(label, () => jumpToChapter(context, key)),
      ]),
    );
  }
}
