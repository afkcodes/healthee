/// **Every named style is a step on the ladder, and nothing is set below it.**
///
/// The ladder (`type_ladder.dart`) is twelve steps on nine sizes. The theme
/// names roles (`TypeScale.panelTitle`, `FormType.badge`, the Material roles)
/// and each must resolve to one of those steps exactly: its size on the list,
/// its line box the step's own, its weight one the ladder uses, tabular figures
/// on, and the app's face. Dart has no reflection, so the roles are listed by
/// hand below; a role added to a theme class without being added here is the
/// one gap, and `lib/core/theme/` is small enough to review for it.
///
/// The ladder's own table is restated here too (`kSteps`), so a step whose
/// size, line height, weight or tracking drifts fails by name, and a role must
/// match one step in all four.
///
/// Two further guarantees: [TypeLadder.micro] (11 px) is reserved for chart
/// text, so only the chart-only roles may resolve to it; and no source file in
/// `lib/` sets a `fontSize` literal below 11. The snapping rule for a free size
/// (`TypeLadder.nearest`) is pinned in `type_ladder_nearest_test.dart`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/meter_type_scale.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/core/theme/type_scale_dates.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/core/theme/typography.dart';

/// Each ladder size and the line height its step sets, restated by hand.
final Map<double, double> kLineHeights = <double, double>{
  64: 64,
  40: 44,
  28: 34,
  20: 26,
  17: 22,
  15: 22,
  13: 18,
  12: 16,
  11: 14,
};

/// The twelve steps as the spec's table gives them: (style, size, line height,
/// weight, tracking). Restated by hand, so a step that drifts in any one of its
/// four metrics fails by name.
final Map<String, (TextStyle, double, double, FontWeight, double)> kSteps =
    <String, (TextStyle, double, double, FontWeight, double)>{
      'display': (TypeLadder.display, 64, 64, FontWeight.w700, -1.25),
      'metric': (TypeLadder.metric, 40, 44, FontWeight.w700, -0.6),
      'title1': (TypeLadder.title1, 28, 34, FontWeight.w700, -0.3),
      'title2': (TypeLadder.title2, 20, 26, FontWeight.w700, -0.1),
      'headline': (TypeLadder.headline, 17, 22, FontWeight.w600, 0),
      'body': (TypeLadder.body, 15, 22, FontWeight.w400, 0),
      'bodyStrong': (TypeLadder.bodyStrong, 15, 22, FontWeight.w600, 0),
      'callout': (TypeLadder.callout, 13, 18, FontWeight.w400, 0),
      'calloutStrong': (TypeLadder.calloutStrong, 13, 18, FontWeight.w600, 0),
      'label': (TypeLadder.label, 12, 16, FontWeight.w700, 0.72),
      'caption': (TypeLadder.caption, 12, 16, FontWeight.w400, 0),
      'micro': (TypeLadder.micro, 11, 14, FontWeight.w400, 0),
    };

/// The roles allowed to be [TypeLadder.micro]: chart axes, chart keys and a
/// chart's end labels, verified at their call sites. The one exception is
/// `age_orb_hero.dart`, which sets `KeyType.rangeEnd` (at its own size) under
/// its title, off any chart; it is exempt here and rewritten in a later step.
const Set<String> kChartOnly = <String>{
  'TypeScale.colourKey',
  'TypeScale.factorRow',
  'KeyType.rangeEnd',
  'KeyType.rangeUsual',
  'MeterType.signalKey',
  'MeterType.signalReading',
  'MeterType.comparisonRow',
};

