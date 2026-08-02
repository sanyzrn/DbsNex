import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/feedback_service.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  test('the compiled-in default is empty, so an unconfigured build never '
      'touches the network', () async {
    final service = FeedbackService(preferences: preferences);
    addTearDown(service.close);

    expect(await service.send('hello'), FeedbackOutcome.unavailable);
  });

  test('a 202 is sent, and clears whatever was pending', () async {
    await preferences.setPendingFeedback('an old draft');
    final service = FeedbackService(
      preferences: preferences,
      baseUrl: 'https://example.invalid',
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.invalid/feedback');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['message'], 'hello');
        return http.Response('{}', 202);
      }),
    );
    addTearDown(service.close);

    expect(await service.send('hello'), FeedbackOutcome.sent);
    expect(preferences.pendingFeedback, isNull);
  });

  test('no network reaches the server at all is offline, not failed', () async {
    final service = FeedbackService(
      preferences: preferences,
      baseUrl: 'https://example.invalid',
      client: MockClient((_) async => throw const FormatException('no dns')),
    );
    addTearDown(service.close);

    expect(await service.send('hello'), FeedbackOutcome.offline);
  });

  test('the server rejecting the request is failed, not offline', () async {
    final service = FeedbackService(
      preferences: preferences,
      baseUrl: 'https://example.invalid',
      client: MockClient((_) async => http.Response('nope', 503)),
    );
    addTearDown(service.close);

    expect(await service.send('hello'), FeedbackOutcome.failed);
  });

  group('flushPending', () {
    test('nothing pending does nothing', () async {
      var calls = 0;
      final service = FeedbackService(
        preferences: preferences,
        baseUrl: 'https://example.invalid',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 202);
        }),
      );
      addTearDown(service.close);

      await service.flushPending();
      expect(calls, 0);
    });

    test('a pending message is retried and cleared on success', () async {
      await preferences.setPendingFeedback('typed while offline');
      final service = FeedbackService(
        preferences: preferences,
        baseUrl: 'https://example.invalid',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['message'], 'typed while offline');
          return http.Response('{}', 202);
        }),
      );
      addTearDown(service.close);

      await service.flushPending();
      expect(preferences.pendingFeedback, isNull);
    });

    test('still offline leaves it pending for the next resume', () async {
      await preferences.setPendingFeedback('typed while offline');
      final service = FeedbackService(
        preferences: preferences,
        baseUrl: 'https://example.invalid',
        client: MockClient((_) async => throw const FormatException('no dns')),
      );
      addTearDown(service.close);

      await service.flushPending();
      expect(preferences.pendingFeedback, 'typed while offline');
    });

    test('a hard rejection drops it rather than retrying forever', () async {
      await preferences.setPendingFeedback('typed while offline');
      final service = FeedbackService(
        preferences: preferences,
        baseUrl: 'https://example.invalid',
        client: MockClient((_) async => http.Response('nope', 400)),
      );
      addTearDown(service.close);

      await service.flushPending();
      expect(preferences.pendingFeedback, isNull);
    });
  });
}
