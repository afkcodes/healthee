/// Holds ONE authenticated session for as long as the app is in front, and
/// gives it back the moment it is not.
///
/// ## Why hold it at all
///
/// Connect → sync → disconnect is generic BLE practice, and it is not how this
/// strap is used: the Zepp app shows the band as connected while it is not
/// syncing, so the device both supports and expects a long-lived link. Against
/// that, an indicator reading "Not connected" one minute after a healthy sync is
/// answering a question nobody asked — it reports a socket where the owner
/// wanted a fact.
///
/// ## Why releasing it is not optional
///
/// A link held for hours drains the strap, and most BLE peripherals accept ONE
/// connection at a time — so an app that keeps the link while backgrounded locks
/// the owner out of their own band in the Zepp app, all day, for a screen nobody
/// is looking at. [toBackground] closes the session properly rather than
/// dropping the object and hoping the platform notices.
///
/// ## What it may claim
///
/// [held] re-asks `StrapSession.isOpen` every time; it never remembers that a
/// connect once succeeded. `Connected` is built from that session's own
/// `authenticatedAt`, which is written on the line that emits
/// `StrapPhase.authenticated` — so the state and the evidence are the same fact,
/// not two records of it that can drift apart.
library;

import 'dart:async';

import 'package:healthee/ble/strap_client.dart';
import 'package:healthee/ble/strap_exception.dart';
import 'package:healthee/ble/strap_failure.dart';
import 'package:healthee/ble/strap_progress.dart';
import 'package:healthee/ble/strap_scanner.dart';
import 'package:healthee/ble/strap_session.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/pairing/pairing_exception.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/device_lease.dart';
import 'package:healthee/data/sync/preflight_scan.dart';
import 'package:healthee/data/sync/reconnect_policy.dart';
import 'package:healthee/data/sync/sync_failure.dart';

/// Runs [action] after [delay]. `Timer.new` in the app; a fake in tests, which
/// is what lets the backoff SCHEDULE be asserted rather than waited out.
typedef DelayedCall = Timer Function(Duration delay, void Function() action);

/// Keeps the strap connected while the app is in the foreground.
class ForegroundLink {
  /// [lastCompleteSync] dates the resting states; [onState] publishes every
  /// state this link passes through.
  ForegroundLink({
    required this.client,
    required StrapScanner scanner,
    required this.lastCompleteSync,
    required this.onState,
    this.policy = const ReconnectPolicy(),
    this.schedule = Timer.new,
    this.lease,
  }) : _preflight = PreflightScan(pairing: client.pairing, scanner: scanner);

  /// The protocol layer this link opens sessions through.
  final StrapClient client;

  /// Dates the resting states. Read at the moment one is published, never
  /// cached — a freshness line built from a value read minutes ago is exactly
  /// the stale-as-current failure the product exists against.
  final Future<DateTime?> Function() lastCompleteSync;

  /// Publishes every state this link passes through.
  final void Function(StrapConnection state) onState;

  /// When to try again, and when trying again is a battery bug.
  final ReconnectPolicy policy;

  /// How the backoff waits. `Timer.new` in the app, a fake in tests.
  final DelayedCall schedule;

  final PreflightScan _preflight;
  final DeviceLease? lease;

  StrapSession? _session;
  Timer? _retry;
  bool _foreground = false;
  bool _connecting = false;
  int _attempt = 0;

  /// The open session, or null when there is none.
  ///
  /// Re-asks the session whether it is open rather than trusting a flag set when
  /// it was created — the difference between "a session is open" and "a session
  /// was opened", which is the whole distinction this feature turns on.
  StrapSession? get held {
    final session = _session;
    return (session != null && session.isOpen) ? session : null;
  }

  /// Whether the app currently believes it is in front. Read by tests.
  bool get isForeground => _foreground;

  /// The app came to the front: open a session and keep it.
  Future<void> toForeground() async {
    if (_foreground) {
      return;
    }
    _foreground = true;
    _attempt = 0;
    await _connect();
  }

  /// The app left: close the session, cleanly, and stop trying.
  ///
  /// Emits [Disconnected] with the freshness fact, because that is the useful
  /// and honest thing to say about a link deliberately let go.
  Future<void> toBackground() async {
    _foreground = false;
    _retry?.cancel();
    _retry = null;
    await _release('the app is no longer in front');
    onState(Disconnected(lastCompleteSync: await lastCompleteSync()));
  }

