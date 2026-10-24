/// The five tabs fit the narrowest phone at the ladder's caption step.
///
/// The tab labels moved from a 10 px override to `TypeLadder.caption` (12 px)
/// when the type ladder landed. Five labels share 320 px, so each gets a fifth
/// of it; this measures that with the real face rather than the test font,
/// whose every glyph is one em wide and would overflow at any size.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/shared/app_tab_bar.dart';

import '../features/_hero_probe.dart';

void main() {
  setUpAll(loadFigtree);

  for (final width in kPhoneWidths) {
    testWidgets('every tab label is whole at ${width.round()} px', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: AppTabBar(currentIndex: 0, onSelect: (_) {}),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (final tab in kAppTabs) {
        final label = tester.renderObject<RenderParagraph>(
          find.text(tab.label),
        );
        expect(label.didExceedMaxLines, isFalse, reason: tab.label);
        expect(label.text.style!.fontSize, 12, reason: 'the caption step');
        final box = tester.getRect(find.text(tab.label));
        expect(box.right, lessThanOrEqualTo(width), reason: tab.label);
      }
    });
  }
}
