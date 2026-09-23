import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:uuid/uuid.dart';

/// SQLite arbitration across UI/background isolates.
///
/// ## A killed owner used to hold the strap for thirty minutes
///
/// The row is `<owner-uuid>:<expires-at>` and [acquire] only ever asked whether
/// `expires-at` had passed. Both the first grab and every heartbeat set that to
/// **now + [expiry]**, so a process that died left a lease valid for the full
/// thirty minutes after its last breath — while the heartbeat that would have
/// proved it dead runs every sixty seconds.
///
/// Observed exactly that way: the debug app was killed to install a release
/// build, and the new process — the only one on the device, with no sync
/// service running — was told `Another sync owns the strap. Wait for the
/// current connection to finish.` There was no connection to wait for, and no
/// way for the app to tell the difference.
///
/// ## Why this is not fixed by shortening the expiry
///
/// The obvious repair is an expiry a few heartbeats long. It trades one failure
/// for a worse one: an owner whose isolate is busy enough to miss its timer —
/// a long sync parsing a day of samples — would have its lease stolen mid-run,
/// and two processes on one BLE session is a real corruption where a stale card
/// is only an annoying one.
///
/// ## What it does instead: ask whether the owner still exists
///
/// The row records the owner's **process id**, and a lease whose process is
/// gone is dead by definition — no timeout needed. Android is Linux, so
/// `/proc/<pid>` answers it directly.
///
///   * **A different, dead process** — reclaimed at once. This is the case
///     above, and the only one that changed.
///   * **A live process, including this one** — respected until [expiry], so a
///     blocked isolate keeps its lease exactly as before.
///   * **A recycled pid**, or a platform with no `/proc` — reads as alive and
///     falls back to the timeout. It fails closed, toward waiting.
///   * **A row with no pid at all** — written by a build from before this
///     field existed, and therefore by a process that cannot still be running:
///     two builds of one package cannot run at the same time, and installing
///     the new one killed everything belonging to the old. Reclaimed.
///
/// That last case was first written the other way, as "absent evidence of death
/// is not evidence of death". It is the more careful sentence and the wrong
/// rule: it left the very lease that prompted this fix — orphaned by the killed
/// debug process — sitting there after the repaired build was installed, still
/// telling the owner to wait for a connection that had died with it.
///
/// The reclaim is a compare-and-swap against the exact row that was read, so
/// two processes racing to take the same dead lease cannot both win.
///
/// ## A replaced UI isolate, in a process that is still alive
///
/// Back destroys the Activity and its FlutterEngine, but Android keeps the
/// process. Reopening starts a new UI isolate under the SAME pid. The old
/// isolate's release is async and never ran, and "same pid, so alive" made
/// the new isolate wait out the full expiry.
///
/// So the UI isolate, the one that runs `main()` and calls [markUiIsolate],
/// stamps its rows with a token of its own. A process hosts one UI isolate at
/// a time. A same-pid row stamped by a DIFFERENT UI token therefore belongs to
/// an isolate that has been replaced, and the new UI isolate reclaims it. Rows
/// with no stamp (WorkManager's background isolate) and rows stamped by this
/// very isolate are judged exactly as before.
class DeviceLease {
  DeviceLease(
    this.store, {
    this.resource = 'strap_lease',
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final LocalStore store;
  final String resource;
  final DateTime Function() now;
  final String _owner = const Uuid().v4();

  /// This process. Recorded with the lease so a later owner can ask whether the
  /// holder still exists rather than waiting out [expiry].
  static final int _pid = pid;

  /// This isolate's stamp when it is the UI isolate; null in any other.
  static String? _uiIsolate;

  /// Declares this isolate the UI one. Called once, from `main()`.
  static void markUiIsolate() => _uiIsolate ??= const Uuid().v4();
  Timer? _renewal;
  static const expiry = Duration(minutes: 30);
  static const heartbeat = Duration(minutes: 1);
  bool _held = false;
  bool _closed = false;

  Future<bool> acquire() async {
    if (_closed) return false;
    if (_held) return true;
    var updated = await store.customUpdate(
      'INSERT INTO sync_meta(name, value) VALUES (?, ?) '
      'ON CONFLICT(name) DO UPDATE SET value = excluded.value '
      'WHERE CAST(substr(sync_meta.value, 38) AS INTEGER) < ?',
      variables: [
        Variable(resource),
        Variable(_claim()),
        Variable(now().millisecondsSinceEpoch),
      ],
      updates: {store.syncMeta},
    );
    // Unexpired, so somebody holds it — but "holds it" and "is still running"
    // are different claims. See the class docstring.
    updated = updated == 1 ? updated : await _reclaimIfOwnerIsGone();
    _held = updated == 1;
    if (_closed) {
      await release();
      return false;
    }
    if (_held) _renewal = Timer.periodic(heartbeat, (_) => unawaited(_renew()));
    return _held;
  }

  /// `<owner>:<expires-at>:<pid>` — the row this process would write.
  ///
  /// The pid is appended rather than inserted, so the `substr(value, 38)` the
  /// expiry check has always used still reads the timestamp: SQLite's `CAST`
  /// stops at the first non-digit, and every existing row without a pid parses
  /// exactly as it did before.
  String _claim() =>
      '$_owner:${now().add(expiry).millisecondsSinceEpoch}:$_pid'
      '${_uiIsolate == null ? '' : ':$_uiIsolate'}';

  /// Takes the lease when the recorded process no longer exists.
  ///
  /// Returns 1 when it was taken, 0 otherwise. The update is conditional on the
  /// row still being byte-for-byte what was read, so a second process reclaiming
  /// the same dead lease at the same moment loses the race rather than sharing
  /// the strap.
  Future<int> _reclaimIfOwnerIsGone() async {
    final rows = await store
        .customSelect(
          'SELECT value FROM sync_meta WHERE name = ?',
          variables: [Variable(resource)],
        )
        .get();
    final held = rows.firstOrNull?.read<String>('value');
    if (held == null) {
      return 0;
    }
    final parts = held.split(':');
    // A row with no pid predates this field, so its writer ran a build that is
    // no longer installed and a process that is no longer alive — see the class
    // docstring. Anything else is judged on whether its process still exists.
    final owner = parts.length < 3 ? null : int.tryParse(parts[2]);
    final legacy = owner == null;
    final holderUi = parts.length < 4 ? null : parts[3];
    // See the class docstring. Only a UI isolate may conclude this.
    final replacedUi =
        owner == _pid &&
        _uiIsolate != null &&
        holderUi != null &&
        holderUi != _uiIsolate;
    if (!legacy && !replacedUi && (owner == _pid || _isRunning(owner))) {
      return 0;
    }
    AppLog.info(
      'sync',
      legacy
          ? 'reclaimed $resource from a pre-upgrade owner'
          : replacedUi
          ? 'reclaimed $resource from a UI isolate that was replaced'
          : 'reclaimed $resource from dead process $owner',
    );
    return store.customUpdate(
      'UPDATE sync_meta SET value = ? WHERE name = ? AND value = ?',
      variables: [Variable(_claim()), Variable(resource), Variable(held)],
      updates: {store.syncMeta},
    );
  }

  /// Whether [owner] is still a live process on this device.
  ///
  /// **Anything but a confident "no" is a yes.** A platform without `/proc`, or
  /// a directory this app may not stat, must not be read as death — the cost of
  /// a wrong "dead" is two owners on one BLE session.
  static bool _isRunning(int owner) {
    if (!Platform.isAndroid && !Platform.isLinux) {
      return true;
    }
    try {
      return Directory('/proc/$owner').existsSync();
    } on Exception {
      return true;
    }
  }

  /// Stop timers synchronously during teardown, including an in-flight acquire.
  /// The connection owner still releases the row after closing its session.
  void stopRenewing() {
    _closed = true;
    _renewal?.cancel();
    _renewal = null;
  }

  Future<void> _renew() async {
    try {
      await store.customUpdate(
        'UPDATE sync_meta SET value = ? WHERE name = ? AND substr(value, 1, 36) = ?',
        variables: [Variable(_claim()), Variable(resource), Variable(_owner)],
      );
    } on Exception catch (error, stack) {
      AppLog.failure(
        'sync',
        'renewing device connection ownership',
        error,
        stack,
      );
    }
  }

  Future<void> release() async {
    _renewal?.cancel();
    _renewal = null;
    if (!_held) return;
    await store.customUpdate(
      'DELETE FROM sync_meta WHERE name = ? AND substr(value, 1, 36) = ?',
      variables: [Variable(resource), Variable(_owner)],
      updates: {store.syncMeta},
    );
    _held = false;
  }
}
