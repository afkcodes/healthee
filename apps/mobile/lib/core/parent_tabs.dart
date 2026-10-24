/// `app.js:8`'s `parents` map — the tab a pushed screen belongs to.
///
/// ```js
/// const parents = { recovery:'today','sleep-history':'sleep',
///   workouts:'activity',workout:'activity',route:'activity',record:'activity',
///   fitness:'activity',body:'activity',metric:'insights',metrics:'insights',
///   insight:'insights',challenge:'actions',program:'actions',
///   coach-ledger:'actions','action-history':'actions',journal:'actions' };
/// H.back = () => routeHistory.length
///   ? history.back()
///   : H.navigate(parents[H.route.split('/')[0]] || 'today');
/// ```
///
/// ## This is a defect, not a nicety
///
/// `DetailPage` drew **no back control at all** when `Navigator.canPop()` was
/// false. Every detail screen is normally pushed, so the arrow was there
/// whenever anyone looked — but a deep link, a notification, or a process
/// restored onto `/body` opens that screen with an empty stack, and the owner
/// then had no way off it. Not a wrong way: none. That is the same shape as the
/// `go`-into-Settings defect `router.dart` records, and it went unnoticed for
/// the same reason — the affordance and the gesture went missing together.
///
/// The prototype answers it with this map and so does the app. Back pops when
/// there is a stack, and otherwise lands on the tab the screen belongs under.
///
/// ## The lookup is on the FIRST path segment
///
/// `H.route.split('/')[0]` — so `route/abc` and `insight/caffeine-sleep` resolve
/// through `route` and `insight`, and a screen with an id in its path does not
/// need an entry of its own.
///
/// **An unmapped screen goes to Today**, which is the prototype's `|| 'today'`.
/// Coach is deliberately unmapped in both: it is opened from five different
/// tabs, so there is no one tab it belongs under.
library;

import 'package:healthee/core/routes.dart';

/// The prototype's map, in this app's paths.
///
/// Two entries have no prototype counterpart and are filed by what they are:
///
///   * `/routes` — the app's saved-route list. The prototype's `record` links
///     straight to a single `route`, having no list screen; the list is a
///     sibling of both and belongs where they do.
///   * `/gps` — this app's name for the prototype's `record`.
const Map<String, String> kParentTabs = <String, String>{
  'recovery': Routes.today,
  'sleep-history': Routes.sleep,
  'history': Routes.insights,
  'insight': Routes.insights,
  'workouts': Routes.activity,
  'workout': Routes.activity,
  'route': Routes.activity,
  'routes': Routes.activity,
  'gps': Routes.activity,
  'fitness': Routes.activity,
  'body': Routes.activity,
  'challenge': Routes.actions,
  'program': Routes.actions,
  'coach-ledger': Routes.actions,
  'recommendations': Routes.actions,
  'journal': Routes.actions,
};

/// The tab [location] belongs under, or [Routes.today] when it belongs to none.
///
/// [location] is a path, with or without its query — `/history?metric=hrv`
/// resolves through `history` exactly as `/history` does, because the metric a
/// screen is showing does not change which tab it lives under.
String parentTabFor(String location) {
  final String path = location.split('?').first;
  final String head = path
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .firstOrNull ??
      '';
  return kParentTabs[head] ?? Routes.today;
}
