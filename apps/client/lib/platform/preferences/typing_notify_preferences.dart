part of '../nex_preferences.dart';

/// Notification for text typed into a settings field, held until the typing
/// pauses.
///
/// The three fields that save as they are typed — the brief's instruction,
/// the assistant's instruction and the assistant's about-you name —
/// persist every keystroke the moment it happens; the disk write is what
/// "saved as you type" means, and it stays immediate. It was the
/// *notification* that paid for the keystroke: the timeline rebuilds
/// wholesale on every preferences notify (the rows cache absorbs only the
/// note cards), so a person typing a sentence into a covered settings
/// screen was buying one whole covered-screen rebuild per character. The
/// notify waits for a pause instead — 400 ms of quiet, or the moment any
/// other preference changes, which flushes it so a toggle never shares a
/// pause with the text. Listeners read these values through getters when
/// they rebuild, so one late notify shows them everything that was typed.
mixin _TypingNotifyPreferences on ChangeNotifier {
  Timer? _typingNotify;

  /// Notifies now, carrying anything a paused typing notify was holding.
  void _notifyNow() {
    _typingNotify?.cancel();
    _typingNotify = null;
    notifyListeners();
  }

  /// Notifies when typing pauses; replaced by [_notifyNow] if anything
  /// else changes first.
  ///
  /// Nobody listening at the moment of the write means nobody to tell
  /// later, either: a subscriber that arrives after the fact reads the
  /// getters, which already hold everything typed. This keeps a
  /// listener-less write (tests type into preferences before any app is
  /// pumped) from leaving an armed timer behind.
  void _notifyTypingSettled() {
    if (!hasListeners) return;
    _typingNotify?.cancel();
    _typingNotify = Timer(const Duration(milliseconds: 400), () {
      _typingNotify = null;
      notifyListeners();
    });
  }

  /// The value is already persisted; a deferred notify exists only for
  /// whoever is listening. When the last listener goes, so does the wait —
  /// anything that subscribes later reads the getters, which already hold
  /// everything typed.
  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _typingNotify?.cancel();
      _typingNotify = null;
    }
  }

  @override
  void dispose() {
    _typingNotify?.cancel();
    _typingNotify = null;
    super.dispose();
  }
}
