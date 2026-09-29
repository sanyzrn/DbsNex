/// One unlock for every private tool, and how long it lasts.
///
/// Each vault screen used to own its unlock and threw it away the moment the
/// screen closed or the app lost focus. So backing out of Passwords to open
/// Bank cards asked for the fingerprint again, and copying a password to
/// paste it into a browser — the whole reason the vault exists — locked it
/// behind you. The screen promised two minutes; nothing ever waited for them.
///
/// The unlock now lives here, once for the process. It stays open while
/// anything private is being used and for [grace] after the last touch,
/// including time spent in another app. Content is still hidden the moment
/// the app is backgrounded (see VaultScreen); only the need to authenticate
/// again is what the grace period spares.
///
/// Nothing is persisted. A killed process always starts locked.
class VaultSession {
  VaultSession._();

  static final instance = VaultSession._();

  /// How long an unlock survives without activity.
  static const grace = Duration(minutes: 2);

  /// Replaceable so tests can move time without waiting for it.
  DateTime Function() clock = DateTime.now;

  DateTime? _until;

  bool get isOpen {
    final until = _until;
    return until != null && clock().isBefore(until);
  }

  /// Time left before the unlock lapses, or zero when it already has.
  Duration get remaining {
    final until = _until;
    if (until == null) return Duration.zero;
    final left = until.difference(clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Called only after a successful device authentication.
  void open() => _until = clock().add(grace);

  /// Activity inside a private tool pushes the deadline out again. An unlock
  /// that has already lapsed is never revived by a touch.
  void touch() {
    if (isOpen) _until = clock().add(grace);
  }

  void close() => _until = null;
}
