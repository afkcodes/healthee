/// `.coach-form` — the input, and the cost printed on the control beside it.
///
/// ```css
/// .coach-form       { display:flex; gap:8px; margin-top:24px }
/// .coach-form input { width:100%; min-height:48px; padding:12px;
///                     border-radius:12px; border:1px solid var(--rule);
///                     background:var(--surface); font-size:16px }
/// .form-note        { font-size:10px; margin-block:16px }
/// ```
///
/// ## The one substitution on this screen, and why it is forced
///
/// The prototype's send control is an **arrow with no label**, because a scripted
/// preview costs nothing. A question here costs one of twenty per rolling thirty
/// days, and the rule is that the cost is on the button *before* the tap — a
/// meter at the top of a sheet and a bare arrow at the bottom is still a spend
/// the owner has to remember to have read about.
///
/// So the button carries `Ask — uses 1 of your 17` **and** the prototype's arrow.
/// A label that long does not fit beside an input at 320 px, so the row is
/// measured: it stays the prototype's single row wherever the label and a usable
/// input both fit, and the button drops to its own full-width line where they do
/// not. That is the rendered result of the same CSS at a narrower width, which is
/// the rule for anything Flutter cannot express directly.
///
/// ## It cannot be constructed without a decision about the balance
///
/// [remaining] is `int?` and means *how many are left, or uncapped* — it is never
/// "unknown". A screen that has not read the meter does not build this widget at
/// all; see `coach_screen.dart`.
///
/// ## [initialQuestion] is how a subject reaches the OWNER
///
/// *Discuss this workout* and *Talk this through* arrive as text already in this
/// box — **written, not sent**. Sending it on arrival would spend one of twenty
/// on a navigation, and the standing rule on this surface is that a spend
/// follows a press.
///
/// This is the owner-facing half of a topic and it stays exactly that: a
/// sentence they can read, edit or delete before it costs anything. The server
/// learns the subject separately, through `POST /api/coach`'s optional `topic`
/// field (`coach_screen.dart`); this widget knows nothing about that and does
/// not need to.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// What the send control ANNOUNCES. Public so a test can pin the wording.
///
/// It is no longer printed. The full-width "Ask — uses 1 of your 16" bar said the
/// same thing the meter says three lines above it, and saying a fact twice is not
/// twice as honest — it was redundancy wearing honesty's clothes, and it made the
/// composer the loudest object on a screen it should sit quietly at the bottom of.
///
/// It survives as the control's accessible name, and that is not a downgrade: a
/// screen reader reads controls rather than pages, so for anyone using one this
/// string is the ONLY place the cost of a press is stated. Deleting it outright
/// would have removed the cost for exactly the people who cannot see the meter.
String askLabel(int? remaining) =>
    remaining == null ? 'Ask' : 'Ask — uses 1 of your $remaining';

/// The input a permitting balance licenses.
class CoachComposer extends StatefulWidget {
  /// [remaining] is the server's own count, or null for an uncapped account.
  const CoachComposer({
    required this.asking,
    required this.remaining,
    required this.onAsk,
    this.initialQuestion,
    super.key,
  });

  /// `margin-top: 24px`.
  static const double topGap = 24;

  /// `gap: 8px`.
  static const double gap = 8;

  /// `min-height: 48px`.
  static const double fieldHeight = 48;

  /// `border-radius: 12px`.
  static const double fieldRadius = 12;

  /// The narrowest an input may be and still be one — under this the row wraps.
  /// The narrowest the input may be and still be an input.
  ///
  /// Was 132, and 132 was measured against the wrong thing: it is wide enough to
  /// *draw* a field, not wide enough to *read* one. On the owner's 360 pt phone the
  /// row branch left the field at almost exactly 132, and after the field's own 12 pt
  /// padding each side the hint had ~108 pt for text that wants ~140 — so
  /// "What's on your mind?" wrapped onto two lines inside a one-line box and the
  /// composer read as a broken label rather than somewhere to type.
  ///
  /// 190 is the hint on one line with its padding and a little slack. Below it the
  /// column branch takes over, which is the better layout on a phone anyway: this
  /// button carries the meter ("Ask — uses 1 of your 16") rather than the prototype's
  /// bare arrow, and a cost the owner is about to spend has earned its own full-width
  /// row.
  /// `.send { width: 44px; height: 44px }` — a circular control, legacy's shape.
  static const double sendSize = 44;

  /// The glyph inside it.
  static const double sendIcon = 20;

  /// Whether a question is in flight.
  final bool asking;

  /// How many are left, or null when the account is uncapped.
  final int? remaining;

  /// The opening question a caller opened this screen about. Written into the
  /// field once, on first build; never sent by itself.
  final String? initialQuestion;

  /// Asks one.
  final void Function(String question) onAsk;

  @override
  State<CoachComposer> createState() => _CoachComposerState();
}

class _CoachComposerState extends State<CoachComposer> {
  late final TextEditingController _controller = TextEditingController(
    // Once, in `initState`'s position. A topic re-applied on every build would
    // erase whatever the owner had typed over it, and a topic applied in
    // `didUpdateWidget` would do it again on the next rebuild of the parent.
    text: widget.initialQuestion ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final question = _controller.text.trim();
    if (question.isEmpty || widget.asking) {
      return;
    }
    _controller.clear();
    widget.onAsk(question);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bool ready = !widget.asking;
    return Padding(
      padding: const EdgeInsets.only(top: CoachComposer.topGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: ready,
              minLines: 1,
              maxLines: 4,
              style: TypeScale.inputText.copyWith(color: colors.ink),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Ask your coach…',
                isDense: true,
                contentPadding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(
                  minHeight: CoachComposer.fieldHeight,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    CoachComposer.fieldRadius,
                  ),
                  borderSide: BorderSide(color: colors.rule, width: hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    CoachComposer.fieldRadius,
                  ),
                  borderSide: BorderSide(color: colors.rule, width: hairline),
                ),
              ),
            ),
          ),
          const SizedBox(width: CoachComposer.gap),
          Semantics(
            // The cost is stated once, in the meter above. The BUTTON still has
            // to carry it for anyone who cannot see the meter — a screen reader
            // reads controls, not the whole page, and "send" alone would be the
            // one place this app failed to say what a press costs.
            label: askLabel(widget.remaining),
            button: true,
            child: SizedBox(
              width: CoachComposer.sendSize,
              height: CoachComposer.sendSize,
              child: Material(
                color: ready ? colors.accent : colors.surface2,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: ready ? _send : null,
                  customBorder: const CircleBorder(),
                  child: Icon(
                    SolarIconsOutline.arrowUp,
                    size: CoachComposer.sendIcon,
                    color: ready ? colors.onAccent : colors.ink2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
