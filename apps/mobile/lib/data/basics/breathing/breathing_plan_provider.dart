/// The plan for today, from the real store, the real settings and the server's
/// overnight HRV card.
library;

import 'package:healthee/data/basics/breathing/breathing_history.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_builder.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/data/notifications/notification_providers.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/shared/v02/reading_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'breathing_plan_provider.g.dart';

const String _hrvMetric = 'hrv_sleep_avg';

String _dateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The plan. Rebuilds when settings or the snapshot change; invalidate it
/// after a sync to re-read the store.
@riverpod
Future<BreathingPlan> breathingPlan(Ref ref) async {
  final settings = await ref.watch(breathingSettingsControllerProvider.future);
  final now = DateTime.now();
  final history = await readBreathingHistory(
    ref.watch(localStoreProvider),
    now,
  );
  // The HRV sentence says "this morning", so only today's snapshot counts. It
  // is watched, not awaited: the plan must not wait on the network.
  final view = ref.watch(todaySnapshotProvider).value;
  final card = view == null || view.describesAnotherDay(_dateOf(now))
      ? null
      : view.snapshot.metric(_hrvMetric);
  return buildBreathingPlan(
    now: now,
    history: history,
    settings: settings,
    hrv: card?.reading.valueOrNull,
    hrvUsual: card == null ? null : usualOfCard(card),
  );
}

/// Changes that also move the reminders.
@Riverpod(keepAlive: true)
class BreathingActions extends _$BreathingActions {
  @override
  void build() {}

  /// Turns all items on and schedules their reminders.
  Future<void> acceptAll() async {
    await ref.read(breathingSettingsControllerProvider.notifier).acceptAll();
    await syncReminders();
  }

  /// Switches one item and updates its reminder.
  Future<void> setEnabled(BreathingItemKind kind, {required bool on}) async {
    await ref
        .read(breathingSettingsControllerProvider.notifier)
        .setEnabled(kind, on: on);
    await syncReminders();
  }

  /// Re-applies the reminders for the current plan.
  Future<void> syncReminders() async {
    final plan = await ref.refresh(breathingPlanProvider.future);
    await ref.read(notificationServiceProvider).syncBreathingReminders(plan);
  }
}
