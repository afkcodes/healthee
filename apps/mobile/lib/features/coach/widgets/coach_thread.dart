/// The conversation, drawn — `.coach-message` in its two shapes, plus trouble.
///
/// ```css
/// .coach-message      { margin-top:20px; padding:16px; border-radius:18px;
///                       font-size:12px; line-height:1.9;
///                       background:var(--surface); color:var(--ink);
///                       border:1px solid var(--line) }
/// .coach-message.user { background:var(--accent-soft); margin-left:28px;
///                       border:0 }
/// ```
///
/// The coach's own prose goes through [GroundedProse] like every other field a
/// model wrote in this app: the raw string with its `[note_id]` markers rendered
/// rather than printed.
///
/// Its sources sit behind the ⓘ at the foot of the bubble, not under the
/// sentence — the owner asked three times for citation chips off the surfaces
/// that carry prose, and a reply that cited four notes was four stamps of chrome
/// under every answer. An answer that cites nothing draws no ⓘ at all.
///
/// Two pieces of response metadata ride in that sheet rather than beside it:
///
///   * **`grade_floor`** — the weakest evidence grade among the notes cited. It is
///     the answer's own statement of how firm it is, and `INTELLIGENCE §3` makes
///     it part of the response rather than a nicety. `null` means nothing
///     gradeable was cited, which is not a weak grade and is not rendered as one.
///   * **`validated: false`** — the blocking validator rejected the model's answer
///     and the honest fallback shipped. That is the product working, and it is
///     also not the answer the owner asked for, so it says both.
///
/// A [CoachTrouble] wears the same bubble. It is not an error banner: a failure
/// that looked different from the rest of the thread would read as the app
/// breaking rather than as an answer about the question that was asked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:healthee/features/coach/widgets/coach_reveal.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/grounded_text.dart';

/// What the coach's grounding sheet calls itself.
const String kCoachSourcesTitle = 'What this answer is based on';

/// One entry of the thread.
class CoachEntryView extends StatelessWidget {
  const CoachEntryView({required this.entry, this.onGrow, super.key});

  static const double topGap = 20;
  static const double padding = 14;
  static const double radius = 18;

  /// How much of the row the owner's bubble may take — a chat's own rule: the
  /// question sits right and short, the answer runs the width like prose.
  static const double questionShare = 0.82;

  final CoachEntry entry;

  /// Called each time a live reply reveals another piece, so the thread can
  /// keep its end in view while the text is still arriving.
  final VoidCallback? onGrow;

  @override
  Widget build(BuildContext context) {
    // Exhaustive over the sealed union: a fourth kind is a compile error here
    // rather than a row that draws nothing.
    return switch (entry) {
      OwnerQuestion(:final text) => _QuestionBubble(text: text),
      CoachReply(:final answer, :final live) => _Reply(
        answer: answer,
        live: live,
        onGrow: onGrow,
      ),
      final CoachTrouble trouble => CoachBubble(
        child: _Trouble(trouble: trouble),
      ),
    };
  }
}

/// The owner's turn: a short bubble at the trailing edge, the way every chat
/// draws the person typing. `accentSoft`, which is the colour of an ACTION in
/// this app — asking is one. It says nothing about the owner's body, which is
/// the only thing `fav`/`unf`/`alert` are allowed to say.
class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: CoachEntryView.topGap),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FractionallySizedBox(
          widthFactor: CoachEntryView.questionShare,
          alignment: AlignmentDirectional.centerEnd,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CoachEntryView.padding + 2,
                vertical: CoachEntryView.padding - 2,
              ),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(CoachEntryView.radius),
                  topRight: Radius.circular(CoachEntryView.radius),
                  bottomLeft: Radius.circular(CoachEntryView.radius),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(
                text,
                style: TypeScale.coachBody.copyWith(color: colors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered coach-side box — kept for notices (a refusal, a failed request),
/// which are cards about the request, not prose from the coach.
class CoachBubble extends StatelessWidget {
  const CoachBubble({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: CoachEntryView.topGap),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CoachEntryView.padding + 2),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(CoachEntryView.radius),
        ),
        child: child,
      ),
    );
  }
}

/// The coach's turn: prose at the leading edge, no box — the way a chat draws
/// the other party. A live reply appears a sentence at a time (`coach_reveal`);
/// one from history is shown whole. The sources dot and the fallback notice
/// arrive with the last piece, because a citation for text not yet on screen is
/// a claim about nothing.
class _Reply extends StatefulWidget {
  const _Reply({required this.answer, required this.live, this.onGrow});

  final CoachAnswer answer;
  final bool live;
  final VoidCallback? onGrow;

  @override
  State<_Reply> createState() => _ReplyState();
}

class _ReplyState extends State<_Reply> {
  late final List<int> _cuts = revealCuts(widget.answer.reply);
  late int _shown = widget.live ? 0 : _cuts.length;
  Timer? _timer;

  bool get _complete => _shown >= _cuts.length;

  @override
  void initState() {
    super.initState();
    if (!_complete) {
      _timer = Timer.periodic(revealInterval(_cuts.length), _step);
    }
  }

  void _step(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    setState(() => _shown += 1);
    widget.onGrow?.call();
    if (_complete) {
      timer.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _visible => _complete || _shown == 0
      ? (_complete ? widget.answer.reply : '')
      : widget.answer.reply.substring(0, _cuts[_shown - 1]);

  MetricDetail get _detail => MetricDetail.grounded(
    groundingOf(widget.answer.reply, alsoCites: widget.answer.citations),
    grade: widget.answer.gradeFloor,
    title: kCoachSourcesTitle,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final answer = widget.answer;
    final detail = _detail;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_complete && !answer.validated) ...<Widget>[
          Text(
            "The coach couldn't answer that one to its own standard, so this "
            'is the honest fallback rather than the answer you asked for. It '
            'was not counted against your questions.',
            style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
          ),
          const SizedBox(height: 12),
        ],
        GroundedProse(
          text: _visible,
          style: TypeScale.coachBody.copyWith(color: colors.ink),
        ),
        // At the foot, right-aligned, only once the whole answer is on screen,
        // and drawing nothing at all when the answer cited nothing.
        if (_complete && detail.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: MetricInfoDot(null, detail: detail),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: CoachEntryView.topGap),
      // `!live` is exactly "a draft was on screen for this answer" (see
      // `CoachController.ask`) — the words were already there, so there is
      // nothing to reveal a sentence at a time, only a swap from the muted
      // draft ink to the answer's own. A short cross-fade says that swap
      // happened; a bare replacement would read as a flicker.
      child: widget.live
          ? body
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 150),
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: body,
            ),
    );
  }
}

class _Trouble extends StatelessWidget {
  const _Trouble({required this.trouble});

  final CoachTrouble trouble;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          trouble.message,
          style: TypeScale.rowTitle.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 8),
        Text(
          // Never silent about the meter. "A spend must never be silent" cuts
          // both ways: a question that was NOT charged has to say so too, or
          // the owner is left counting their own. And the third thing it cuts
          // against is the one that shipped — a denial the app could not know
          // was true. The server charges inside the gate before the handler
          // starts, so once the request has left, only the number is authority.
          switch (trouble.charge) {
            CoachCharge.notCharged =>
              'Nothing was counted for this. The number above is the '
                  'server’s own, re-read just now.',
            CoachCharge.unknown =>
              'We could not confirm whether this was counted. The number '
                  'above is the server’s own, re-read just now.',
          },
          style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
        ),
      ],
    );
  }
}
