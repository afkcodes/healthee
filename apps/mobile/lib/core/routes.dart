/// Every route's PATH, and nothing that knows what is at the end of one.
///
/// Split out of `router.dart` at the 400-line gate (Standards section 1), and
/// the seam is a real one rather than a place to cut: this file is the app's
/// path vocabulary and imports nothing but Dart, while `router.dart` imports
/// every screen in the app to wire them up. A widget that needs a destination
/// needed the whole router to name one.
///
/// `router.dart` re-exports this file, so `import 'core/router.dart'` still
/// resolves [Routes] and no call site moved. Import this one directly where only
/// the paths are wanted — `core/parent_tabs.dart` does.
library;

import 'package:healthee/core/profile_field.dart';

/// Every route's path, in one place. Screens reference these, never string
/// literals — Standards section 3 bans the string-literal habit for user
/// constants and the reasoning is the same here: a typo'd path fails at
/// runtime, a typo'd constant fails at compile time.
abstract final class Routes {
  static const recommendations = '/recommendations';
  static const gps = '/gps';
  static const routes = '/routes';
  static const route = '/route';
  static const String challenge = '/challenge';
  static const String program = '/program';

  /// The coach ledger, "Every yes, checked". Not `/coach`: that is the chat.
  static const String coachLedger = '/coach-ledger';

  /// The breathing plan: four items, the patterns, and the owner's switches.
  static const String breathingPlan = '/breathing';

  /// One breathing session. Carries `item=<morning|midday|night|onDemand>` for
  /// a plan item or `pattern=<id>` for an ad hoc one; see
  /// [breathingPlayerLocation].
  static const String breathingPlayer = '/breathing/play';
  static const String workouts = '/workouts';
  static const String workout = '/workout';
  static const String profile = '/profile';

  /// Daily metric observations over selectable periods.
  static const String history = '/history';

  /// Manual observations and recent entries.
  static const String journal = '/journal';

  /// The daily snapshot. The app's home.
  static const String today = '/';

  /// Last night, and the one lever to improve tonight.
  static const String sleep = '/sleep';

  /// Fitness, organised around VO₂max.
  static const String activity = '/activity';

  /// The owner's own history — trends, and the patterns found in it.
  static const String insights = '/insights';

  /// The coach conversation, on the frame the prototype draws it on.
  ///
  /// **It was a sheet and is now a route.** `screens-actions.js::H.screens.coach`
  /// is a full screen with a back control, and five surfaces link to it — two of
  /// them (*Discuss this workout*, *Talk this through*) asking about something
  /// specific. A sheet cannot be deep linked, does not survive a rotation, and
  /// cannot carry the subject it was opened about; those two links lost theirs.
  ///
  /// The subject rides in `?topic=`, and `coach_screen.dart` says why that is
  /// the opening message rather than anything the server is told separately.
  static const String coach = '/coach';

  /// Conversations already had, read back from this device.
  ///
  /// A child of [coach] rather than a sibling: it is reached from the coach's
  /// own head and returns to it, and reopening a thread pops straight back into
  /// the conversation it belongs to.
  static const String coachHistory = '/coach/history';

  /// The biological-age estimate, opened up: the ladder, its two terms, and
  /// the lever it does not price.
  ///
  /// Reached from Today's hero (its eyebrow arrow and both contribution rows)
  /// and from the Insights relationship card. The prototype files it under
  /// Activity in its `parents` map; the app pushes it, so it returns to
  /// whichever screen opened it.
  static const String body = '/body';

  /// VO₂max with its instrument, its stored history and the work behind it.
  static const String fitness = '/fitness';

  /// The recovery model, opened up: its weights, its factors, and each signal
  /// against the owner's own baseline.
  static const String recovery = '/recovery';

  /// `Your trends`: the main readings over a week, a month or six months.
  static const String trends = '/trends';

  /// Every night in the window, and the way into one of them.
  static const String sleepHistory = '/sleep-history';

  /// One correlation found in the owner's own history, opened from the Insights
  /// relationship card.
  ///
  /// Takes the pair as a path segment because the server sends findings with no
  /// id — see `features/insights/v02/finding_detail_screen.dart`.
  static const String insight = '/insight';

  /// Every cited action the server raised for today.
  static const String actions = '/actions';

  /// Appearance, the server session, the strap, diagnostics and the licences.
  ///
  /// **Outside the tab shell**, and reached from the Today header's avatar —
  /// which is the entry point that already existed, extended rather than
  /// duplicated. A settings surface inside the bar would light a tab while the
  /// owner is somewhere that is not a tab.
  static const String settings = '/settings';

