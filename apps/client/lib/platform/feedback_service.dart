import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'device_label.dart';
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

/// What a piece of feedback is about, as the relay's `kind` field names it.
enum FeedbackKind { bug, idea, other }

/// Sends feedback to the app's own backend, which forwards it to Telegram —
/// never a bot token embedded in this client, which a public app cannot keep
/// secret from anyone who unpacks the APK.
class FeedbackService {
  FeedbackService({
    http.Client? client,
    required this.preferences,
    this.baseUrl = nexFeedbackApiUrl,
    this.describeDevice = NexDevice.describe,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final NexPreferences preferences;

  /// Overridable only for tests — every real caller relies on the compiled-in
  /// default, the same way [UpdateChecker.repository] is a constructor
  /// default rather than something a screen decides.
  final String baseUrl;

  /// The phone it is sent from; replaced in tests.
  final Future<NexDeviceLabel> Function() describeDevice;

  final http.Client _client;
  final bool _ownsClient;

  /// Sends [message], and the [diagnostics] report the person chose to
  /// attach, if any. The relay forwards the report to the chat as a file.
  Future<FeedbackOutcome> send(
    String message, {
    FeedbackKind? kind,
    String? contact,
    String? diagnostics,
  }) async {
    if (baseUrl.isEmpty) return FeedbackOutcome.unavailable;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return FeedbackOutcome.failed;
    final reply = contact?.trim() ?? '';

    try {
      final device = await describeDevice();
      final response = await _client
          .post(
            Uri.parse('$baseUrl/feedback'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'message': trimmed,
              'appVersion': nexAppVersion,
              'platform': device.platform,
              'device': ?device.device,
              'kind': ?kind?.name,
              if (reply.isNotEmpty) 'contact': reply,
              if (diagnostics != null && diagnostics.trim().isNotEmpty)
                'diagnostics': diagnostics,
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
    final held = decodePending(pending);
    final outcome = await send(
      held.message,
      kind: held.kind,
      contact: held.contact,
      diagnostics: held.diagnostics,
    );
    // `.sent` already cleared it; `.failed` means the server rejected this
    // exact text, so holding onto it would only retry a fixed rejection.
    if (outcome == FeedbackOutcome.failed) {
      await preferences.setPendingFeedback(null);
    }
  }

  /// What [NexPreferences.pendingFeedback] holds: the message with its
  /// category and reply address, so a retry sends what was typed rather than
  /// the text alone. A plain string from before these existed is a message.
  static String encodePending(
    String message, {
    FeedbackKind? kind,
    String? contact,
    String? diagnostics,
  }) => jsonEncode({
    'message': message,
    'kind': ?kind?.name,
    if (contact != null && contact.trim().isNotEmpty) 'contact': contact.trim(),
    // The report as it was shown when Send was tapped, not a fresh read:
    // what goes out later is what the person agreed to.
    if (diagnostics != null && diagnostics.trim().isNotEmpty)
      'diagnostics': diagnostics,
  });

  static ({
    String message,
    FeedbackKind? kind,
    String? contact,
    String? diagnostics,
  })
  decodePending(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map && value['message'] is String) {
        return (
          message: value['message'] as String,
          kind: FeedbackKind.values
              .where((k) => k.name == value['kind'])
              .firstOrNull,
          contact: value['contact'] as String?,
          diagnostics: value['diagnostics'] as String?,
        );
      }
    } on FormatException {
      // Not JSON: a message queued by an older build.
    }
    return (message: raw, kind: null, contact: null, diagnostics: null);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
