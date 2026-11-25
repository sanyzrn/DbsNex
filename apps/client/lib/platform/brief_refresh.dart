import 'dart:async';

import 'package:nex_ai/cloud.dart';

import 'nex_preferences.dart';

/// One request per service graph, including while the timeline is recreated.
/// The flight includes persistence: another delivery cannot read a half-written
/// cache and ask the provider again. Failures never replace a successful brief.
class NexBriefRefresh {
  NexBriefRefresh(this.preferences, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final NexPreferences preferences;
  final DateTime Function() _clock;
  static const successInterval = Duration(hours: 1);
  static const failureInterval = Duration(minutes: 15);

  /// How soon an expired brief may be replaced.
  ///
  /// The hourly interval is what stops a library somebody is typing into from
  /// spending a request a minute. Expiry is a different event: the facts moved
  /// by themselves, and the words on file are no longer true. They are not
  /// shown any more either way — the local lines stand in — so this is only
  /// about how quickly a replacement is asked for, and a couple of minutes is
  /// enough for a library where several items fall due close together to
  /// spend one request rather than one each.
  static const expiredInterval = Duration(minutes: 2);
  Future<NexBriefRefreshResult>? _pending;
  Future<String?>? _headlinePending;
  String? _headlinePendingKey;

  Future<String?> headline({
    required String dateKey,
    required String? language,
    required Future<String?> Function() request,
    bool force = false,
    String? part,
  }) {
    bool accepts(String? text) =>
        AiOutputLanguage.fromWire(language).acceptsGreeting(text);
    // A cached line is only this moment's line: same day, same part of it,
    // same language. The part is what 2.9.0 added — without it, last night's
    // phrase was a valid cache hit all through the morning.
    String? cachedHeadline() {
      final text = preferences.aiHeadlineText;
      final sameMoment =
          preferences.aiHeadlineDate == dateKey &&
          preferences.aiHeadlinePart == part &&
          preferences.aiHeadlineLang == language;
      return sameMoment && accepts(text) ? text : null;
    }

    // The flight belongs to a moment too. A request for another part of the
    // day cannot answer this one, and waiting on it would hold the line until
    // a phrase about the wrong hour came back.
    final flightKey = '$dateKey|$part|$language';
    final pending = _headlinePending;
    if (pending != null) {
      if (_headlinePendingKey == flightKey) return pending;
      return Future.value(cachedHeadline());
    }
    if (!force) {
      final cached = cachedHeadline();
      if (cached != null && cached.isNotEmpty) return Future.value(cached);
      final failed = preferences.aiHeadlineFailedAt;
      if (failed != null && _clock().difference(failed) < failureInterval) {
        return Future.value(cached);
      }
    }
    final completer = Completer<String?>();
    final flight = completer.future.whenComplete(() {
      _headlinePending = null;
      _headlinePendingKey = null;
    });
    _headlinePending = flight;
    _headlinePendingKey = flightKey;
    Future.sync(() async {
      String? text;
      try {
        text = (await request())?.trim();
      } catch (_) {
        text = null;
      }
      if (!accepts(text)) {
        await preferences.setAiHeadlineFailure(_clock());
        return cachedHeadline();
      }
      await preferences.setAiHeadline(
        text: text!,
        dateKey: dateKey,
        lang: language,
        part: part,
      );
      return text;
    }).then(completer.complete, onError: completer.completeError);
    return flight;
  }

  /// Whether the recap on file has stopped describing the library, and enough
  /// time has passed for that to be worth a request.
  ///
  /// [expired] is the third reason, and the one the data alone cannot see: the
  /// words were true when they were written and the clock has since moved
  /// past a fact they state.
  static bool needsRefresh({
    required DateTime? at,
    required String? text,
    required String? storedSource,
    required String fingerprint,
    required DateTime now,
    DateTime? failedAt,
    bool expired = false,
  }) {
    if (failedAt != null && now.difference(failedAt) < failureInterval) {
      return false;
    }
    final has = at != null && text != null && text.isNotEmpty;
    if (has && expired) return now.difference(at) >= expiredInterval;
    if (at != null && now.difference(at) < successInterval) return false;
    return !has || storedSource != fingerprint;
  }

  /// Whether the words on file have outlived the moment they describe.
  bool get expired {
    final until = preferences.aiDaySummaryValidUntil;
    final text = preferences.aiDaySummaryText;
    if (until == null || text == null || text.isEmpty) return false;
    return !_clock().isBefore(until);
  }

  bool needs(String fingerprint) => needsRefresh(
    at: preferences.aiDaySummaryCurrent ? preferences.aiDaySummaryAt : null,
    text: preferences.aiDaySummaryText,
    storedSource: preferences.aiDaySummarySource,
    fingerprint: fingerprint,
    now: _clock(),
    failedAt: preferences.aiDaySummaryFailedAt,
    expired: expired,
  );

  /// Only used for changed data awaiting its cooldown, never periodic polling.
  DateTime nextAllowedAt() {
    var next = _clock();
    final failedAt = preferences.aiDaySummaryFailedAt;
    // A failed attempt is the cooldown even when the words have expired:
    // retrying a provider that has just refused would spend a request on
    // every wake-up and learn nothing.
    if (failedAt != null && next.difference(failedAt) < failureInterval) {
      return failedAt.add(failureInterval);
    }
    if (expired) {
      final retry = preferences.aiDaySummaryAt?.add(expiredInterval);
      return retry != null && retry.isAfter(next) ? retry : next;
    }
    for (final date in [
      if (preferences.aiDaySummaryCurrent)
        preferences.aiDaySummaryAt?.add(successInterval),
      preferences.aiDaySummaryFailedAt?.add(failureInterval),
    ]) {
      if (date != null && date.isAfter(next)) next = date;
    }
    return next;
  }

  Future<NexBriefRefreshResult> refresh({
    required String fingerprint,
    required String dateKey,
    required Future<String?> Function() request,
    bool force = false,
    bool includesHabits = false,
    String? notesOnlyFallback,
    DateTime? validUntil,
    Future<bool> Function()? canPersist,
  }) {
    final pending = _pending;
    if (pending != null) return pending;
    if (!force && !needs(fingerprint)) {
      return Future.value(NexBriefRefreshResult(preferences.aiDaySummaryText));
    }
    // Install the shared flight before invoking even a synchronous callback.
    // Manual refresh bypasses time, not deduping.
    final completer = Completer<NexBriefRefreshResult>();
    final flight = completer.future.whenComplete(() => _pending = null);
    _pending = flight;
    Future.sync(() async {
      String? text;
      try {
        text = (await request())?.trim();
      } catch (_) {
        text = null;
      }
      if (includesHabits && !preferences.briefHabitsAllowed) {
        return NexBriefRefreshResult(preferences.aiDaySummaryText);
      }
      if (text == null || text.isEmpty) {
        await preferences.setAiDaySummaryFailure(_clock());
        return NexBriefRefreshResult(
          preferences.aiDaySummaryText,
          failed: true,
        );
      }
      // The data, settings or facts can change while the provider is busy.
      // Refuse the answer before it reaches any shared cache or surface.
      if (canPersist != null && !await canPersist()) {
        return const NexBriefRefreshResult(null);
      }
      if (validUntil != null && !_clock().isBefore(validUntil)) {
        return const NexBriefRefreshResult(null);
      }
      await preferences.setAiDaySummary(
        text: text,
        dateKey: dateKey,
        at: _clock(),
        source: fingerprint,
        includesHabits: includesHabits,
        notesOnlyFallback: notesOnlyFallback,
        validUntil: validUntil,
      );
      return NexBriefRefreshResult(text, updated: true);
    }).then(completer.complete, onError: completer.completeError);
    return flight;
  }
}

class NexBriefRefreshResult {
  const NexBriefRefreshResult(
    this.text, {
    this.failed = false,
    this.updated = false,
  });
  final String? text;
  final bool failed;
  final bool updated;
}
