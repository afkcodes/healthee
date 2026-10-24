/// The operational view: battery, when we last synced, and whether it finished.
///
/// Brief §5.8 calls the freshness strip "the owner-facing operational view" and
/// says why it matters: *"production has served stale data behind a
/// healthy-looking screen before."* This is the strap-only form of it.
///
/// The load-bearing line is the last one. `last complete sync` and `last
/// attempt` are separate stored facts (`SyncKeys`), and this card shows the gap
/// between them out loud when there is one. A partial pull that reported nothing
/// would leave the owner reading yesterday's steps as today's — which is the
/// same failure as a stale server number, arriving from the other direction.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

/// Strap and sync health, always present, never alarming.
class DeviceHealthCard extends StatelessWidget {
  /// [now] is injected so tests do not depend on the wall clock.
  const DeviceHealthCard({required this.day, this.now, super.key});

  /// The day being shown.
  final DeviceDay day;

  /// The current instant.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final at = now ?? DateTime.now();
    return StateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device and sync', style: text.labelSmall),
          const SizedBox(height: Insets.md),
          _Line(label: 'Strap battery', value: _battery(day)),
          _Line(label: 'Last full sync', value: _lastComplete(day, at)),
          if (day.sync.lastAttemptIncomplete)
            // Said plainly, and only when true. An attempt that half-worked and
            // stays quiet is indistinguishable from one that worked.
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text(
                _incomplete(day, at),
                style: text.bodySmall?.copyWith(color: colors.unf),
              ),
            ),
        ],
      ),
    );
  }

  static String _battery(DeviceDay day) =>
      day.batteryPercent == null ? 'not read yet' : '${day.batteryPercent}%';

  /// Never "just now" by default: a phone that has never synced says so.
  static String _lastComplete(DeviceDay day, DateTime now) {
    final at = day.sync.lastCompleteSync;
    return at == null
        ? 'never — nothing has been pulled from the strap yet'
        : '${ageLabel(at, now: now)} (${clockLabel(at)})';
  }

  static String _incomplete(DeviceDay day, DateTime now) {
    final at = day.sync.lastAttempt;
    final when = at == null ? '' : ' ${ageLabel(at, now: now)}';
    return 'The last attempt$when did not finish, so anything above may be '
        'older than it looks.';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: colors.ink2),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            flex: 2,
            child: Text(value, style: text.bodySmall, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
