/// The openers — chips under a caption, the shape the legacy coach used.
///
/// ## Where this shape comes from
///
/// `healthee-legacy/design_reference/project/screens/v2-coach.png` puts its
/// suggested questions directly under the coach's own message as small pills —
/// *"How did I sleep last night?"*, *"Am I ready for a har…"* — beneath a
/// small-caps `ASK YOUR COACH` caption. They read as things you might say next,
/// which is what they are, rather than as destinations.
///
/// This app has been through three shapes for them and each was worse for a
/// reason worth keeping:
///
/// * **three `.prompt-button` boxes** (the v02 prototype's own) — three borders
///   and three gaps between the masthead and the composer, and they pushed the
///   ask box off the bottom of the owner's phone;
/// * **a `.card.flush` of `V02ListRow`s** — one border instead of three, but that
///   row forces a tone-tinted `IconTile`, so three FITNESS-GREEN squares landed
///   on a screen whose every other accent is amber, and it elides its title at
///   one line, which would have truncated the questions themselves;
/// * **chips**, which is where legacy started. A question is a short phrase, not
///   a row: it wants to sit on the line with its neighbours and wrap when it runs
///   out of room, and it needs no icon at all to say what it is.
///
/// ## Still gated by the balance, and still structurally
///
/// A prompt asks a question, so it spends one of the owner's twenty. [onAsk] is
/// **nullable and required** for that reason and no other: a caller cannot build
/// this widget without having decided whether a question may be spent, and null
/// draws the chips as ABSENT rather than as disabled decoration. `test/mutations.sh`
/// breaks that on purpose to check it is real.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/v02/labels.dart';

/// The caption above them — legacy's `ASK YOUR COACH`, in this app's voice.
const String kCoachPromptsLabel = 'OR ASK ONE OF THESE';

/// The openers, or nothing at all when none may be spent.
class CoachPrompts extends StatelessWidget {
  /// [onAsk] of null draws no chips — absent, never disabled. [prompts] are the
  /// questions to offer, which `coach_openers.dart` builds from the owner's own
  /// figures where it can and fills with the generic ones where it cannot.
  const CoachPrompts({required this.prompts, required this.onAsk, super.key});

  /// The questions offered, in order.
  final List<String> prompts;

  /// `.chip { gap: 8px }` between chips, both axes.
  static const double gap = 8;

  /// Asks one of [kCoachPrompts]. Null builds nothing.
  final void Function(String question)? onAsk;

  @override
  Widget build(BuildContext context) {
    final ask = onAsk;
    if (ask == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const TinyLabel(kCoachPromptsLabel),
        const SizedBox(height: Insets.md),
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final prompt in prompts)
              _PromptChip(prompt: prompt, onPressed: () => ask(prompt)),
          ],
        ),
      ],
    );
  }
}

/// One opener, as a pill.
///
/// No icon and no chevron. Legacy's chips carry neither, and both would be
/// decoration on a control whose entire content is the sentence it will send.
/// The border is `--line` and the ground `--surface`, so the chips recede and
/// the Ask button — the control that actually spends — keeps the only accent on
/// the screen.
class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.prompt, required this.onPressed});

  /// `.chip { padding: 10px 14px }`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 10,
  );

  /// `.chip { border-radius: 999px }` — a pill, so it reads as speech.
  static const double radius = 999;

  final String prompt;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(
            prompt,
            style: TypeScale.panelNote.copyWith(color: colors.ink2),
          ),
        ),
      ),
    );
  }
}