Map<String, TextStyle> _typeScale() => <String, TextStyle>{
  'TypeScale.pageTitle': TypeScale.pageTitle,
  'TypeScale.pageDate': TypeScale.pageDate,
  'TypeScale.pageDateStrong': TypeScale.pageDateStrong,
  'TypeScale.sectionTitle': TypeScale.sectionTitle,
  'TypeScale.panelTitle': TypeScale.panelTitle,
  'TypeScale.panelValue': TypeScale.panelValue,
  'TypeScale.panelUnit': TypeScale.panelUnit,
  'TypeScale.panelNote': TypeScale.panelNote,
  'TypeScale.textButton': TypeScale.textButton,
  'TypeScale.tileTitle': TypeScale.tileTitle,
  'TypeScale.tileValue': TypeScale.tileValue,
  'TypeScale.tileMeta': TypeScale.tileMeta,
  'TypeScale.colourKey': TypeScale.colourKey,
  'TypeScale.bridge': TypeScale.bridge,
  'TypeScale.panelContext': TypeScale.panelContext,
  'TypeScale.panelTitleCompact': TypeScale.panelTitleCompact,
  'TypeScale.panelValueCompact': TypeScale.panelValueCompact,
  'TypeScale.panelUnitCompact': TypeScale.panelUnitCompact,
  'TypeScale.panelNoteCompact': TypeScale.panelNoteCompact,
  'TypeScale.statLabel': TypeScale.statLabel,
  'TypeScale.statValue': TypeScale.statValue,
  'TypeScale.statUnit': TypeScale.statUnit,
  'TypeScale.chapterTitle': TypeScale.chapterTitle,
  'TypeScale.metricListValue': TypeScale.metricListValue,
  'TypeScale.chapterNav': TypeScale.chapterNav,
  'TypeScale.factorRow': TypeScale.factorRow,
  'TypeScale.dimensionLabel': TypeScale.dimensionLabel,
  'TypeScale.dimensionValue': TypeScale.dimensionValue,
  'TypeScale.dimensionReading': TypeScale.dimensionReading,
  'TypeScale.dimensionNote': TypeScale.dimensionNote,
  'TypeScale.deviceStrip': TypeScale.deviceStrip,
  'TypeScale.entryTitle': TypeScale.entryTitle,
  'TypeScale.entryBody': TypeScale.entryBody,
  'TypeScale.footer': TypeScale.footer,
  'TypeScale.detailTitle': TypeScale.detailTitle,
  'TypeScale.small': TypeScale.small,
  'TypeScale.observationTitle': TypeScale.observationTitle,
  'TypeScale.observationBody': TypeScale.observationBody,
  'TypeScale.tinyLabel': TypeScale.tinyLabel,
  'TypeScale.badge': TypeScale.badge,
  'TypeScale.noticeTitle': TypeScale.noticeTitle,
  'TypeScale.noticeBody': TypeScale.noticeBody,
  'TypeScale.focusEyebrow': TypeScale.focusEyebrow,
  'TypeScale.focusTitle': TypeScale.focusTitle,
  'TypeScale.heroNumber': TypeScale.heroNumber,
  'TypeScale.heroUnit': TypeScale.heroUnit,
  'TypeScale.metricHeroNumber': TypeScale.metricHeroNumber,
  'TypeScale.metricHeroUnit': TypeScale.metricHeroUnit,
  'TypeScale.rowTitle': TypeScale.rowTitle,
  'TypeScale.challengeTitle': TypeScale.challengeTitle,
  'TypeScale.buttonLabel': TypeScale.buttonLabel,
  'TypeScale.textLink': TypeScale.textLink,
  'TypeScale.coachBody': TypeScale.coachBody,
  'TypeScale.formNote': TypeScale.formNote,
  'TypeScale.inputText': TypeScale.inputText,
};

Map<String, TextStyle> _formType() => <String, TextStyle>{
  'FormType.displayTitle': FormType.displayTitle,
  'FormType.detailTitle': FormType.detailTitle,
  'FormType.heading2': FormType.heading2,
  'FormType.heading3': FormType.heading3,
  'FormType.body': FormType.body,
  'FormType.small': FormType.small,
  'FormType.rowTitle': FormType.rowTitle,
  'FormType.rowSubtitle': FormType.rowSubtitle,
  'FormType.toggleTitle': FormType.toggleTitle,
  'FormType.toggleBody': FormType.toggleBody,
  'FormType.fieldLabel': FormType.fieldLabel,
  'FormType.fieldInput': FormType.fieldInput,
  'FormType.fieldHint': FormType.fieldHint,
  'FormType.formNote': FormType.formNote,
  'FormType.button': FormType.button,
  'FormType.linkButton': FormType.linkButton,
  'FormType.badge': FormType.badge,
  'FormType.noticeTitle': FormType.noticeTitle,
  'FormType.noticeBody': FormType.noticeBody,
  'FormType.statLabel': FormType.statLabel,
  'FormType.statNumber': FormType.statNumber,
  'FormType.statUnit': FormType.statUnit,
  'FormType.timelineTitle': FormType.timelineTitle,
  'FormType.timelineBody': FormType.timelineBody,
  'FormType.timelineNode': FormType.timelineNode,
  'FormType.themeOption': FormType.themeOption,
  'FormType.syncStage': FormType.syncStage,
  'FormType.observationTitle': FormType.observationTitle,
  'FormType.observationBody': FormType.observationBody,
};

Map<String, TextStyle> _otherScales() => <String, TextStyle>{
  'KeyType.name': KeyType.name,
  'KeyType.value': KeyType.value,
  'KeyType.unit': KeyType.unit,
  'KeyType.line': KeyType.line,
  'KeyType.chip': KeyType.chip,
  'KeyType.rangeEnd': KeyType.rangeEnd,
  'KeyType.rangeUsual': KeyType.rangeUsual,
  'DateType.dateCaret': DateType.dateCaret,
  'DateType.calendarMonth': DateType.calendarMonth,
  'DateType.calendarDay': DateType.calendarDay,
  'DateType.calendarDayCurrent': DateType.calendarDayCurrent,
  'SleepType.duration': SleepType.duration,
  'SleepType.durationNarrow': SleepType.durationNarrow,
  'SleepType.durationUnit': SleepType.durationUnit,
  'SleepType.deviceScore': SleepType.deviceScore,
  'SleepType.deviceCaption': SleepType.deviceCaption,
  'SleepType.checkName': SleepType.checkName,
  'SleepType.checkValue': SleepType.checkValue,
  'SleepType.checkTarget': SleepType.checkTarget,
  'SleepType.checkDetail': SleepType.checkDetail,
  'SleepType.tableCell': SleepType.tableCell,
  'SleepType.shareDuration': SleepType.shareDuration,
  'SleepType.vitalLabel': SleepType.vitalLabel,
  'SleepType.vitalValue': SleepType.vitalValue,
  'SleepType.vitalUnit': SleepType.vitalUnit,
  'MeterType.signalKey': MeterType.signalKey,
  'MeterType.signalReading': MeterType.signalReading,
  'MeterType.comparisonRow': MeterType.comparisonRow,
};

