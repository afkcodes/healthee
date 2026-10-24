/// Conversations already had — the screen legacy has and this app did not.
///
/// It exists because a thread used to die with the process: the owner asked a
/// question, the app restarted, and an answer they had been charged one of
/// twenty for was gone with no record it had existed. `CoachHistoryStore` keeps
/// them now; this is where they are read back.
///
/// ## Every row is a conversation, not a question
///
/// The list shows the OPENING question, when it happened, and how many turns it
/// holds. It deliberately does not show the answer: a one-line preview of a
/// grounded reply is the same reply with its citations and its grade floor
/// removed, and that is the one form this app must not render text in. Opening
/// the thread shows the answer with everything that qualifies it.
///
/// ## Reopening continues; it does not fork
///
/// `CoachController.reopen` keeps the stored thread's id, so a question asked
/// after reopening appends to that conversation. The alternative — a copy that
/// drifts from the row it came from — would leave two records of one exchange
/// and no way to say which is the conversation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/coach/coach_history_store.dart';
import 'package:healthee/features/coach/coach_controller.dart';
import 'package:healthee/features/coach/coach_history_provider.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/list_rows.dart';
import 'package:solar_icons/solar_icons.dart';

/// The screen's name.
const String kCoachHistoryTitle = 'Your conversations.';

/// What it says when there are none.
const String kCoachHistoryEmpty = 'No conversations yet';

/// And why that is not a fault.
const String kCoachHistoryEmptyHint =
    'Ask your coach something and it will be kept here, on this phone.';

/// Past conversations, most recent first.
class CoachHistoryScreen extends ConsumerWidget {
  /// Builds the list.
  const CoachHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailPage(
    title: kCoachHistoryTitle,
    children: <Widget>[
      AsyncView<List<CoachThreadSummary>>(
        value: ref.watch(coachThreadsProvider),
        loadingLabel: 'Reading your conversations',
        errorMessage: "Couldn't read your conversations",
        onRetry: () => ref.invalidate(coachThreadsProvider),
        builder: (context, threads) => threads.isEmpty
            ? const EmptyState(
                message: kCoachHistoryEmpty,
                hint: kCoachHistoryEmptyHint,
              )
            : FlushCard(
                rows: <Widget>[
                  for (final thread in threads)
                    _ThreadRow(
                      thread: thread,
                      onOpen: () async {
                        await ref
                            .read(coachControllerProvider.notifier)
                            .reopen(thread.id);
                        if (context.mounted) {
                          context.pop();
                        }
                      },
                    ),
                ],
              ),
      ),
    ],
  );
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.onOpen});

  /// `.list-row { min-height: 72px; padding: 16px 20px }`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  final CoachThreadSummary thread;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: padding,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      thread.opening,
                      style: TypeScale.panelTitle.copyWith(color: colors.ink),
                      maxLines: 2,
                    ),
                    const SizedBox(height: Insets.xs),
                    Text(
                      coachThreadSubtitle(thread),
                      style: TypeScale.panelNote.copyWith(color: colors.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Insets.md),
              Icon(
                SolarIconsOutline.altArrowRight,
                size: 16,
                color: colors.ink2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "9 Sep · 4 turns" — when it happened and how big it is.
///
/// The DATE is the thread's own, not "2 days ago": a relative label has to be
/// recomputed to stay true and reads differently depending on when the screen
/// was opened, and this list is a record rather than a feed. Public because the
/// wording is what the test pins.
String coachThreadSubtitle(CoachThreadSummary thread) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final at = thread.lastAt.toLocal();
  final turns = thread.turns == 1 ? '1 turn' : '${thread.turns} turns';
  return '${at.day} ${months[at.month - 1]} · $turns';
}
