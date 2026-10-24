/// "What I watch": what the coach reads, when it reviews, and how to end the
/// plan. Ending is a confirmed write through the commitment repository.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The end row's title.
const String kEndPlan = 'End plan';

/// What the end row promises.
const String kEndPlanBody = 'Stops the job. Your record stays.';

/// The card. [watchTitle] names the metric the strap decides on.
class ProgramWatchCard extends StatelessWidget {
  /// [onEnd] null hides the End plan row: only an active plan can be ended.
  const ProgramWatchCard({required this.watchTitle, this.onEnd, super.key});

  /// `Active minutes, daily`.
  final String watchTitle;

  /// Confirmed end.
  final Future<void> Function()? onEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[
      _Row(
        title: watchTitle,
        body: 'From the strap. This decides done or missed.',
      ),
      const _Row(
        title: 'Sunday review',
        body: 'What you did, what moved, next week\'s job. Every week.',
      ),
      if (onEnd case final end?)
        _Row(
          title: kEndPlan,
          body: kEndPlanBody,
          onTap: () => _confirm(context, end),
        ),
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.md),
                child: Divider(
                  height: hairline,
                  thickness: hairline,
                  color: colors.line,
                ),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    Future<void> Function() end,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this plan?'),
        content: const Text('The job stops. Your record stays.'),
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
    if (yes ?? false) {
      await end();
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.body, this.onTap});

  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TypeLadder.bodyStrong.copyWith(color: colors.ink)),
          Text(body, style: TypeLadder.callout.copyWith(color: colors.ink2)),
        ],
      ),
    );
  }
}