  /// Light · Dark · System, and the accent this build wears.
  ///
  /// ## The sub-screens are paths under [settings], not flags on it
  ///
  /// The v02 design turns Settings from one long scroll of expanding cards into
  /// an **index of rows**, each opening a screen of its own. A boolean on the
  /// settings screen saying "show the appearance panel" would be a route the
  /// router does not know about: no deep link, no back arrow, and a system back
  /// gesture that leaves the app instead of closing the panel.
  ///
  /// They nest under `/settings` because that is what they are under, and
  /// because a `push` from the index then pops back to the index — which is the
  /// same rule `leaveSetup` keeps for the two setup flows.
  static const String appearance = '/settings/appearance';

  /// The three optional nudges, and the times they arrive at.
  static const String reminders = '/settings/reminders';

  /// Whether the phone collects and uploads on its own, and under what limits.
  static const String background = '/settings/background';

  /// The strap this phone is paired to: its charge, its last read, its sync.
  static const String device = '/settings/device';

  /// Which streams are current, and how old each one is.
  static const String dataFreshness = '/settings/sync';

  /// What this app is, which build it is, and the licences it carries.
  static const String about = '/settings/about';

  /// The first screen an app with nothing set up has to show.
  ///
  /// Not reached by a redirect — the router still sends a strapless app to
  /// [pairing], which is the flow that gets it working. This is the door
  /// **into** that flow, and the account screen beside it.
  static const String welcome = '/welcome';

  /// Pair a strap, or review the pairing already held.
  static const String pairing = '/pairing';

  /// Baselines and the strap's own streams — "is the instrument working".
  ///
  /// Off the tab bar on purpose. `diagnostics_screen.dart` argues it: these are
  /// the numbers the owner wants when something looks wrong, and never at 7am.
  /// Reached from [pairing], which is where the avatar on Today already goes.
  static const String diagnostics = '/diagnostics';

  /// Sign in to the Healthee server, or review the session already held.
  ///
  /// **Nothing redirects here**, unlike [pairing]. See the router's own
  /// "Unpaired means pairing" note for the contrast: an app with no strap has
  /// nothing to show at all, whereas an app with no server session still has
  /// every measurement this phone read off the strap. Gating on a token would
  /// take the owner's own data away until they satisfied a server, and
  /// strap-only is a supported mode rather than a degraded one.
  static const String serverSignIn = '/server';

  /// The honesty-state specimen sheet. **Not a product screen.**
  ///
  /// `FoundationScreen` used to sit on [today], where it was reasonably
  /// mistaken for a hung request — a catalogue whose loading specimen looks
  /// exactly like a screen that never loaded. It is kept because it is a useful
  /// side-by-side of the four `Reading` states while building a card, and it is
  /// kept OFF the home route for the same reason it was moved.
  static const String devFoundation = '/dev/foundation';
}

/// The coach's location, carrying [topic] as the message to open with.
///
/// One builder rather than five call sites composing a query string: the
/// encoding is easy to get almost right, and a topic that arrived
/// double-escaped would put `%20` in the middle of the owner's own first
/// sentence. A blank or whitespace-only topic yields the plain coach, which is
/// the same decision the route makes when it reads the query back.
String coachLocation([String? topic]) {
  final String subject = topic?.trim() ?? '';
  return subject.isEmpty
      ? Routes.coach
      : '${Routes.coach}?topic=${Uri.encodeQueryComponent(subject)}';
}

/// [coachLocation] read back — the topic in [uri], or null for the plain coach.
///
/// The other half of the round trip, and it lives beside the half that writes
/// it. It was five lines inside the route's own builder, where nothing could
/// ask it anything: a topic dropped THERE looks exactly like a caller that
/// passed none, and the coach opens with an empty box either way.
///
/// A blank or whitespace-only `topic=` is no topic, the same answer
/// [coachLocation] gives — a caller that built the query from a label it did
/// not have must not produce a coach claiming to hold a question.
String? coachTopicOf(Uri uri) {
  final String subject = uri.queryParameters['topic']?.trim() ?? '';
  return subject.isEmpty ? null : subject;
}

/// The breathing player's location for a plan [item] (a `BreathingItemKind`
/// name) or an ad hoc [pattern] id. [item] wins when both are given.
String breathingPlayerLocation({String? item, String? pattern}) {
  final String key = item != null ? 'item' : 'pattern';
  final String? value = item ?? pattern;
  return value == null
      ? Routes.breathingPlayer
      : '${Routes.breathingPlayer}?$key=${Uri.encodeQueryComponent(value)}';
}