Map<String, TextStyle> _textTheme() {
  final theme = healtheeTextTheme(
    ink: const Color(0xFF121217),
    ink2: const Color(0xFF56565F),
    ink3: const Color(0xFF6D6D7C),
  );
  return <String, TextStyle>{
    'displayLarge': theme.displayLarge!,
    'displayMedium': theme.displayMedium!,
    'headlineMedium': theme.headlineMedium!,
    'headlineSmall': theme.headlineSmall!,
    'titleLarge': theme.titleLarge!,
    'titleMedium': theme.titleMedium!,
    'titleSmall': theme.titleSmall!,
    'bodyLarge': theme.bodyLarge!,
    'bodyMedium': theme.bodyMedium!,
    'bodySmall': theme.bodySmall!,
    'labelLarge': theme.labelLarge!,
    'labelMedium': theme.labelMedium!,
    'labelSmall': theme.labelSmall!,
  };
}

/// Every named role in the theme, by name.
Map<String, TextStyle> _allRoles() => <String, TextStyle>{
  ..._typeScale(),
  ..._formType(),
  ..._otherScales(),
  ..._textTheme(),
};

/// `fontSize:` set to a number literal, anywhere in a line.
final RegExp _fontSizeLiteral = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)\b');

void main() {
  group('THE LADDER ITSELF: each step, restated by hand', () {
    for (final MapEntry(key: name, value: step) in kSteps.entries) {
      test(name, () {
        final (style, size, line, weight, tracking) = step;
        expect(style.fontSize, size);
        expect(style.height! * size, closeTo(line, 1e-9));
        expect(style.fontWeight, weight);
        expect(style.fontVariations, <FontVariation>[
          FontVariation('wght', weight.value.toDouble()),
        ]);
        expect(style.letterSpacing, tracking);
      });
    }

    test('the size list is the steps’ sizes, largest first', () {
      expect(TypeLadder.sizes, <double>[64, 40, 28, 20, 17, 15, 13, 12, 11]);
    });
  });

  group('every named role is a ladder step', () {
    for (final role in _allRoles().entries) {
      test(role.key, () {
        final style = role.value;
        final size = style.fontSize!;
        expect(TypeLadder.sizes, contains(size), reason: 'size $size');
        expect(
          style.height! * size,
          closeTo(kLineHeights[size]!, 1e-9),
          reason: 'the line box is the step’s own',
        );
        expect(<FontWeight>[
          FontWeight.w400,
          FontWeight.w600,
          FontWeight.w700,
        ], contains(style.fontWeight));
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        expect(style.fontFamily, 'Figtree');
        expect(style.fontFamily, healtheeFontFamily);
        expect(
          <String>[
            for (final MapEntry(key: name, value: (step, _, _, _, _))
                in kSteps.entries)
              if (step.fontSize == size &&
                  step.height == style.height &&
                  step.fontWeight == style.fontWeight &&
                  step.letterSpacing == style.letterSpacing &&
                  listEquals(step.fontVariations, style.fontVariations))
                name,
          ],
          isNotEmpty,
          reason: 'size, line, weight and tracking are one step’s exactly',
        );
      });
    }
  });

  test('MICRO IS FOR CHARTS: only the chart-only roles are 11 px', () {
    final micro = <String>{
      for (final role in _allRoles().entries)
        if (role.value.fontSize == 11) role.key,
    };
    expect(micro, kChartOnly);
    for (final name in kChartOnly) {
      expect(
        _allRoles()[name]!.fontWeight,
        FontWeight.w400,
        reason: '$name: micro is set at 400',
      );
    }
  });

  test('no role is set below 11 px', () {
    for (final role in _allRoles().entries) {
      expect(role.value.fontSize, greaterThanOrEqualTo(11), reason: role.key);
    }
  });

  test('NO SOURCE FILE IN lib/ SETS A fontSize LITERAL BELOW 11', () {
    final offenders = <String>[
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          for (final (index, line) in file.readAsLinesSync().indexed)
            for (final match in _fontSizeLiteral.allMatches(line))
              if (double.parse(match.group(1)!) < 11)
                '${file.path}:${index + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty);
  });

  test('MUTATION — the source scan can see a small literal', () {
    expect(_fontSizeLiteral.hasMatch('  fontSize: 9,'), isTrue);
    expect(
      _fontSizeLiteral.firstMatch('x.copyWith(fontSize: 10.5)')!.group(1),
      '10.5',
    );
    expect(_fontSizeLiteral.hasMatch('fontSize: holeSize,'), isFalse);
  });
}
