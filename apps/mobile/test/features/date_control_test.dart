/// `.date-navigation` — previous, next, the calendar, and the way back.
///
/// The prototype's header carries a date CONTROL, not a date label, and the
/// selection follows the reader between screens. This suite holds the control's
/// behaviour and the one thing it must never be allowed to cause.
///
/// ## What the control must never be allowed to cause
///
/// A date control creates a way to have one day's numbers on screen with another
/// day's date above them, which is **stale-as-current**: the failure
/// `vo2max_tier.py`'s freshness horizon exists for, and the
/// one this repo has already swept three times.
///
/// The answer used to be a refusal — `/api/today` took no day, so the screen drew
/// nothing derived on a past one. The endpoint now takes `day=YYYY-MM-DD` and
/// answers from the rows filed under it (`docs/AS_OF_DAY.md`), so the refusal is
/// gone and the guard moved: the screen draws the payload only when the payload's
/// own `as_of` day is the day being read. That closes the same failure at its
/// remaining entry point — the frame between the tap and the response.
///
/// Both are tested against the section list directly rather than through a
/// scroll, because what is being asserted is what the screen DECIDED — a rendered
/// viewport would pass while the hero sat one scroll below it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/store/view_date.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/features/today/today_sections.dart';
import 'package:healthee/features/today/v02/date_calendar_sheet.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/features/today/v02/today_key_numbers.dart';
import 'package:healthee/features/today/widgets/data_health_section.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/chapter.dart';

import '../_today_stubs.dart';
import '_screen_data.dart';
import '_today_host.dart';

/// The window Today hands the control, as `today_screen.dart` builds it.
DateNavigation _window({ValueChanged<String>? onSelect}) => DateNavigation(
  earliest: earliestViewableDay(todayDate),
  latest: todayDate,
  onSelect: onSelect ?? (_) {},
);

/// The section list for a phone showing [day], with a server that answers FOR
/// that day — which is what `/api/today?day=…` now does.
List<PageSection> _sectionsFor(String day, {DatedHistory? history}) =>
    todaySections(
      screenData(
        day: DeviceDay.empty(day),
        server: todayViewFor(day, today: todayDate),
        history: history,
      ),
      TodayExtras(navigation: _window()),
    );

bool _has<T>(List<PageSection> list) =>
    list.any((section) => section.child is T);

/// What the head calls the newest day the window reaches.
const String kTodayWord = 'Today';

