import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/sponsor.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// flutter_test registers no plugin for `getApplicationSupportPath`, which is
/// where the sponsor's picture is cached.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

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

      expect(
        preferences.sponsorPayload,
        isNotNull,
        reason: 'the card that was there is not thrown away by a bad network',
      );
      expect(
        preferences.sponsorFetchedAt,
        isNull,
        reason: 'so the next launch tries again instead of waiting a day',
      );
      // It is kept, and it is not shown: nothing has ever been fetched, so
      // there is no successful check to be recent. See the "going quiet"
      // group for the rule.
      expect(service.visible(languageCode: 'en'), isNull);
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

    test('caching a card does not wake every listener in the app', () async {
      // The bug this is here for, which took a "pumpAndSettle timed out" to
      // find: these writes used to notify, so a background HTTP reply
      // rebuilt the whole app — including the lock gate, whose unlock button
      // is a spinner while a fingerprint is pending. An infinite animation,
      // caused by a cache write, on a screen with nothing to do with either.
      //
      // The card is not a setting. The one screen that shows it calls
      // setState itself.
      var woken = 0;
      // Held in a variable: `removeListener` matches by identity, so passing
      // a fresh closure removes nothing and leaves the listener attached to
      // a preferences object the next test rebuilds.
      void count() => woken++;
      preferences.addListener(count);
      addTearDown(() => preferences.removeListener(count));

      final service = serviceReturning((_) => http.Response(card(), 200));
      await service.refresh();
      await service.dismiss('c1');

      expect(woken, 0);
    });

    test('dismissing survives the next fetch of the same card', () async {
      final service = serviceReturning((_) => http.Response(card(), 200));
      await service.refresh();
      await service.dismiss('c1');
      await service.refresh(force: true);

      expect(service.visible(languageCode: 'en'), isNull);
    });
  });

  group('pictures', () {
    late NexPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await NexPreferences.load();
      final tmp = Directory.systemTemp.createTempSync('nex_sponsor_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    });

    /// A one-pixel GIF: real bytes with a real magic number, so the format
    /// check is exercised rather than mocked around.
    final gif = Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, //
      0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
    ]);

    String withImage() => jsonEncode({
      'id': 'c1',
      'title': 'A local bookshop',
      'image': 'https://example.com/banner.gif',
    });

    NexSponsorService service(
      http.Response Function(http.Request request) respond,
    ) => NexSponsorService(
      preferences: preferences,
      client: MockClient((request) async => respond(request)),
      now: () => now,
    );

    test('the picture is fetched and kept beside the card', () async {
      final s = service(
        (request) => request.url.path.endsWith('.gif')
            ? http.Response.bytes(gif, 200)
            : http.Response(withImage(), 200),
      );
      await s.refresh();

      expect(s.image, isNotNull);
      expect(s.visible(languageCode: 'en')?.id, 'c1');
      expect(preferences.sponsorImagePath, isNotNull);
    });

    test('a card whose picture will not come is not shown at all', () async {
      // Better an empty space than a banner with a hole where its design was.
      final s = service(
        (request) => request.url.path.endsWith('.gif')
            ? http.Response('', 404)
            : http.Response(withImage(), 200),
      );
      await s.refresh();

      expect(s.visible(languageCode: 'en'), isNull);
      expect(preferences.sponsorPayload, isNull);
    });

    test('an HTML error page is not a picture', () async {
      // What a captive portal answers with, and what caching would leave: a
      // card that can never draw.
      final s = service(
        (request) => request.url.path.endsWith('.gif')
            ? http.Response('<!doctype html><html>Blocked</html>', 200)
            : http.Response(withImage(), 200),
      );
      await s.refresh();

      expect(s.visible(languageCode: 'en'), isNull);
    });

    test('a picture over the ceiling is refused', () async {
      final huge = Uint8List.fromList([
        ...gif,
        ...List.filled(NexSponsorService.maxImageBytes, 0),
      ]);
      final s = service(
        (request) => request.url.path.endsWith('.gif')
            ? http.Response.bytes(huge, 200)
            : http.Response(withImage(), 200),
      );
      await s.refresh();

      expect(s.visible(languageCode: 'en'), isNull);
    });

    test('a card with no picture needs none', () async {
      final s = service((_) => http.Response(card(), 200));
      await s.refresh();

      expect(s.image, isNull);
      expect(s.visible(languageCode: 'en')?.id, 'c1');
    });
  });

  group('going quiet', () {
    late NexPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await NexPreferences.load();
    });

    test('a card stops showing once the last fetch is old', () async {
      // The offline rule. There is no connectivity plugin and no wish for
      // one: a phone that cannot reach the host stops refreshing, the last
      // answer ages out, and the card goes — rather than a campaign that
      // ended in March sitting in the timeline of a phone that has had its
      // data off since then.
      await preferences.setSponsorPayload(card());
      await preferences.setSponsorFetchedAt(now);

      NexSponsorService at(DateTime when) => NexSponsorService(
        preferences: preferences,
        client: MockClient((_) async => http.Response('', 500)),
        now: () => when,
      );

      expect(at(now).visible(languageCode: 'en')?.id, 'c1');
      expect(
        at(now.add(const Duration(hours: 47))).visible(languageCode: 'en'),
        isNotNull,
        reason: 'one missed check is not enough to lose a running card',
      );
      expect(
        at(now.add(const Duration(hours: 49))).visible(languageCode: 'en'),
        isNull,
      );
    });

    test('a device that has never fetched shows nothing', () async {
      await preferences.setSponsorPayload(card());
      final s = NexSponsorService(
        preferences: preferences,
        client: MockClient((_) async => http.Response('', 500)),
        now: () => now,
      );
      expect(s.visible(languageCode: 'en'), isNull);
    });
  });
}

/// A stand-in for whatever the platform throws when there is no network.
class SocketFailure implements Exception {
  const SocketFailure();
}