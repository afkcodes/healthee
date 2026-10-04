/// The coach, as a ROUTE — the prototype's own shape.
///
/// `screens-actions.js::H.screens.coach` is a full screen: `H.header(…, true)`
/// draws a back control, then `.coach-intro`, then the thread or the three
/// prompt buttons, then `.coach-form`, its `.form-note` and the data footer.
/// This app opened the same composition in a bottom sheet.
///
/// ## Why the sheet had to go rather than sit beside a route
///
/// **Five surfaces link here** — Today's entry card and its FAB, Insights,
/// `metric/:key`, the workout detail's *Discuss this workout* and the finding
/// detail's *Talk this through* — and the last two are asking about something
/// specific. A sheet cannot carry a subject in a location, cannot be deep
/// linked, and does not survive a rotation. Keeping both would be two ways in
/// with different back behaviour, which is the defect `router.dart` already
/// records one level up.
///
/// ## The topic is the OPENING MESSAGE, and now also a field
///
/// A caller's [topic] arrives as text already in the prototype's own
/// `.coach-form`, and the owner sends it. It is **not** asked automatically: a
/// question costs one of twenty per rolling thirty days, and a navigation that
/// spent one on arrival would be a charge nobody pressed anything for. That
/// half is unchanged, and it is the half the owner sees — the sentence is in
/// their input, in their words, editable or deletable before anything is sent.
///
/// `POST /api/coach` also takes an optional `topic` now, and [CoachBody] sends
/// it with every question asked from this screen. The two are different facts:
/// the seeded sentence is what the owner is ASKING, and the field is what
/// screen they came FROM, which the server could not otherwise know and which
/// it uses to rank its context and evidence. It is context and nothing else —
/// `insights/coach_thread.py` screens it with the refusal gate before any model
/// call and fences it in the prompt as a label rather than a finding, so the
/// app is not putting a claim in the server's mouth either.
///
/// ## The input cannot exist without the meter
///
/// This is the rule the whole file is built around, and it came here unchanged
/// from the sheet. A coach question costs one of twenty per rolling thirty days,
/// so the screen reads `/api/entitlement` first and **only builds an input when
/// it holds a balance that permits one**. There is no branch in which a text
/// field appears beside an unknown number: a checking state, a failed check, a
/// locked account and a spent window each render their own sentence and no box
/// to type in.
///
/// That is structural rather than careful — [CoachComposer] takes a non-null
/// remaining-or-uncapped decision as a required argument, so an input with no
/// meter behind it is not a widget this file can build. The **prompt buttons are
/// under the same rule**: a prompt asks a question, so it spends one, and
/// `CoachIntro` draws none when `onAsk` is null.
///
/// ## The meter is the server's, after every attempt
///
/// It is never decremented here. `coach_controller.dart` re-reads
/// `/api/entitlement` in a `finally`, because `routers/coach.py` refunds a
/// refusal, an unvalidated answer and a transport failure — a local subtraction
/// would be wrong in three of the five outcomes and wrong the flattering way
/// round. Nothing in this file subtracts anything.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_body.dart';
import 'package:healthee/features/coach/coach_controller.dart';
import 'package:healthee/features/coach/coach_history_provider.dart';
import 'package:healthee/features/coach/v02/coach_composer.dart';
import 'package:healthee/features/coach/v02/coach_page.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/screen_head.dart';
import 'package:solar_icons/solar_icons.dart';

// The cost-carrying label lives with the control that prints it. Re-exported so
// the screen stays the one import a caller — or a test pinning the wording —
// needs for this surface.
export 'package:healthee/features/coach/v02/coach_composer.dart'
    show CoachComposer, askLabel;

/// The prototype's own h1 and eyebrow for this surface.
const String kCoachTitle = 'Your coach.';

/// Its eyebrow.
/// `.form-note` — what an answer carries, said before one arrives.
const String kCoachFormNote =
    'Answers name the research notes behind them and the weakest grade among '
    'those notes. The coach says when it does not know.';

/// The coach conversation, its meter, and the input the meter licenses.
class CoachScreen extends ConsumerStatefulWidget {
  /// [topic] is an opening question a caller wants asked about a specific
  /// workout, finding or metric. [now] is injected by tests so "reopens in …"
  /// is deterministic.
  const CoachScreen({this.topic, this.now, super.key});

  /// The opening question, or null for the plain coach.
  final String? topic;

  /// The instant the reset countdown is measured against.
  final DateTime? now;

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

/// Stateful for ONE reason: the thread's scroll position. A chat reads from
/// the bottom — the question just sent, the dots, the answer as it arrives —
/// and something has to own the controller that keeps the end in view.
class _CoachScreenState extends ConsumerState<CoachScreen> {
  final ScrollController _scroll = ScrollController();

