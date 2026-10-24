import 'dart:convert';

import 'package:healthee/data/basics/breathing/breathing_plan.dart';

/// One daily breathing reminder, as scheduled and as saved to restore later.
///
/// On demand has no reminder, so it never becomes one of these.
class BreathingReminder {
  const BreathingReminder({
    required this.id,
    required this.minute,
    required this.label,
    required this.minutes,
  });

  /// Every enabled, scheduled item of [plan].
  factory BreathingReminder.fromItem(BreathingItem item) => BreathingReminder(
    id: item.kind.reminderId!,
    minute: item.minuteOfDay!,
    label: item.kind.label,
    minutes: item.minutes,
  );

  static List<BreathingReminder> fromPlan(BreathingPlan plan) => [
    for (final item in plan.items)
      if (item.enabled && item.kind.isScheduled && item.minuteOfDay != null)
        BreathingReminder.fromItem(item),
  ];

  static List<BreathingReminder> decode(String? raw) {
    if (raw == null) return const [];
    final data = jsonDecode(raw) as List<Object?>;
    return [
      for (final entry in data.cast<Map<String, Object?>>())
        BreathingReminder(
          id: entry['id']! as int,
          minute: entry['minute']! as int,
          label: entry['label']! as String,
          minutes: entry['minutes']! as int,
        ),
    ];
  }

  /// The ids the three scheduled items use.
  static final List<int> ids = [
    for (final kind in BreathingItemKind.values)
      if (kind.reminderId != null) kind.reminderId!,
  ];

  static String encode(List<BreathingReminder> reminders) => jsonEncode([
    for (final r in reminders)
      {'id': r.id, 'minute': r.minute, 'label': r.label, 'minutes': r.minutes},
  ]);

  final int id;
  final int minute;
  final String label;
  final int minutes;

  String get body => '$label breathing, $minutes min.';
}
