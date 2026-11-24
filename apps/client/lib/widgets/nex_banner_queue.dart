part of 'nex_banner.dart';

/// Consecutive results of one operation can share a count and an Undo.
class NexBannerGroup {
  const NexBannerGroup({
    required this.key,
    required this.count,
    required this.message,
    this.batch,
  });

  final Object key;
  final int count;
  final String Function(int) message;

  /// Optional identifiers to submit together when the user taps Undo.
  final ({List<String> ids, ValueChanged<List<String>> run})? batch;
}

final _queues = Expando<_BannerQueue>();
_BannerQueue? _lastQueue;

_BannerQueue _queueFor(OverlayState overlay) =>
    _lastQueue = _queues[overlay] ??= _BannerQueue(overlay);

class _BannerRequest {
  _BannerRequest({
    required this.message,
    required this.kind,
    required this.actionLabel,
    required VoidCallback? onAction,
    required this.actionKey,
    required this.duration,
    required this.haptics,
    required this.group,
  }) : actions = [?onAction],
       _ids = group?.batch?.ids.toSet(),
       repetitions = group?.count ?? 1;

  String message;
  final NexBannerKind kind;
  final String? actionLabel;
  final Key? actionKey;
  final Duration? duration;
  final bool haptics;
  final NexBannerGroup? group;
  final List<VoidCallback> actions;
  final Set<String>? _ids;
  final closed = Completer<void>();
  int repetitions;

  bool get important => actionLabel != null || kind != NexBannerKind.done;

  bool merge(_BannerRequest next) {
    if (kind != next.kind || actionLabel != next.actionLabel) return false;
    final mergeActions =
        group != null &&
        group!.key == next.group?.key &&
        (_ids == null) == (next._ids == null) &&
        actionKey == next.actionKey;
    if (!mergeActions && (actionLabel != null || message != next.message)) {
      return false;
    }
    repetitions += next.repetitions;
    if (mergeActions) {
      if (_ids case final ids?) {
        ids.addAll(next._ids!);
        repetitions = ids.length;
      } else {
        actions.addAll(next.actions);
      }
      message = group!.message(repetitions);
    }
    return true;
  }

  void act() {
    if (group?.batch case final batch?) {
      batch.run(List.unmodifiable(_ids!));
      return;
    }
    for (final action in actions) {
      action();
    }
  }
}

class _BannerQueue {
  _BannerQueue(this.overlay);

  final OverlayState overlay;
  final _waiting = <_BannerRequest>[];
  final _exiting = <_BannerSession>{};
  _BannerSession? _active;

  NexBannerHandle show(_BannerRequest request) {
    final active = _active;
    final last =
        _waiting.lastOrNull ??
        (active?.leaving == false ? active?.request : null);
    if (last != null && last.merge(request)) {
      active?.entry.markNeedsBuild();
      return NexBannerHandle._(this, last);
    }
    if (active == null) {
      _insert(request);
    } else if (active.request.important ||
        active.leaving && _waiting.isNotEmpty) {
      // Keep the order of important results. The latest confirmation only
      // needs one slot after them.
      final receipt = _waiting.indexWhere((item) => !item.important);
      if (request.important) {
        _waiting.insert(receipt < 0 ? _waiting.length : receipt, request);
      } else if (receipt < 0) {
        _waiting.add(request);
      } else {
        _waiting[receipt].closed.complete();
        _waiting[receipt] = request;
      }
      active.entry.markNeedsBuild();
    } else {
      _active = null;
      _exiting.add(active);
      active.leaving = true;
      final state = active.state;
      if (state == null) {
        _gone(active);
      } else {
        unawaited(state._dismiss());
      }
      _insert(request);
    }
    return NexBannerHandle._(this, request);
  }

  void _insert(_BannerRequest request) {
    final session = _BannerSession(request);
    session.entry = OverlayEntry(
      builder: (context) => _NexBanner(
        session: session,
        message: request.message,
        kind: request.kind,
        actionLabel: request.actionLabel,
        onAction: request.act,
        actionKey: request.actionKey,
        duration: request.duration,
        haptics: request.haptics,
        repetitions: request.repetitions,
        pendingCount: session.leaving ? 0 : _waiting.length,
        nextMessage: !session.leaving && _waiting.firstOrNull?.important == true
            ? _waiting.first.message
            : null,
        onGone: () => _gone(session),
      ),
    );
    _active = session;
    overlay.insert(session.entry);
  }

  void _gone(_BannerSession session) {
    if (session.request.closed.isCompleted) return;
    _exiting.remove(session);
    if (overlay.mounted) session.entry.remove();
    session.request.closed.complete();
    if (!identical(_active, session)) return;
    _active = null;
    if (_waiting.isNotEmpty && overlay.mounted) {
      _insert(_waiting.removeAt(0));
    }
  }

  void hide(_BannerRequest request) {
    if (_waiting.remove(request)) {
      request.closed.complete();
      _active?.entry.markNeedsBuild();
    } else if (_active case final active?
        when identical(active.request, request)) {
      _gone(active);
    }
  }

  void clear() {
    for (final request in _waiting) {
      request.closed.complete();
    }
    _waiting.clear();
    if (_active case final active?) _gone(active);
    for (final session in _exiting.toList()) {
      _gone(session);
    }
  }
}

class _BannerSession {
  _BannerSession(this.request);

  final _BannerRequest request;
  late final OverlayEntry entry;
  bool leaving = false;
  _NexBannerState? state;
}

/// Tracks a banner from submission through dismissal, including its time in
/// the queue. Hiding it leaves unrelated requests in place.
class NexBannerHandle {
  NexBannerHandle._(this._queue, this._request);

  final _BannerQueue _queue;
  final _BannerRequest _request;

  Future<void> get closed => _request.closed.future;
  bool get isShowing => identical(_queue._active?.request, _request);

  void hide() => _queue.hide(_request);
}

void nexHideBanner() {
  _lastQueue?.clear();
  _lastQueue = null;
}
