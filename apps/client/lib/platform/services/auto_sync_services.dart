part of '../nex_services.dart';

/// Sync that runs by itself once a server is paired: a cycle shortly after
/// writes, a pull on a standing rhythm, and a quiet cooldown after a failure.
/// Nothing here runs, and no timer exists, while no endpoint is configured.
extension NexAutoSyncServices on NexServices {
  /// How long after a write the auto-sync cycle runs. Long enough that a
  /// burst of captures is one cycle, short enough that "it syncs by itself"
  /// is something a person can watch happen.
  static const autoSyncDelay = Duration(seconds: 30);

  /// The standing rhythm: pull even when this device has nothing to send.
  /// Peers' changes otherwise waited for the next manual pull-to-refresh —
  /// the only trigger sync had before this existed.
  static const autoSyncInterval = Duration(minutes: 15);

  /// How long a failed auto-sync silences the scheduler. An unattended cycle
  /// against a dead server every thirty seconds is a battery drain wearing
  /// a feature's clothes; one attempt per cooldown window is the honest
  /// rate for something nobody asked to see.
  static const autoSyncRetryDelay = Duration(minutes: 5);

  /// Kicks a sync cycle soon — after the writes that just landed, once, not
  /// one per write. Nothing happens without a configured endpoint, and the
  /// cycle itself runs unattended: its failure is a diagnostics line, never
  /// a banner nobody is standing in front of.
  void _scheduleAutoSync() {
    if (_closed || _preferences.syncBaseUrl == null) return;
    _armAutoSyncRhythm();
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(autoSyncDelay, () => _autoSync(pullToo: false));
  }

  /// One unattended cycle. With [pullToo] it pulls regardless of the outbox
  /// (the standing rhythm); without, it only spends a round trip when there
  /// is something to send — the outbox check is what keeps a cycle that ends
  /// in `refreshTimeline` from scheduling another, forever.
  Future<void> _autoSync({required bool pullToo}) async {
    if (_closed || _preferences.syncBaseUrl == null) return;
    if (DateTime.now().isBefore(_autoSyncQuietUntil)) return;
    if (_autoSyncInFlight) return;
    try {
      if (!pullToo && !await worker.pendingSyncWork()) return;
    } catch (_) {
      return; // the worker is gone or busy; the periodic tick retries
    }
    _autoSyncInFlight = true;
    try {
      await syncNow();
      _autoSyncQuietUntil = DateTime.fromMillisecondsSinceEpoch(0);
    } catch (error) {
      _autoSyncQuietUntil = DateTime.now().add(autoSyncRetryDelay);
      unawaited(
        NexServices.noteDiagnostic('auto-sync failed: ${error.runtimeType}'),
      );
    } finally {
      _autoSyncInFlight = false;
    }
  }

  /// The standing sync rhythm: one pull every [autoSyncInterval] while the
  /// app runs, quiet about it — and only once an endpoint is configured. A
  /// library that is not paired (every library, until pairing has a screen)
  /// carries no timer at all, rather than one that wakes every quarter hour
  /// to find nothing to do. Armed again by the first write after pairing.
  void _armAutoSyncRhythm() {
    if (_closed ||
        _autoSyncPeriodicTimer != null ||
        _preferences.syncBaseUrl == null) {
      return;
    }
    _autoSyncPeriodicTimer = Timer.periodic(
      autoSyncInterval,
      (_) => _autoSync(pullToo: true),
    );
  }
}