void main() {
  group('the control moves the day', () {
    late LocalStore store;

    setUp(() async {
      store = LocalStore.memory();
      await seedDevice(store);
    });

    tearDown(() => store.close());

    testWidgets('PREVIOUS AND NEXT MOVE IT, AND Latest COMES BACK', (
      tester,
    ) async {
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      // The seeded day. `todayDate` is a Tuesday — and it is the newest day the
      // window reaches, so the head calls it `Today` (see `dayTitle`). Every
      // day stepped back to is named instead.
      expect(find.text(kTodayWord), findsOneWidget);

      // Backwards, forwards, and back to the newest day — the same journey the
      // two chevrons used to make one press at a time, now one tap each.
      await chooseDay(tester, '2026-08-03');
      expect(find.text(prettyDate('2026-08-03')), findsOneWidget);
      expect(find.text(kTodayWord), findsNothing);

      await chooseDay(tester, '2026-08-02');
      expect(find.text(prettyDate('2026-08-02')), findsOneWidget);

      await chooseDay(tester, '2026-08-03');
      expect(find.text(prettyDate('2026-08-03')), findsOneWidget);

      await chooseDay(tester, todayDate);
      expect(find.text(kTodayWord), findsOneWidget);
    });

    testWidgets('it cannot walk past the wall clock', (tester) async {
      // There are no measurements from tomorrow. A control that could ask for
      // one would be offering a screen of withholds and calling it a day. The
      // grid draws tomorrow — a month has to — and refuses the tap.
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      await openCalendar(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('calendar.2026-08-05')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(kTodayWord),
        findsOneWidget,
        reason: 'a day past the wall clock must not become the day on screen',
      );
    });

    testWidgets('TAPPING THE DATE OPENS THE CALENDAR', (tester) async {
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DayPill));
      await tester.pumpAndSettle();

      expect(find.text(kDateCalendarTitle), findsOneWidget);
      expect(find.text('August 2026'), findsOneWidget);
      // The dot's claim, said in words rather than left to be guessed at.
      expect(find.text(helpLine), findsOneWidget);

      // A day inside the window is a live control and choosing it moves the
      // screen; the sheet closes behind it.
      await tester.tap(
        find.byKey(const ValueKey<String>('calendar.2026-08-01')),
      );
      await tester.pumpAndSettle();

      expect(find.text(kDateCalendarTitle), findsNothing);
      expect(find.text(prettyDate('2026-08-01')), findsOneWidget);
    });
  });

  group('a past day is answered for, not relabelled', () {
    test('THE DERIVED HALF IS DRAWN, FOR THE DAY THE SERVER ANSWERED FOR', () {
      // The reversal, and it is a reversal on purpose. This suite used to assert
      // that the biological age and the summary tiles were ABSENT on a past day,
      // and that was right while `/api/today` took no day: the only payload there
      // could be described the current one, so drawing it under an older date was
      // stale-as-current. The endpoint now answers from the rows filed under the
      // day it is asked about (`docs/AS_OF_DAY.md`), so refusing would be
      // withholding data we hold — and withheld and NOT ASKED FOR are different
      // states, which is the distinction the whole product turns on.
      final past = _sectionsFor('2026-08-01');
      expect(
        _has<ReadingView<BiologicalAge>>(past),
        isTrue,
        reason: 'the biological age, as of that day',
      );
      expect(_has<TodayKeyNumbers>(past), isTrue, reason: 'the tiles');
    });

    test('AND IT IS THAT DAY’S CHAPTERS, NOT THE DATED-HISTORY ONES', () {
      // A past day now draws Today's own three chapters, because it is Today —
      // answered for another date. `Overnight readings` and its two siblings were
      // the CALENDAR view that stood in while there was nothing derived to head.
      final headings = <String>[
        for (final section in _sectionsFor('2026-08-01'))
          if (section.child case final ChapterHeading heading) heading.title,
      ];
      expect(
        headings,
        containsAll(<String>['Last night → today', 'Movement → recovery']),
      );
      expect(headings, isNot(contains('Overnight readings')));
    });

    test('A PAYLOAD ABOUT ANOTHER DAY IS NOT THIS DAY’S ANSWER', () {
      // **The frame between the tap and the response.** Riverpod keeps the
      // previous value through a refresh, so when the control moves, the answer
      // on hand is still the old day's while the new request is in flight.
      // Drawing it would put one day's judgements under another day's date for
      // the length of a round trip — stale-as-current with a shorter lifetime,
      // which is not a smaller version of it.
      //
      // The comparison is exact because the provider sends the selection on every
      // request and the server echoes the day it answered for, so a landed
      // response always names the day that was asked for.
      final mid = todaySections(
        screenData(
          day: DeviceDay.empty('2026-08-01'),
          server: todayViewFor(todayDate, today: todayDate),
        ),
        TodayExtras(navigation: _window()),
      );
      expect(
        _has<ReadingView<BiologicalAge>>(mid),
        isFalse,
        reason: "the previous day's hero was drawn under the new date",
      );
      expect(
        mid.any((section) => section.child is LoadingState),
        isTrue,
        reason:
            'and the screen says it is reading, rather than showing nothing',
      );
    });

    test('the live-feed trust card belongs to the current day only', () {
      // Every figure on it is an age measured against right now, so it is an
      // observation made AFTER a past day rather than one of that day's facts.
      // The server sends null; the layout says the same thing out loud.
      expect(_has<DataHealthSection>(_sectionsFor('2026-08-01')), isFalse);
      expect(_has<DataHealthSection>(_sectionsFor(todayDate)), isTrue);
    });

    test('and the current day is unchanged', () {
      // The half a reversal test is blind to: the live path must not move.
      final today = _sectionsFor(todayDate);
      expect(_has<ReadingView<BiologicalAge>>(today), isTrue);
      expect(_has<ChapterHeading>(today), isTrue);
      expect(_has<TodayKeyNumbers>(today), isTrue);
    });

    testWidgets('the header reads the day being shown', (tester) async {
      final store = LocalStore.memory();
      addTearDown(store.close);
      await seedDevice(store);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      await chooseDay(tester, '2026-08-03');

      expect(find.text(prettyDate('2026-08-03')), findsOneWidget);
    });
  });

  group('the window', () {
    test('reaches exactly as far back as the phone keeps a day', () {
      // `horizon_prune.dart` removes a day at 60. A control that offered day 61
      // would be offering history the store has already deleted.
      expect(earliestViewableDay('2026-08-04'), '2026-06-05');
      expect(isViewableDay('2026-06-05', '2026-08-04'), isTrue);
      expect(isViewableDay('2026-06-04', '2026-08-04'), isFalse);
      expect(isViewableDay('2026-08-05', '2026-08-04'), isFalse);
    });

    test('day arithmetic crosses a month and a year end', () {
      expect(shiftDay('2026-03-01', -1), '2026-02-28');
      expect(shiftDay('2026-12-31', 1), '2027-01-01');
    });

    test('AND THE SELECTION ITSELF REFUSES A DAY OUTSIDE IT', () {
      // The bound belongs on the selection, not only on the two chevrons. The
      // calendar can name any day of its month and a future caller has no
      // reason to check first, so the provider is where "this phone cannot
      // speak about that day" has to hold.
      //
      // It refuses rather than clamps: answering a request for one day with a
      // different day would put something nobody asked for on screen under a
      // date they did not choose.
      final container = ProviderContainer(
        // Untyped on purpose: `Override` is not exported by `flutter_riverpod`,
        // which `_today_stubs.dart` already records.
        overrides: [todayProvider.overrideWithValue(todayDate)],
      );
      addTearDown(container.dispose);
      final selection = container.read(viewDateProvider.notifier);

      expect(container.read(viewDateProvider), todayDate);

      selection.select('2026-08-05');
      expect(container.read(viewDateProvider), todayDate, reason: 'tomorrow');

      selection.select('2026-06-04');
      expect(
        container.read(viewDateProvider),
        todayDate,
        reason: 'a day the horizon has already pruned',
      );

      selection.select('2026-08-01');
      expect(container.read(viewDateProvider), '2026-08-01');

      selection.move(-1);
      expect(container.read(viewDateProvider), '2026-07-31');

      selection.latest();
      expect(container.read(viewDateProvider), todayDate);
    });
  });
}
