import 'dart:convert';
import 'dart:math';

import 'nex_tips.dart';

/// What the home screen remembers about its tips: which were shown and when,
/// which is up now, and how the last few were received.
class NexTipState {
  const NexTipState({
    this.firstSeenAt,
    this.shown = const {},
    this.current,
    this.currentSince,
    this.closedAt,
    this.notesAtClose = 0,
    this.ignored = 0,
  });

  /// When the home screen first looked for a tip on this install.
  final DateTime? firstSeenAt;

  /// Every tip that has been up, with when it last was.
  final Map<String, DateTime> shown;

  /// The tip on screen now, and since when.
  final String? current;
  final DateTime? currentSince;

  /// When the last tip was closed, and how many notes there were then.
  final DateTime? closedAt;
  final int notesAtClose;

  /// Tips closed in a row without their button being used. Each one makes
  /// the next wait longer: the schedule listens to someone who keeps
  /// closing them.
  final int ignored;

  NexTipState copyWith({
    DateTime? firstSeenAt,
    Map<String, DateTime>? shown,
    String? current,
    DateTime? currentSince,
    bool clearCurrent = false,
    DateTime? closedAt,
    int? notesAtClose,
    int? ignored,
  }) => NexTipState(
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    shown: shown ?? this.shown,
    current: clearCurrent ? null : (current ?? this.current),
    currentSince: clearCurrent ? null : (currentSince ?? this.currentSince),
    closedAt: closedAt ?? this.closedAt,
    notesAtClose: notesAtClose ?? this.notesAtClose,
    ignored: ignored ?? this.ignored,
  );

  String toJson() => jsonEncode({
    if (firstSeenAt case final at?) 'first': at.toUtc().toIso8601String(),
    'shown': {
      for (final MapEntry(:key, :value) in shown.entries)
        key: value.toUtc().toIso8601String(),
    },
    'current': ?current,
    if (currentSince case final at?) 'since': at.toUtc().toIso8601String(),
    if (closedAt case final at?) 'closed': at.toUtc().toIso8601String(),
    'notes': notesAtClose,
    'ignored': ignored,
  });

  /// Anything unreadable starts the tips over rather than failing the home
  /// screen.
  static NexTipState parse(String? json) {
    if (json == null) return const NexTipState();
    try {
      final raw = jsonDecode(json);
      if (raw is! Map) return const NexTipState();
      DateTime? at(Object? value) =>
          value is String ? DateTime.tryParse(value)?.toLocal() : null;
      final shown = <String, DateTime>{};
      if (raw['shown'] case final Map<Object?, Object?> map) {
        for (final MapEntry(:key, :value) in map.entries) {
          if (key is String) {
            if (at(value) case final last?) shown[key] = last;
          }
        }
      }
      return NexTipState(
        firstSeenAt: at(raw['first']),
        shown: shown,
        current: raw['current'] is String ? raw['current'] as String : null,
        currentSince: at(raw['since']),
        closedAt: at(raw['closed']),
        notesAtClose: raw['notes'] is int ? raw['notes'] as int : 0,
        ignored: raw['ignored'] is int ? raw['ignored'] as int : 0,
      );
    } catch (_) {
      return const NexTipState();
    }
  }
}

/// When a tip appears, and which (2.8.4). Pure: the same state, notes and
/// moment give the same answer, so every rule below is tested as written.
///
/// - **A quiet start.** Nothing in the first day, or before there are three
///   notes: first the app, then the tips.
/// - **One at a time, and not for long.** A tip stays until it is closed or
///   its button used, or for a day and a half, whichever comes first.
/// - **A rest between tips** of [rest]; each tip closed in a row without its
///   button being used adds a day, up to five — someone who keeps closing
///   them sees them less, never more.
/// - **Writing brings one sooner.** [notesForEarly] new notes since the last
///   tip end the rest early, but never within [earliest] of it.
/// - **Not at night.** No new tip between 22:00 and 07:00; one already up
///   stays.
/// - **Which one** is picked at random among those that fit, the same one
///   all day, with new features ([NexTip.fresh]) three times as likely.
/// - **Each once.** A tip is shown once; [again] after it was last up, it
///   may come back.
abstract final class NexTipSchedule {
  static const rest = Duration(hours: 20);
  static const earliest = Duration(hours: 3);
  static const notesForEarly = 5;
  static const stayUp = Duration(hours: 36);
  static const again = Duration(days: 120);
  static const quietStart = Duration(hours: 24);
  static const notesToStart = 3;

  /// The tip to show now, if any, and the state that goes with it.
  static (NexTip?, NexTipState) pick({
    required List<NexTip> tips,
    required NexTipState state,
    required NexTipContext context,
    required DateTime now,
  }) {
    var next = state.firstSeenAt == null
        ? state.copyWith(firstSeenAt: now)
        : state;
    final first = next.firstSeenAt!;
    final count = context.notes.length;

    // One already up stays, while it still fits and is not stale.
    if (next.current case final id?) {
      final tip = tips.where((t) => t.id == id).firstOrNull;
      final since = next.currentSince ?? now;
      if (tip != null && tip.fits(context) && now.difference(since) < stayUp) {
        return (tip, next);
      }
      // Gone stale or no longer true: it leaves quietly, as if closed.
      next = next.copyWith(
        clearCurrent: true,
        closedAt: now,
        notesAtClose: count,
      );
    }

    if (now.difference(first) < quietStart || count < notesToStart) {
      return (null, next);
    }
    if (now.hour >= 22 || now.hour < 7) return (null, next);
    if (next.closedAt case final closed?) {
      final waited = now.difference(closed);
      final wait = rest + Duration(days: min(next.ignored, 4));
      final early =
          count - next.notesAtClose >= notesForEarly && waited >= earliest;
      if (waited < wait && !early) return (null, next);
    }

    bool rested(NexTip tip) {
      final last = next.shown[tip.id];
      return last == null || now.difference(last) >= again;
    }

    final candidates = [
      for (final tip in tips)
        if (tip.fits(context) && rested(tip)) tip,
    ];
    if (candidates.isEmpty) return (null, next);

    // The same pick all day: seeded by the day and how many have been shown.
    final day = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(2024)).inDays;
    final random = Random(day * 31 + next.shown.length);
    final weights = [for (final tip in candidates) tip.fresh ? 3 : 1];
    var roll = random.nextInt(weights.fold(0, (a, b) => a + b));
    var chosen = candidates.first;
    for (var i = 0; i < candidates.length; i++) {
      roll -= weights[i];
      if (roll < 0) {
        chosen = candidates[i];
        break;
      }
    }
    return (
      chosen,
      next.copyWith(
        current: chosen.id,
        currentSince: now,
        shown: {...next.shown, chosen.id: now},
      ),
    );
  }

  /// The tip was closed — with its button ([acted]) or without.
  static NexTipState closed(
    NexTipState state, {
    required DateTime now,
    required int notes,
    bool acted = false,
  }) => state.copyWith(
    clearCurrent: true,
    closedAt: now,
    notesAtClose: notes,
    ignored: acted ? 0 : state.ignored + 1,
  );
}
