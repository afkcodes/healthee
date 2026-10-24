/// A chapter title takes the width it needs; the rule takes what is left.
///
/// The owner, comparing the prototype with the installed app: *"these header
/// texts in web looks right but in app its getting clipped of or truncated"*.
///
/// `.chapter-heading h2` is `width: auto` and only `.grow` is `flex: 1`, so the
/// title takes its own width and the rule fills the remainder out to the edge.
/// The port wrote `Flexible(title)` beside `Expanded(rule)` — **both default to
/// `flex: 1`** — so `RenderFlex` split the free space equally: on a 390 px phone
/// the title's half is about 148 px and `Last night → today` at 20 px/700/-0.6
/// needs about 160, so every chapter title ellipsized while the rule ran half
/// the row.
///
/// ## The two things this asserts, and why they are the right two
///
/// The bug has two symptoms and a fix that only removes one is still broken:
///
///   * a title that fits is **cut** — because it was handed half the row;
///   * the rule is **short of the edge** — because it was handed the other half
///     and a loose `Flexible` never gives its surplus back.
///
/// The second is the one that discriminates at any width and in any font: with
/// the equal split, `Expanded` gets exactly `free / 2`, so the row's children
/// end before the content edge. `rule.right == content edge` is false under the
/// bug and true under the fix, for every title and every width.
///
/// ## Two things about the harness
///
/// `flutter test` pumps an **800 px** viewport, which is wider than any handset,
/// and the defect is invisible there because half of 800 is enough for anything.
/// This project has already shipped one layout defect for exactly that reason.
/// So every case here pins a real handset width.
///
/// It also renders with the **test font, whose every glyph is one em wide** — so
/// `Patterns → small changes` measures ~480 px here against ~250 px on a device.
/// That is why the real titles are exercised on the graceful-degradation path
/// and a short title carries the fits-exactly path: the assertions are about the
/// LAYOUT RULE, which is what actually changed, rather than about whether one
/// particular string happens to clear one particular width in one font.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/shared/v02/chapter.dart';
import 'package:solar_icons/solar_icons.dart';

/// The three headings Today actually draws.
const List<String> kChapterTitles = <String>[
  'Last night → today',
  'Movement → recovery',
  'Patterns → small changes',
];

/// The handset widths this has to be right at. 320 is the narrowest phone still
/// in use; 414 is a large one. The 800 px default is deliberately absent.
const List<double> kHandsetWidths = <double>[320, 360, 390, 414];

/// A title short enough to fit at every one of those widths in the test font.
const String kShortTitle = 'Night';

/// The page's own horizontal padding — `instrument_screen.dart`'s `Insets.lg`.
const double kPagePadding = 16;

void main() {
  Future<void> pumpHeading(
    WidgetTester tester,
    String title,
    double width,
  ) async {
    tester.view
      ..physicalSize = Size(width, 400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
            child: ChapterHeading(
              title: title,
              icon: SolarIconsOutline.moonSleep,
              tone: Tone.sleep,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the rule reaches the trailing edge at every handset width', () {
    for (final title in <String>[kShortTitle, ...kChapterTitles]) {
      for (final width in kHandsetWidths) {
        testWidgets('${width.round()}px · "$title"', (tester) async {
          await pumpHeading(tester, title, width);

          final rule = tester.getRect(find.byKey(ChapterHeading.ruleKey));
          expect(
            rule.right,
            closeTo(width - kPagePadding, 0.5),
            reason:
                'the equal-flex split hands the rule free/2 and stops there, '
                'short of the edge — this is the assertion that fails under '
                'the bug at every width and in every font',
          );
          // And nothing overlaps: the CSS gap between the title and the rule is
          // exact, so the rule really is the remainder rather than an overlay.
          final box = tester.getRect(find.text(title));
          expect(rule.left - box.right, closeTo(ChapterHeading.gap * 2, 0.5));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('a title that fits is given its own width, not a share of the row', () {
    for (final width in kHandsetWidths) {
      testWidgets('"$kShortTitle" IS WHOLE AT ${width.round()}px', (
        tester,
      ) async {
        await pumpHeading(tester, kShortTitle, width);

        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(kShortTitle),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'the painted paragraph reports it did not fit',
        );
        // Intrinsic: as wide as the glyphs, no wider and no narrower.
        final box = tester.getRect(find.text(kShortTitle));
        expect(box.width, closeTo(paragraph.size.width, 0.5));
        // And the rule got everything else, which is far more than its floor —
        // the "full title, stubby rule" half of the bug.
        final rule = tester.getRect(find.byKey(ChapterHeading.ruleKey));
        expect(rule.width, greaterThan(ChapterHeading.minRule));
        expect(
          box.width + rule.width,
          closeTo(
            width -
                2 * kPagePadding -
                ChapterHeading.iconSize -
                ChapterHeading.gap * 3,
            0.5,
          ),
          reason: 'together they account for the whole row',
        );
      });
    }
  });

  group('a title too long for the row degrades gracefully', () {
    for (final title in kChapterTitles) {
      testWidgets('"$title" ELLIPSIZES AND KEEPS THE RULE AT ITS FLOOR', (
        tester,
      ) async {
        // In the test font every glyph is one em, so all three real titles are
        // over-wide here. On a device only the 320 px case reaches this path —
        // and the prototype's own row does not fit there either.
        await pumpHeading(tester, title, 320);

        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(title),
        );
        expect(paragraph.didExceedMaxLines, isTrue);
        expect(tester.takeException(), isNull);
        final rule = tester.getRect(find.byKey(ChapterHeading.ruleKey));
        expect(
          rule.width,
          closeTo(ChapterHeading.minRule, 0.5),
          reason: 'the row is genuinely full; the rule sits at its floor',
        );
        expect(rule.right, closeTo(320 - kPagePadding, 0.5));
      });
    }
  });
}
