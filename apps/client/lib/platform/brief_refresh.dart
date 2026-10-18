import 'dart:async';

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
  Future<NexBriefRefreshResult>? _pending;
  Future<String?>? _headlinePending;

  Future<String?> headline({
    required String dateKey,
    required String? language,
    required Future<String?> Function() request,
    bool force = false,
  }) {
    final pending = _headlinePending;
    if (pending != null) return pending;
    if (!force) {
      final cached = preferences.aiHeadlineText;
      if (preferences.aiHeadlineDate == dateKey &&
          preferences.aiHeadlineLang == language &&
          cached != null &&
          cached.isNotEmpty) {
        return Future.value(cached);
      }
      final failed = preferences.aiHeadlineFailedAt;
      if (failed != null && _clock().difference(failed) < failureInterval) {
        return Future.value(cached);
      }
    }
    final completer = Completer<String?>();
    final flight = completer.future.whenComplete(() => _headlinePending = null);
    _headlinePending = flight;
    Future.sync(() async {
      String? text;
      try {
        text = (await request())?.trim();
      } catch (_) {
        text = null;
      }
      if (text == null || text.isEmpty) {
        await preferences.setAiHeadlineFailure(_clock());
        return preferences.aiHeadlineText;
      }
      await preferences.setAiHeadline(
        text: text,
        dateKey: dateKey,
        lang: language,
      );
      return text;
    }).then(completer.complete, onError: completer.completeError);
    return flight;
  }

  static bool needsRefresh({
    required DateTime? at,
    required String? text,
    required String? storedSource,
    required String fingerprint,
    required DateTime now,
    DateTime? failedAt,
  }) {
    if (failedAt != null && now.difference(failedAt) < failureInterval) {
      return false;
    }
    if (at != null && now.difference(at) < successInterval) return false;
    return at == null ||
        text == null ||
        text.isEmpty ||
        storedSource != fingerprint;
  }

  bool needs(String fingerprint) => needsRefresh(
    at: preferences.aiDaySummaryAt,
    text: preferences.aiDaySummaryText,
    storedSource: preferences.aiDaySummarySource,
    fingerprint: fingerprint,
    now: _clock(),
    failedAt: preferences.aiDaySummaryFailedAt,
  );

  /// Only used for changed data awaiting its cooldown, never periodic polling.
  DateTime nextAllowedAt() {
    var next = _clock();
    for (final date in [
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
      if (text == null || text.isEmpty) {
        await preferences.setAiDaySummaryFailure(_clock());
        return NexBriefRefreshResult(
          preferences.aiDaySummaryText,
          failed: true,
        );
      }
      await preferences.setAiDaySummary(
        text: text,
        dateKey: dateKey,
        at: _clock(),
        source: fingerprint,
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