  String? get topic => widget.topic;
  DateTime? get now => widget.now;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keep the thread's end in view — after the frame that added the content,
  /// because the new extent does not exist until then.
  void _stickToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      final double end = _scroll.position.maxScrollExtent;
      if (end - _scroll.offset < 1) {
        return;
      }
      _scroll.animateTo(
        end,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Every change to the thread — a question sent, the dots appearing, an
    // answer landing — moves the end of the list; follow it.
    ref.listen(coachControllerProvider, (previous, next) {
      if (previous?.entries.length != next.entries.length ||
          previous?.asking != next.asking) {
        _stickToEnd();
      }
    });
    // The entitlement is watched TWICE and that is not a duplicate read: Riverpod
    // serves one value to both. The body needs it resolved (it renders the meter
    // and the thread), and the pinned composer needs it too — and the composer
    // cannot live inside the `AsyncView`, because the whole point of pinning it
    // is that it does not sit in the scrolling column.
    final entitlement = ref.watch(coachEntitlementProvider);
    final conversation = ref.watch(coachControllerProvider);
    // Whether there is anything to show. A loading or failed read yields false,
    // so the control is absent rather than opening a screen that cannot answer.
    final bool hasHistory =
        ref.watch(coachThreadsProvider).value?.isNotEmpty ?? false;
    return CoachPage(
      title: kCoachTitle,
      controller: _scroll,
      actions: <Widget>[
        // Only when there is something to look at. `HeaderAction` draws nothing
        // for a null callback, so an owner who has never asked anything is not
        // offered a door into an empty room.
        HeaderAction(
          icon: SolarIconsOutline.history,
          tooltip: 'Past conversations',
          onPressed: hasHistory
              ? () => context.push(Routes.coachHistory)
              : null,
        ),
        // Only once there is a conversation to leave. An empty thread offering
        // to be replaced is a control that does nothing.
        if (!conversation.isEmpty && !conversation.asking)
          HeaderAction(
            icon: SolarIconsOutline.pen,
            tooltip: 'Start a new conversation',
            onPressed: ref.read(coachControllerProvider.notifier).newThread,
          ),
      ],
      // THE RULE SURVIVES THE SPLIT. `CoachComposer` still takes a non-null
      // meter, and here it is built only from a RESOLVED entitlement that
      // permits a question. While the read is in flight or has failed there is
      // no footer at all — not a disabled one — which is the same structural
      // guarantee as before, expressed in the place the control now lives.
      footer: switch (entitlement.value) {
        final Entitlement e when coachPermits(e) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The note describes what an ANSWER carries, so it belongs beside
            // the control that asks for one. Left in the scrolling column it
            // ended a block of content with 600 pt of nothing beneath it, which
            // is what "why is it floating" was about — and it was describing a
            // thing the owner had to scroll away from it to trigger.
            Text(
              kCoachFormNote,
              style: TypeScale.formNote.copyWith(color: context.colors.ink2),
            ),
            CoachComposer(
              asking: conversation.asking,
              remaining: e.allowanceFor(kCoachFeature)?.remaining,
              initialQuestion: conversation.isEmpty ? topic : null,
              onAsk: (question) => unawaited(
                ref
                    .read(coachControllerProvider.notifier)
                    .ask(question, topic: topic),
              ),
            ),
          ],
        ),
        _ => const SizedBox.shrink(),
      },
      children: <Widget>[
        // The meter is re-read after EVERY answer (`coach_controller.ask`'s
        // finally), and this column is the whole thread. Rendering the thread
        // through the meter's own loading/error states meant one failed
        // re-read on a phone network replaced a just-delivered answer with
        // "Couldn't read what your account includes" — the answer "went off".
        // Once a balance has ever been read, the thread stays on the last known
        // balance and a failed refresh is a one-line notice with a retry.
        if (entitlement.hasValue) ...<Widget>[
          if (entitlement.hasError)
            _BalanceRefreshFailed(
              onRetry: () => ref.invalidate(coachEntitlementProvider),
            ),
          CoachBody(
            entitlement: entitlement.value!,
            topic: topic,
            now: now,
            onGrow: _stickToEnd,
          ),
        ] else
          AsyncView<Entitlement>(
            value: entitlement,
            loadingLabel: 'Checking what your account includes',
            errorMessage: "Couldn't read what your account includes",
            onRetry: () => ref.invalidate(coachEntitlementProvider),
            builder: (context, resolved) => CoachBody(
              entitlement: resolved,
              topic: topic,
              now: now,
              onGrow: _stickToEnd,
            ),
          ),
      ],
    );
  }
}

/// What a failed balance re-read says when there is already a thread to keep.
const String kCoachBalanceRefreshFailed =
    "Couldn't refresh your question balance. The thread and the last known "
    'balance are shown as they were.';

class _BalanceRefreshFailed extends StatelessWidget {
  const _BalanceRefreshFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              kCoachBalanceRefreshFailed,
              style: TypeScale.formNote.copyWith(color: context.colors.ink2),
            ),
          ),
          const SizedBox(width: Insets.md),
          HLinkButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}
