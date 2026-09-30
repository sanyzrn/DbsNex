part of '../nex_preferences.dart';

/// The sponsor card, update checks and the app's own measurements.
mixin _ServicePreferences on _PreferencesStore {
  /// Whether Nex measures its own speed on this phone (W3.4, [NexMetrics]).
  /// Off unless the person switches it on.
  bool get metricsEnabled => _prefs.getBool('metrics.enabled') ?? false;

  Future<void> setMetricsEnabled(bool value) =>
      _setBool('metrics.enabled', value);

  /// The sponsor card's raw JSON as last fetched, or null for none.
  ///
  /// Stored as the file rather than as parsed fields: the parser is the one
  /// place that decides what a valid card is, and keeping the source means a
  /// build that learns a new field can read a file fetched by the last one.
  String? get sponsorPayload => _prefs.getString('sponsor.payload');

  DateTime? get sponsorFetchedAt {
    final value = _prefs.getInt('sponsor.fetched_at');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// Where the sponsor card's picture was written, or null for a card with
  /// none. A path rather than the bytes: preferences are read on every build
  /// and half a megabyte does not belong in them.
  String? get sponsorImagePath => _prefs.getString('sponsor.image_path');

  /// When each sponsor card was last put away, by card id.
  ///
  /// A date rather than a bare list, because a dismissal is "not now", not
  /// "never". Hiding a card used to hide it for good, which is the wrong
  /// reading of a close button on a banner — nobody means "never show this
  /// again as long as I own this phone" by it, and for the one card that
  /// keeps the app free it is an expensive thing to get wrong. How long the
  /// dismissal holds is [NexSponsorService.dismissalCoolOff]'s to say; this
  /// only remembers when it happened.
  ///
  /// A malformed or half-written value reads as no dismissals at all. The
  /// cost of getting that wrong is one card shown once too often, which is
  /// the right way round for a failure nobody can see.
  Map<String, DateTime> get sponsorDismissals {
    final raw = _prefs.getString('sponsor.dismissed_at');
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is int)
            '${entry.key}': DateTime.fromMillisecondsSinceEpoch(
              entry.value as int,
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  /// All three are deliberately silent — no [notifyListeners].
  ///
  /// This is a cache, not a setting. Every listener on this object rebuilds
  /// the whole app, and the one screen that shows a sponsor card already
  /// calls `setState` itself after a fetch or a dismissal, so a notification
  /// here buys nothing and costs a full rebuild triggered by a background
  /// network reply.
  ///
  /// It also cost more than that, which is why this note exists. The reply
  /// arrives while the app lock may still be waiting on a fingerprint, and
  /// the rebuild it caused redrew the lock gate — whose unlock button is a
  /// spinner while authentication is pending. An infinite animation, from a
  /// cache write, on a screen that has nothing to do with either.
  Future<void> setSponsorPayload(String? value) async {
    if (value == null) {
      await _prefs.remove('sponsor.payload');
    } else {
      await _prefs.setString('sponsor.payload', value);
    }
  }

  Future<void> setSponsorFetchedAt(DateTime value) =>
      _prefs.setInt('sponsor.fetched_at', value.millisecondsSinceEpoch);

  Future<void> setSponsorImagePath(String? value) async {
    if (value == null) {
      await _prefs.remove('sponsor.image_path');
    } else {
      await _prefs.setString('sponsor.image_path', value);
    }
  }

  /// Puts [id] away as of [at], and forgets the dismissals that have run out.
  ///
  /// The time comes from the caller rather than from `DateTime.now()` here:
  /// the service that owns this rule already has a clock, and a store that
  /// reads one of its own would answer a different question than the one the
  /// service asks — which is exactly the shape of a bug that only shows up
  /// under test, where the two clocks are not the same clock.
  ///
  /// The housekeeping is here rather than on a schedule because this is the
  /// only moment the map changes and the only moment anyone is waiting on it.
  /// Without it the map would keep an entry for every campaign ever
  /// dismissed, forever, to answer a question none of them can still affect.
  ///
  /// Silent, like the rest of the sponsor cache: the timeline calls
  /// `setState` for itself, and a card being put away is not a reason to
  /// rebuild every screen in the app.
  Future<void> dismissSponsor(
    String id, {
    required DateTime at,
    required Duration keepFor,
  }) async {
    final now = at;
    final kept = {
      for (final entry in sponsorDismissals.entries)
        if (now.difference(entry.value) < keepFor)
          entry.key: entry.value.millisecondsSinceEpoch,
      id: now.millisecondsSinceEpoch,
    };
    await _prefs.setString('sponsor.dismissed_at', jsonEncode(kept));
  }

  /* ----------------------------------------------------------------- update */

  /// Whether the app looks for a new release on its own.
  ///
  /// On by default. Nex ships outside any store, so without this a user only
  /// learns about a release by going to look for one.
  bool get autoUpdateCheck => _prefs.getBool('update.auto') ?? true;

  Future<void> setAutoUpdateCheck(bool value) async {
    await _prefs.setBool('update.auto', value);
    notifyListeners();
  }

  DateTime? get lastUpdateCheck {
    final millis = _prefs.getInt('update.lastCheck');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastUpdateCheck(DateTime value) async {
    await _prefs.setInt('update.lastCheck', value.millisecondsSinceEpoch);
    // Deliberately silent: the timestamp is bookkeeping, and rebuilding the
    // whole settings tree because a background check finished is noise.
  }
}
