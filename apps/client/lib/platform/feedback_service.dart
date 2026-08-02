import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'nex_preferences.dart';

/// Where feedback goes — a server this app's developer controls, never the
/// arbitrary sync endpoint a user may have typed into Settings. Empty by
/// default: unset, [FeedbackService.send] answers [FeedbackOutcome.unavailable]
/// without ever touching the network, the same way the backend itself answers
/// 503 when its own Telegram credentials are unset.
const nexFeedbackApiUrl = String.fromEnvironment('NEX_FEEDBACK_API_URL');

enum FeedbackOutcome {
  /// Delivered.
  sent,

  /// No network reached, or the request timed out — retryable.
  offline,

  /// The server understood the request and refused it (bad payload, 5xx from
  /// its own Telegram call). Not retryable with the same text.
  failed,

  /// This build has no feedback endpoint configured at all.
  unavailable,
}

/// Sends feedback to the app's own backend, which forwards it to Telegram —
/// never a bot token embedded in this client, which a public app cannot keep
/// secret from anyone who unpacks the APK.
class FeedbackService {
  FeedbackService({
    http.Client? client,
    required this.preferences,
    this.baseUrl = nexFeedbackApiUrl,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final NexPreferences preferences;

  /// Overridable only for tests — every real caller relies on the compiled-in
  /// default, the same way [UpdateChecker.repository] is a constructor
  /// default rather than something a screen decides.
  final String baseUrl;

  final http.Client _client;
  final bool _ownsClient;

  Future<FeedbackOutcome> send(String message) async {
    if (baseUrl.isEmpty) return FeedbackOutcome.unavailable;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return FeedbackOutcome.failed;

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/feedback'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'message': trimmed,
              'appVersion': nexAppVersion,
              'platform': Platform.operatingSystem,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 202) {
        await preferences.setPendingFeedback(null);
        return FeedbackOutcome.sent;
      }
      // A 4xx/5xx from our own server, as opposed to never reaching it — the
      // server saw this exact text and said no, so resending it unchanged on
      // the next reconnect would only fail again.
      return FeedbackOutcome.failed;
    } on TimeoutException {
      return FeedbackOutcome.offline;
    } on SocketException {
      return FeedbackOutcome.offline;
    } catch (_) {
      return FeedbackOutcome.offline;
    }
  }

  /// Retries whatever [NexPreferences.pendingFeedback] is holding.
  ///
  /// Called on app resume rather than on a live connectivity listener — this
  /// app has no connectivity-watching dependency yet, and "the user came back
  /// to the app" is, in practice, also when a phone that regained signal
  /// while backgrounded gets noticed.
  Future<void> flushPending() async {
    final pending = preferences.pendingFeedback;
    if (pending == null) return;
    final outcome = await send(pending);
    // `.sent` already cleared it; `.failed` means the server rejected this
    // exact text, so holding onto it would only retry a fixed rejection.
    if (outcome == FeedbackOutcome.failed) {
      await preferences.setPendingFeedback(null);
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
