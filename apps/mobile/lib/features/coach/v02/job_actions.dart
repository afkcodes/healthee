/// The job's buttons: "I'm in", "Change time", and a quiet "End plan".
///
/// "I'm in" adopts the job's challenge. "Change time" edits ONLY the slot.
/// "End plan" asks first, stops the job and keeps the record. None of them
/// writes a verdict; those come from the strap.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/slot_repository.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/data/coach/review_models.dart';
import 'package:healthee/data/coach/review_repository.dart';
import 'package:healthee/shared/v02/buttons.dart';

/// `at 7:30 pm`: the words a slot is written in.
String slotText(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  return 'at $hour:$minute ${time.period == DayPeriod.am ? 'am' : 'pm'}';
}

/// The buttons under a job.
class JobActions extends ConsumerStatefulWidget {
  /// Buttons for [job]; [adopted] says whether it is already running.
  const JobActions({required this.job, required this.adopted, super.key});

  /// The job.
  final ReviewJob job;

  /// Whether the owner already said yes.
  final bool adopted;

  @override
  ConsumerState<JobActions> createState() => _JobActionsState();
}

class _JobActionsState extends ConsumerState<JobActions> {
  bool _busy = false;

  Future<void> _run(String what, Future<void> Function() act) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await act();
      ref
        ..invalidate(challengeFeedProvider)
        ..invalidate(coachLedgerProvider);
    } on Object catch (error, stack) {
      AppLog.failure('coach', what, error, stack);
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('Could not $what. Try again.')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _adopt() => _run('start the job', () async {
    final repository = await ref.read(commitmentRepositoryProvider.future);
    await repository.challengeAction(widget.job.challengeId, 'adopt');
  });

  Future<void> _changeTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (picked == null || !mounted) {
      return;
    }
    final slot = slotText(picked);
    await _run('change the time', () async {
      final repository = await ref.read(slotRepositoryProvider.future);
      await repository.setSlot(widget.job.challengeId, slot);
      ref.read(coachReviewProvider.notifier).setSlot(slot);
    });
  }

  Future<void> _endPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this plan?'),
        content: const Text(
          'The job stops. Everything the strap checked so far stays in '
          'your record.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep plan'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End plan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run('end the plan', () async {
      final repository = await ref.read(commitmentRepositoryProvider.future);
      await repository.challengeAction(widget.job.challengeId, 'abandon');
    });
  }

  @override
  Widget build(BuildContext context) {
    final change = HButton(
      label: 'Change time',
      kind: HButtonKind.secondary,
      full: true,
      onPressed: _busy ? null : () => unawaited(_changeTime()),
    );
    if (!widget.adopted) {
      return Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: HButton(
              label: "I'm in",
              full: true,
              onPressed: _busy ? null : () => unawaited(_adopt()),
            ),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(flex: 2, child: change),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: change),
        const SizedBox(width: Insets.sm),
        _QuietButton(
          label: 'End plan',
          onPressed: _busy ? null : () => unawaited(_endPlan()),
        ),
      ],
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(Radii.button),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 88),
        child: Center(
          child: Text(
            label,
            style: TypeLadder.bodyStrong.copyWith(color: context.colors.ink2),
          ),
        ),
      ),
    ),
  );
}