/// Where a tapped notification with [payload] leads. Anything this app did not
/// schedule goes to the actions list, as it always did.
String notificationRoute(String payload) => switch (payload) {
  'sleep' => Routes.sleep,
  'breathing' => Routes.breathingPlan,
  _ => Routes.actions,
};

/// The query parameter the profile's focused field rides in.
const String kFocusParameter = 'focus';

/// The profile's location, opened on [focus] when there is one.
///
/// `/profile?focus=weight`. The same pattern as [coachLocation]: one builder,
/// so a caller cannot spell the field a way [profileFocusOf] does not read.
String profileLocation({ProfileField? focus}) => focus == null
    ? Routes.profile
    : '${Routes.profile}?$kFocusParameter=${focus.name}';

/// [profileLocation] read back: the field named in [uri], or null for the
/// plain profile. An unknown name is no field, the same answer a link that
/// carried none gets, rather than a guess at which field was meant.
ProfileField? profileFocusOf(Uri uri) {
  final String? raw = uri.queryParameters[kFocusParameter];
  for (final ProfileField field in ProfileField.values) {
    if (field.name == raw) {
      return field;
    }
  }
  return null;
}

/// The query parameter the selected day rides in — `?date=2026-07-29`.
///
/// The prototype's own name for it (`history-data.js`), kept so a URL read off
/// the design preview names the same day here.
const String kDateParameter = 'date';

/// Every route that carries the selected day.
///
/// `design/mobile-preview/history-data.js:10` lists **fourteen** date-aware
/// routes: `today, sleep, activity, insights, actions, recovery, body, fitness,
/// metrics, metric, sleep-history, workouts, journal, action-history`. Thirteen
/// paths carry them here because `metrics` and `metric` are one route in this
/// app — [Routes.history] with and without a `metric=` — which the router
/// records as a deliberate collapse rather than a gap.
const Set<String> kDateAwareRoutes = <String>{
  Routes.today,
  Routes.sleep,
  Routes.activity,
  Routes.insights,
  Routes.actions,
  Routes.recovery,
  Routes.body,
  Routes.fitness,
  Routes.history,
  Routes.sleepHistory,
  Routes.trends,
  Routes.workouts,
  Routes.journal,
  Routes.recommendations,
};

/// Whether [path] is one of the screens the day follows the reader onto.
///
/// The path only — a query string never decides this. A route outside the set
/// keeps whatever query it was given, because the day means nothing there and
/// stamping one on would be a parameter no screen reads.
bool isDateAwareRoute(String path) => kDateAwareRoutes.contains(path);

/// The day named in [uri], or null when it names none this app can read.
///
/// The other half of [dateLocation], and it lives beside the half that writes
/// it for the reason [coachTopicOf] does: a day dropped HERE looks exactly like
/// a link that carried none, and the screen opens on the latest day either way.
///
/// **Shape only.** `2026-02-31` is refused because it is not a day at all —
/// `DateTime` rolls it silently into March, and the app would then be showing a
/// date nobody wrote. Whether a real day is one this phone still holds is the
/// *retention* question, and that answer belongs to `ViewDate.select`, which is
/// the one place the horizon is known.
String? viewDateOf(Uri uri) {
  final String? raw = uri.queryParameters[kDateParameter];
  if (raw == null || !_isoDay.hasMatch(raw)) {
    return null;
  }
  final DateTime? parsed = DateTime.tryParse('${raw}T00:00:00Z');
  return parsed != null && parsed.toIso8601String().startsWith(raw)
      ? raw
      : null;
}

/// [location] carrying [day], or carrying none when [day] is [latest].
///
/// The parameter is **removed** on the newest day rather than written out in
/// full, which is `date-navigation.js::H.setViewDate`'s own rule
/// (`url.searchParams.delete('date')`). A link to the current day is then the
/// plain route, so it still means "the newest readings" tomorrow; a stamped one
/// would mean "that Tuesday" forever.
///
/// Every other query parameter survives, so `/history?metric=hrv` keeps its
/// metric when the day is stamped onto it.
String dateLocation(String location, String day, String latest) {
  final Uri uri = Uri.parse(location);
  final Map<String, String> query = <String, String>{...uri.queryParameters};
  if (day == latest) {
    query.remove(kDateParameter);
  } else {
    query[kDateParameter] = day;
  }
  return query.isEmpty
      ? uri.path
      : Uri(path: uri.path, queryParameters: query).toString();
}

final RegExp _isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');
