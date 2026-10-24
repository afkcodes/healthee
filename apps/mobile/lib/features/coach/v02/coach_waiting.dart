/// What the owner looks at while the coach thinks — for up to five minutes.
///
/// It replaced `LoadingState(label: 'Asking your coach')`: one 16 px spinner and
/// four words, held for a wait that was **measured at 80–304 seconds** on the
/// owner's own broad question. A spinner is a fine way to say "a moment"; held
/// for four minutes it says "this has hung", and the owner's own report was that
/// the coach "takes insane amount of time" — which was true, and the screen was
/// doing nothing to make the time legible.
///
/// ## The stage shown is the wire's, never invented
///
/// `POST /api/coach/stream` names its own progress (`data/coach/coach_stream_
/// event.dart`'s `CoachStage`), so this widget can say what the server is
/// actually doing instead of a description of the whole operation. The rule
/// this file was built to keep is unchanged, only its instrument improved: a
/// stepper advancing on a TIMER would be inventing server state and showing it
/// as fact, which is the exact move the honesty contract forbids. [progress]
/// is null until the first `stage` event lands — before that, and against an
/// older server that falls back to the non-streaming call, this widget says
/// exactly what it always said, because that is still all it knows.
///
/// So what is shown is only what is actually known:
///
/// * the elapsed time, counted here and true by construction;
/// * [progress]'s own stage, worded by [coachStageLabel] — or, before the
///   first one arrives, the same whole-operation sentence this screen showed
///   before streaming existed;
/// * after [_longAfter], a second sentence saying the wait is longer than usual
///   and that broad questions take more rounds. That is a statement about the
///   distribution, not about this request, and it is the honest way to say
///   "still working" without pretending to know why.
///
/// ## "You can leave this screen"
///
/// The one piece of genuinely useful news, and it is checked rather than hoped:
/// `CoachController` is `@Riverpod(keepAlive: true)`, so the request is owned by
/// the provider and not by this widget. Popping the route does not cancel it and
/// the answer is in the thread on return. Told to the owner because a four-minute
/// wait they are required to sit through is a different product from one they can
/// walk away from.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:healthee/features/coach/widgets/coach_thread.dart';
import 'package:healthee/shared/states/grounded_text.dart';

/// The panel shown while a question is in flight.
///
/// ## Once a draft has arrived, this stops being a spinner and starts being
/// the coach's next turn beginning
///
/// The owner decided the coach should "feel like claude — stream it as it
/// starts and swap": once [draft] is non-null this widget draws a compact
/// status line (the same dots, the same stage label, smaller) over the
/// draft's own prose, in the muted ink rather than the answer's full one —
/// it has not been checked yet. [draft] replaces wholesale on every update
/// (never appended to), so the prose here just needs to redraw with whatever
/// it was last given; [onGrow] is called on every such update so the thread
/// this panel sits in can follow the text growing, the same contract
/// `_ReplyState` already keeps for a live reply.
class CoachWaiting extends StatefulWidget {
  /// [progress] is the latest stage `CoachController` has seen for this
  /// question, or null before the first one arrives. [draft] is the latest
  /// `draft` event's prose, or null before one arrives (or when the server
  /// never sends one). [onGrow] fires once per [draft] update.
  const CoachWaiting({this.progress, this.draft, this.onGrow, super.key});

  /// The stage to describe. Null draws the pre-streaming sentence.
  final CoachStageEvent? progress;

  /// The in-flight draft, or null before one has arrived this turn.
  final CoachDraft? draft;

  /// Called each time [draft] is replaced, so the thread can keep its end in
  /// view while the draft is still growing.
  final VoidCallback? onGrow;

  @override
  State<CoachWaiting> createState() => _CoachWaitingState();
}

/// The default description, before any [CoachStageEvent] has arrived — the
/// exact sentence this screen showed before streaming existed, and what it
/// still shows against a server old enough to fall back to the plain call.
const String _beforeAnyStage =
    'Reading your own data and the graded research, then writing an answer '
    'that cites both.';

/// [progress]'s own words, in this app's copy — never the wire's raw name.
///
/// Public so a test can pin the mapping directly rather than only through the
/// widget it feeds.
String coachStageLabel(CoachStageEvent progress) => switch (progress.stage) {
  CoachStage.context => 'Reading your data',
  CoachStage.thinking => 'Thinking it through',
  CoachStage.tool => _toolLabel(progress.detail),
  CoachStage.checking => 'Checking the citations',
  CoachStage.revising => 'Rewording to match the evidence',
};

