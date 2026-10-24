/// What to do tonight, on Today: the server's one sleep lever, under the three
/// key numbers.
///
/// It is `/api/sleep/consistency`'s `tonight` block drawn by the same
/// [TonightPanel] Sleep uses, so the advice is the server's grounded line with
/// its research notes behind the ⓘ, never a sentence written on the phone.
/// Nothing is drawn while it loads, when it fails, when the server has no
/// lever, or on a past day: tonight is about the wall clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';
import 'package:healthee/shared/states/current_account_value.dart';

/// The lever, or nothing.
class TodayTonight extends ConsumerWidget {
  /// [live] is false on a past day.
  const TodayTonight({required this.live, super.key});

  /// Whether the day being read is today.
  final bool live;

  /// Above the card.
  static const double gap = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!live) {
      return const SizedBox.shrink();
    }
    final consistency = currentAccountValue(
      ref.watch(sleepConsistencyProvider),
    ).value;
    if (consistency?.tonight case final TonightLever lever) {
      return Padding(
        padding: const EdgeInsets.only(top: gap),
        child: TonightPanel(lever: lever),
      );
    }
    return const SizedBox.shrink();
  }
}
