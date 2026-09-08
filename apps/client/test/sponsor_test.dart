import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/sponsor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rule this file exists for: **when there is nothing to show, nothing
/// appears.** Every way the fetch or the file can go wrong has to end in the
/// same silence — no placeholder, no error, no stale card running forever.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 9, 15, 12);

  String card({
    String id = 'c1',
    String title = 'A local bookshop',
    String? starts,
    String? ends,
    List<String>? locales,
  }) => jsonEncode({
    'id': id,
    'title': title,
    'body': 'Ten percent off this month',
    'color': '#F0A93B',
    'url': 'https://example.com',
    if (starts != null) 'starts': starts,
    if (ends != null) 'ends': ends,
    if (locales != null) 'locales': locales,
  });

  group('parse', () {
    test('reads a whole card', () {
      final sponsor = NexSponsor.parse(card())!;
      expect(sponsor.id, 'c1');
      expect(sponsor.title, 'A local bookshop');
      expect(sponsor.url, 'https://example.com');
    });

    test('every malformed shape is no card, not an exception', () {
      for (final source in [
        '',
        'not json',
        '[]',
        '{}',
        // An HTML error page from a proxy, which is the failure that actually
        // happens on hotel wifi.
        '<!doctype html><html><body>Blocked</body></html>',
        // Present but useless: nothing to draw.
        '{"id":"c1"}',
        '{"title":"only a title"}',
        '{"id":"","title":"blank id"}',
        '{"id":"c1","title":"   "}',
      ]) {
        expect(NexSponsor.parse(source), isNull, reason: source);
      }
    });

    test('an unknown field does not spoil a readable card', () {
      // A newer publisher writing a field this build has never heard of.
      final sponsor = NexSponsor.parse(
        '{"id":"c1","title":"Hello","priority":9,"segments":["x"]}',
      );
      expect(sponsor?.title, 'Hello');
    });
  });

  group('visibleAt', () {
    NexSponsor parsed(String source) => NexSponsor.parse(source)!;

    bool visible(NexSponsor sponsor, {String locale = 'en', Set<String>? hidden}) =>
        sponsor.visibleAt(
          now: now,
          languageCode: locale,
          dismissed: hidden ?? const {},
        );

    test('a card with no dates is always in season', () {
      expect(visible(parsed(card())), isTrue);
    });

    test('not before it starts, not after it ends', () {
      expect(
        visible(parsed(card(starts: '2026-10-01T00:00:00Z'))),
        isFalse,
        reason: 'scheduled for next month',
      );
      expect(
        visible(parsed(card(ends: '2026-09-01T00:00:00Z'))),
        isFalse,
        reason: 'finished a fortnight ago',
      );
      expect(
        visible(
          parsed(
            card(starts: '2026-09-01T00:00:00Z', ends: '2026-10-01T00:00:00Z'),
          ),
        ),
        isTrue,
      );
    });

    test('a card written in one language is not shown in another', () {
      final persian = parsed(card(locales: ['fa']));
      expect(visible(persian, locale: 'fa'), isTrue);
      expect(visible(persian, locale: 'en'), isFalse);
      // No list means everyone.
      expect(visible(parsed(card()), locale: 'en'), isTrue);
    });

    test('dismissed is dismissed', () {
      expect(visible(parsed(card()), hidden: {'c1'}), isFalse);
      expect(
        visible(parsed(card(id: 'c2')), hidden: {'c1'}),
        isTrue,
        reason: 'a different campaign is a different card',
      );
    });
  });

  group('the service', () {
    late NexPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await NexPreferences.load();
    });

    NexSponsorService serviceReturning(
      http.Response Function(http.Request request) respond, {
      DateTime? at,
    }) => NexSponsorService(
      preferences: preferences,
      client: MockClient((request) async => respond(request)),
      now: () => at ?? now,
    );

    test('a card that arrives is cached and shown', () async {
      final service = serviceReturning((_) => http.Response(card(), 200));
      await service.refresh();

      expect(preferences.sponsorPayload, isNotNull);
      expect(service.visible(languageCode: 'en')?.id, 'c1');
    });

    test('a 404 takes the card down rather than leaving it up', () async {
      await preferences.setSponsorPayload(card());
      final service = serviceReturning((_) => http.Response('', 404));
      await service.refresh();

      expect(
        preferences.sponsorPayload,
        isNull,
        reason: 'deleting the file is how a campaign ends',
      );
      expect(service.visible(languageCode: 'en'), isNull);
    });

    test('a failed request leaves the cache and does not start the clock', () async {
      await preferences.setSponsorPayload(card());
      final service = NexSponsorService(
        preferences: preferences,
        client: MockClient((_) async => throw const SocketFailure()),
        now: () => now,
      );
      await service.refresh();

      expect(service.visible(languageCode: 'en')?.id, 'c1');
      expect(
        preferences.sponsorFetchedAt,
        isNull,
        reason: 'so the next launch tries again instead of waiting a day',
      );
    });

    test('a body far too large is not a card', () async {
      final service = serviceReturning(
        (_) => http.Response('x' * (NexSponsorService.maxBytes + 1), 200),
      );
      await service.refresh();
      expect(preferences.sponsorPayload, isNull);
    });

    test('it asks at most once a day', () async {
      var asked = 0;
      final service = NexSponsorService(
        preferences: preferences,
        client: MockClient((_) async {
          asked++;
          return http.Response(card(), 200);
        }),
        now: () => now,
      );
      await service.refresh();
      await service.refresh();
      expect(asked, 1);

      await service.refresh(force: true);
      expect(asked, 2, reason: 'unless asked outright');
    });

    test('dismissing survives the next fetch of the same card', () async {
      final service = serviceReturning((_) => http.Response(card(), 200));
      await service.refresh();
      await service.dismiss('c1');
      await service.refresh(force: true);

      expect(service.visible(languageCode: 'en'), isNull);
    });
  });
}

/// A stand-in for whatever the platform throws when there is no network.
class SocketFailure implements Exception {
  const SocketFailure();
}