/// The named tools get their own sentence; anything else is still true and
/// still honest without naming a tool the owner has never heard of.
String _toolLabel(String? tool) => switch (tool) {
  'query_metric' => 'Looking at your numbers',
  'compare_event' => 'Comparing your days',
  'get_knowledge' => 'Checking the research',
  'sleep_consistency' => 'Looking at your sleep pattern',
  _ => 'Looking something up',
};

/// When the wait stops being ordinary. The measured distribution on the owner's
/// own broad question was 80 · 82 · 132 · 169 · 277 · 304 s, so a minute is well
/// inside "normal" and saying so early would be crying wolf at the median.
const Duration _longAfter = Duration(seconds: 75);

class _CoachWaitingState extends State<CoachWaiting>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late final AnimationController _pulse;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // One second is the coarsest tick that still reads as a live clock. Anything
    // finer would repaint sixty times a minute to move a digit that changes once.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant CoachWaiting oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fires once per draft replacement, never on the stage or the clock
    // ticking — the thread only needs to re-stick to the end when there is
    // more text to see.
    final CoachDraft? draft = widget.draft;
    final bool grew =
        draft != null &&
        (oldWidget.draft?.round != draft.round ||
            oldWidget.draft?.text != draft.text);
    if (grew) {
      widget.onGrow?.call();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final CoachDraft? draft = widget.draft;
    if (draft != null) {
      return _draftPanel(colors, draft);
    }
    final bool long = _elapsed >= _longAfter;
    final String stage = widget.progress == null
        ? _beforeAnyStage
        : coachStageLabel(widget.progress!);
    // No box: this is the coach's next turn beginning, drawn where its prose
    // will appear — three breathing dots, what it is doing right now, and the
    // time it has taken so far. Everything a chat shows while the other party
    // is typing, and nothing that claims more than the wire has said.
    return Padding(
      padding: const EdgeInsets.only(top: CoachEntryView.topGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _TypingDots(pulse: _pulse, color: colors.ink2),
              const SizedBox(width: Insets.md),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  // The switcher centres by default; a status line reads from
                  // the leading edge like the prose it stands in for.
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: <Widget>[...previous, ?current],
                  ),
                  child: Text(
                    stage,
                    key: ValueKey<String>(stage),
                    style: TypeScale.panelNote.copyWith(color: colors.ink2),
                  ),
                ),
              ),
              const SizedBox(width: Insets.md),
              Text(
                _clock(_elapsed),
                style: TypeScale.panelUnit.copyWith(
                  color: colors.ink2,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          if (long) ...<Widget>[
            const SizedBox(height: Insets.sm),
            Text(
              'Taking longer than most questions — broad ones need more rounds. '
              'You can leave; the answer will be here when you come back.',
              style: TypeScale.panelNote.copyWith(color: colors.ink2),
            ),
          ],
        ],
      ),
    );
  }

  /// Once a draft has arrived: a compact status line — the same dots, the
  /// same stage label, smaller and with no clock, because there is now
  /// something more useful under it than a number of seconds — over the
  /// draft's own prose, unchecked and drawn muted (`colors.ink2`) rather
  /// than the full ink an answer gets, through the same [GroundedProse]
  /// every reply uses so a `[note_id]` marker in a draft looks exactly like
  /// one in the validated text once it lands.
  Widget _draftPanel(HealtheeColors colors, CoachDraft draft) {
    final String stage = widget.progress == null
        ? _beforeAnyStage
        : coachStageLabel(widget.progress!);
    return Padding(
      padding: const EdgeInsets.only(top: CoachEntryView.topGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _TypingDots(pulse: _pulse, color: colors.ink2),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: <Widget>[...previous, ?current],
                  ),
                  child: Text(
                    stage,
                    key: ValueKey<String>(stage),
                    style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          GroundedProse(
            text: draft.text,
            style: TypeScale.coachBody.copyWith(color: colors.ink2),
          ),
        ],
      ),
    );
  }
}

/// Three dots breathing in sequence — the one animation every chat reader
/// already knows means "the other side is writing".
class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.pulse, required this.color});

  final Animation<double> pulse;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < 3; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Opacity(
              opacity: _phase(pulse.value, i),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Each dot peaks a third of a cycle after the one before it.
  static double _phase(double t, int i) {
    final double x = (t - i / 3) % 1;
    final double wave = x < 0.5 ? x * 2 : (1 - x) * 2;
    return 0.3 + 0.7 * wave;
  }
}

String coachElapsedLabel(Duration elapsed) => _clock(elapsed);

String _clock(Duration elapsed) {
  final int seconds = elapsed.inSeconds;
  if (seconds < 60) {
    return '${seconds}s';
  }
  final String rest = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$rest';
}
