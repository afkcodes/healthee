/// Insights is the colour-system screen, in its order — held here.
///
/// The only way a re-ordering, a dropped section or one that crept back in gets
/// caught is by reading the section list and comparing it entry by entry. A
/// rendered scroll cannot do it: most of the screen is off the viewport and a
/// lazy sliver list has not built it.
///
/// The order is the kit's (`kit/3-insights.png`): the hero tiles, Effort &
/// stress, Longer patterns, What moved together, the link list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/features/insights/insights_sections.dart';
import 'package:healthee/features/insights/v02/coach_question_panel.dart';
import 'package:healthee/features/insights/v02/effort_stress_card.dart';
import 'package:healthee/features/insights/v02/insight_links.dart';
import 'package:healthee/features/insights/v02/moved_together.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';
import 'package:healthee/features/insights/v02/section_title.dart';
import 'package:healthee/features/insights/widgets/trends_section.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/page_header.dart';

import '../_today_stubs.dart';
import '_screen_data.dart';

/// The section list, built the way the screen builds it.
List<PageSection> sections({
  Map<String, Object?> Function(Map<String, Object?> json)? mutate,
}) => insightsSections(
  screenData(server: todayView(mutate: mutate)),
  const InsightsExtras(),
);

int _indexOf<T>(List<PageSection> list) =>
    list.indexWhere((section) => section.child is T);

/// The nth section whose child is a [T], counting from zero.
int _nthOf<T>(List<PageSection> list, int n) {
  var seen = 0;
  for (var i = 0; i < list.length; i++) {
    if (list[i].child is T) {
      if (seen == n) {
        return i;
      }
      seen++;
    }
  }
  return -1;
}

/// The titles of the section heads, in order.
List<String> _titles(List<PageSection> list) => <String>[
  for (final section in list)
    if (section.child is InsightSectionTitle)
      (section.child as InsightSectionTitle).title,
];

void main() {
  group('the kit’s order, entry by entry', () {
    test('EVERY SECTION THE KIT DRAWS IS DRAWN, AND IN ITS ORDER', () {
      final list = sections();
      final order = <int>[
        _indexOf<V02PageHeader>(list),
        _indexOf<HeroRow>(list),
        _nthOf<InsightSectionTitle>(list, 0),
        _indexOf<EffortStressCard>(list),
        _nthOf<InsightSectionTitle>(list, 1),
        _indexOf<TrendsGrid>(list),
        _nthOf<InsightSectionTitle>(list, 2),
        _indexOf<MovedTogetherCard>(list),
        _indexOf<InsightLinks>(list),
        // Kept: the screen's only door to the coach.
        _indexOf<CoachQuestionPanel>(list),
        _indexOf<DataFooter>(list),
      ];
      for (final index in order) {
        expect(index, isNonNegative, reason: 'a section is missing');
      }
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i],
          greaterThan(order[i - 1]),
          reason: 'section $i is out of the kit’s order',
        );
      }
    });

    test('the three section heads are the kit’s, in its words', () {
      expect(_titles(sections()), <String>[
        'Effort & stress',
        'Longer patterns',
        'What moved together',
      ]);
    });
  });

  group('the gaps are v02’s two rungs, not legacy’s four', () {
    test('THE SCREEN USES CARD GAP AND SECTION GAP AND NOTHING ELSE', () {
      final gaps = <double>{
        for (final section in sections())
          if (section.gap > 0) section.gap,
      };
      expect(
        gaps.difference(<double>{PageSpacing.panel, PageSpacing.block}),
        isEmpty,
        reason:
            'a v02 screen uses one ladder or the other; a legacy rung here is '
            'the two systems drifting into one screen',
      );
    });
  });

  group('the conditional sections are the payload’s conditions', () {
    test('NO TRENDS MEANS NO HEADING — a heading over nothing is dead', () {
      final none = sections(
        mutate: (json) => <String, Object?>{
          ...json,
          'sparklines': const <String, Object?>{},
        },
      );
      expect(_indexOf<TrendsGrid>(none), -1);
      expect(_titles(none), isNot(contains('Longer patterns')));
      // And the block that follows is untouched: a silent section is not a
      // truncated screen.
      expect(_indexOf<MovedTogetherCard>(none), isNonNegative);
    });

    test('no findings means no findings card and no heading over it', () {
      final none = sections(
        mutate: (json) => <String, Object?>{
          ...json,
          'top_findings': const <Object?>[],
        },
      );
      expect(_indexOf<MovedTogetherCard>(none), -1);
      expect(_titles(none), isNot(contains('What moved together')));
      expect(_indexOf<InsightLinks>(none), isNonNegative);
    });

    test('THE HERO ROW IS ALWAYS THERE WHEN THE SERVER HAS ANSWERED', () {
      // Neither tile has anything behind it, and the row is still drawn: each
      // tile says "Not enough readings yet" in its own hatched strip.
      final none = sections(
        mutate: (json) => <String, Object?>{
          ...json,
          'top_findings': const <Object?>[],
          'biological_age': <String, Object?>{
            ...json['biological_age']! as Map<String, Object?>,
            'contributions': const <Object?>[],
          },
        },
      );
      final row = none.map((s) => s.child).whereType<HeroRow>().single;
      expect(row.pattern, isNull);
      expect(row.age, isNull);
    });

    test(
      'two hours is not a day, and the linked chart is not drawn for it',
      () {
        final thin = sections(
          mutate: (json) => <String, Object?>{
            ...json,
            'today_hr_series': const <Object?>[],
            'today_stress_series': const <Object?>[],
          },
        );
        expect(_indexOf<EffortStressCard>(thin), -1);
        // The heading belongs to the card and goes with it.
        expect(_titles(thin), isNot(contains('Effort & stress')));
      },
    );
  });

  group('a past day keeps only what is not dated', () {
    List<PageSection> past() => insightsSections(
      screenData(day: DeviceDay.empty('2026-07-01'), server: todayView()),
      const InsightsExtras(),
    );

    test(
      'THE PATTERNS, THE PAIRS AND THE HOURS ARE TODAY’S, NOT THIS DAY’S',
      () {
        final list = past();
        expect(_indexOf<HeroRow>(list), -1);
        expect(_indexOf<EffortStressCard>(list), -1);
        expect(_indexOf<TrendsGrid>(list), -1);
        expect(_indexOf<MovedTogetherCard>(list), -1);
        expect(_titles(list), isEmpty);
      },
    );

    test('the ways into the history are not dated, and stay', () {
      final list = past();
      expect(_indexOf<InsightLinks>(list), isNonNegative);
      expect(_indexOf<CoachQuestionPanel>(list), isNonNegative);
    });
  });
}