  /// The held session just failed something; stop claiming it.
  ///
  /// The caller has already published [ConnectionFailed] with [failure]'s own
  /// words, so this does not re-announce it. It closes the dead session and, for
  /// a failure a wait can clear, lets the backoff pick it up — starting at the
  /// first delay so the message stays on screen long enough to read.
  Future<void> invalidate(SyncFailure failure) async {
    await _release('the session failed: ${failure.code}');
    if (!_foreground || policy.isPermanent(failure)) {
      return;
    }
    _attempt = 0;
    _scheduleRetry();
  }

  /// Releases everything. After this the link holds nothing and retries nothing.
  Future<void> dispose() async {
    lease?.stopRenewing();
    _foreground = false;
    _retry?.cancel();
    _retry = null;
    await _release('the link is being disposed');
  }

  /// One attempt, plus whatever the failure earns.
  Future<void> _connect() async {
    if (_connecting || held != null || !_foreground) {
      return;
    }
    _connecting = true;
    try {
      if (lease != null && !await lease!.acquire()) {
        AppLog.info('sync', 'background sync owns the strap; retrying shortly');
        // Say when the strap last synced. Silence left the controller's initial
        // `Disconnected()`, which has no date, and the screen read "Nothing has
        // been read from your strap yet" seconds after a sync.
        onState(Disconnected(lastCompleteSync: await lastCompleteSync()));
        _scheduleRetry();
        return;
      }
      final failure = await _openOnce();
      if (failure == null || !_foreground) {
        return;
      }
      onState(
        ConnectionFailed(failure, lastCompleteSync: await lastCompleteSync()),
      );
      if (policy.isPermanent(failure)) {
        AppLog.info(
          'sync',
          'not retrying the strap: ${failure.code} will not clear on a timer',
        );
        return;
      }
      _scheduleRetry();
    } finally {
      _connecting = false;
      if (held == null) await lease?.release();
    }
  }

  /// Scan, connect, handshake. Returns null once a session is held.
  Future<SyncFailure?> _openOnce() async {
    onState(const Scanning());
    final blocked = await _preflight.run();
    if (blocked != null) {
      return blocked;
    }
    if (!_foreground) {
      return null;
    }
    try {
      return _adopt(await client.connect(onPhase: _reportPhase));
    } on StrapException catch (error, stackTrace) {
      AppLog.failure('sync', 'holding the strap connection', error, stackTrace);
      return SyncFailure.strap(error.failure);
    } on PairingException catch (error, stackTrace) {
      AppLog.failure('sync', 'reading the paired strap', error, stackTrace);
      return SyncFailure.pairing(error.failure);
    }
  }

  /// Takes ownership of a freshly opened session — or closes it.
  ///
  /// Two things can be true by the time a handshake returns. The app may have
  /// been backgrounded while it ran, in which case holding the session is the
  /// exact behaviour [toBackground] exists to prevent. And the session may have
  /// no authentication instant, which `connect` makes structurally impossible
  /// (it throws unless the strap accepted the proof) — so rather than reach for
  /// a `!`, the impossible case closes the link and reports a failure. Claiming
  /// `Connected` from a session that cannot say when it authenticated is the
  /// precise lie this file is arranged to prevent.
  Future<SyncFailure?> _adopt(StrapSession session) async {
    final since = session.authenticatedAt;
    if (!_foreground || since == null) {
      await session.close();
      return since == null
          ? SyncFailure.strap(
              const HandshakeRefused('the session reported no auth instant'),
            )
          : null;
    }
    _session = session;
    _attempt = 0;
    AppLog.info('sync', 'holding an authenticated session while in front');
    onState(Connected(since: since, batteryPercent: session.batteryPercent));
    return null;
  }

  void _reportPhase(StrapPhase phase) {
    // Deliberately silent on `authenticated`: this link publishes `Connected`
    // from the returned session in [_adopt], so the state is built from an
    // object that can be asked whether it is still open — not from a callback
    // that fired once.
    switch (phase) {
      case StrapPhase.connecting:
        onState(const Connecting());
      case StrapPhase.authenticating:
        onState(const Authenticating());
      case StrapPhase.authenticated:
        break;
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final delay = policy.delayFor(_attempt);
    AppLog.info(
      'sync',
      'retrying the strap in ${delay.inSeconds}s (attempt ${_attempt + 2})',
    );
    _retry = schedule(delay, () {
      _attempt++;
      unawaited(_connect());
    });
  }

  Future<void> _release(String why) async {
    final session = _session;
    _session = null;
    if (session == null) {
      if (!_connecting) await lease?.release();
      return;
    }
    AppLog.info('sync', 'releasing the strap — $why');
    await session.close();
    await lease?.release();
  }
}
