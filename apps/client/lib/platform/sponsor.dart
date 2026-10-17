import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'nex_preferences.dart';

/// A card the timeline may carry that is not a note.
///
/// Nex is free, and this is how it stays free without a paywall, an account,
/// or anything reading the library: one card, the size of a note card, whose
/// entire content is a file on a server. There is no ad network, no
/// identifier, no profile — the request says nothing about the person making
/// it beyond that a copy of Nex asked, and the answer is the same for
/// everyone who asks.
///
/// The rule that matters is the one about absence: **if there is nothing to
/// show, nothing appears.** A missing file, a malformed one, a network that
/// is not there, a card whose dates have passed, one already dismissed — all
/// of them are the same outcome, which is a timeline with no card in it. No
/// placeholder, no spinner, no "could not load".
class NexSponsor {
  const NexSponsor({
    required this.id,
    required this.title,
    this.body,
    this.color,
    this.image,
    this.url,
    this.starts,
    this.ends,
    this.locales = const [],
    this.minDays,
    this.minNotes,
  });

  /// How many days after Nex was first opened the card may appear, and how
  /// many notes make it appear sooner — `minDaysInstalled` and `minNotes` in
  /// the file. Whichever comes first. Null means the defaults in
  /// [NexSponsorService]; 0 means no wait.
  final int? minDays;
  final int? minNotes;

  /// Stable across edits to the same campaign, because it is what a dismissal
  /// remembers. Changing it brings the card back for everyone who hid it,
  /// which is the intended way to run a second campaign and the accidental
  /// way to annoy people.
  final String id;

  final String title;
  final String? body;

  /// `#RRGGBB`. The card is deliberately coloured — it is not a note, and
  /// looking like one would be the dishonest version of this.
  final String? color;

  /// A picture to fill the card with, or null for the words-and-a-colour
  /// version.
  ///
  /// Any format Flutter decodes on its own — JPEG, PNG, WebP, GIF, and the
  /// animated forms of the last two. Deliberately nothing that needs a
  /// package: an animated WebP is a few tens of kilobytes and plays with no
  /// dependency at all, which is a better trade than a video decoder for a
  /// card the height of one note.
  final String? image;

  /// Opened when the card is tapped. A card with no link is still legitimate:
  /// an announcement is allowed to be just words.
  final String? url;

  final DateTime? starts;
  final DateTime? ends;

  /// Preferred interface languages. Matching campaigns are picked first;
  /// an available campaign still shows when none matches the interface.
  final List<String> locales;

  /// Parses the file, or returns null for every way it can fail to be one.
  ///
  /// Deliberately total: a half-written file, a newer format, an HTML error
  /// page served by a proxy, or an empty object all mean "no card", because
  /// there is no failure here worth telling anyone about.
  static NexSponsor? parse(String source) {
    try {
      final root = jsonDecode(source);
      if (root is! Map<String, Object?>) return null;
      final id = root['id'];
      final title = root['title'];
      if (id is! String || id.isEmpty) return null;
      if (title is! String || title.trim().isEmpty) return null;
      return NexSponsor(
        id: id,
        title: title.trim(),
        body: (root['body'] as String?)?.trim(),
        color: root['color'] as String?,
        image: root['image'] as String?,
        url: root['url'] as String?,
        starts: DateTime.tryParse('${root['starts'] ?? ''}'),
        ends: DateTime.tryParse('${root['ends'] ?? ''}'),
        locales: [
          for (final value in (root['locales'] as List<Object?>? ?? const []))
            if (value is String) value.toLowerCase(),
        ],
        minDays: _count(root['minDaysInstalled']),
        minNotes: _count(root['minNotes']),
      );
    } catch (_) {
      return null;
    }
  }

  /// A whole number of zero or more, or null for anything else — a missing
  /// field and a nonsense one both mean "the default".
  static int? _count(Object? value) =>
      value is int && value >= 0 ? value : null;

  /// Whether this card belongs on screen right now.
  ///
  /// Pure, and separate from the fetch, because every one of these rules is a
  /// way to show somebody the wrong thing and none of them needs a network to
  /// be tested.
  bool visibleAt({required DateTime now, required Set<String> dismissed}) {
    if (dismissed.contains(id)) return false;
    if (starts != null && now.isBefore(starts!)) return false;
    if (ends != null && !now.isBefore(ends!)) return false;
    return true;
  }
}

/// Fetches [NexSponsor] and remembers the answer.
///
/// The small campaign document is revalidated hourly on launch/resume. A
/// manual refresh can revalidate sooner; failures share a short cooldown.
///
/// The cache is what makes the card appear instantly rather than a second
/// after the timeline draws. A card that pops in under the reader's thumb is
/// worse than no card.
class NexSponsorService {
  NexSponsorService({
    required this.preferences,
    http.Client? client,
    this.endpoint = defaultEndpoint,
    this.dismissible = dismissibleByDefault,
    DateTime Function()? now,
    Random? random,
  }) : _client = client,
       _now = now ?? DateTime.now,
       _random = random ?? Random();

  final Random _random;

  /// How many cards one file may offer. More than this are ignored.
  static const maxCards = 5;

  /// The card this phone shows from [body]: the file itself when it is one
  /// card, or one of up to [maxCards] picked at random when it is a list.
  ///
  /// The pick prefers cards in the interface language (or with no language
  /// preference), falling back to any active campaign when none matches.
  /// It is made once per refresh, at most hourly, and kept until
  /// the next: one phone keeps its card until revalidation, and across phones each
  /// card is seen about as often as the others. Answers the card's own JSON,
  /// which is what is cached; null when the file is not a card or a list of
  /// them, and an empty string for a list with nothing to show here.
  String? choose(String body, {required String languageCode}) {
    final Object? root;
    try {
      root = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (root is Map) return NexSponsor.parse(body) == null ? null : body;
    if (root is! List) return null;
    final now = _now();
    final cards = <String>[];
    final fallback = <String>[];
    for (final item in root.take(maxCards)) {
      if (item is! Map) continue;
      final json = jsonEncode(item);
      final card = NexSponsor.parse(json);
      if (card == null) continue;
      if (!card.visibleAt(now: now, dismissed: {})) continue;
      fallback.add(json);
      if (card.locales.isEmpty ||
          card.locales.contains(languageCode.toLowerCase())) {
        cards.add(json);
      }
    }
    final available = cards.isEmpty ? fallback : cards;
    if (available.isEmpty) return '';
    return available[_random.nextInt(available.length)];
  }

  /// Closing a campaign hides it temporarily on this device.
  static const dismissibleByDefault = true;

  final bool dismissible;

  /// On the maker's own site. Publishing a card is putting a file there;
  /// taking it down is deleting it, and a 404 is the "nothing to show" case
  /// working exactly as intended.
  static const defaultEndpoint = 'https://saeedzarrini.ir/banner.json';

  static const refreshInterval = Duration(hours: 1);

  /// After a failed refresh, do not turn every app open/resume into another
  /// request. Half an hour still recovers the same day, while keeping the
  /// worst-case traffic tiny even on a broken or filtered host.
  static const failedRefreshCooldown = Duration(minutes: 30);

  /// A due automatic refresh gets one immediate retry for transient failures.
  /// Manual pull-to-refresh gets one request only.
  static const automaticAttempts = 2;

  /// How stale the last *successful* fetch may be before the card stops
  /// appearing.
  ///
  /// This is what "nothing while offline" means in an app with no
  /// connectivity plugin and no wish for one. A phone that cannot reach the
  /// host stops refreshing, the last answer ages out, and the card goes —
  /// rather than a campaign that ended last month sitting in somebody's
  /// timeline because their data has been off since then.
  ///
  /// Preserve two days of offline tolerance; a missed hourly check is not
  /// enough to lose a campaign that is still running.
  static const maxAge = Duration(hours: 48);

  /// Per campaign, persisted across restarts; each close starts a new window.
  static const dismissalCoolOff = Duration(hours: 8);

  /// The ceiling on a picture. Half a megabyte is a generous animated WebP
  /// and a very large still; a card is not worth more of somebody's data
  /// than that, and the check happens before the bytes are kept rather than
  /// after.
  static const maxImageBytes = 512 * 1024;

  /// The first bytes of every format Flutter can decode without help. A
  /// server that answers a picture request with an HTML error page is the
  /// failure this catches — and caching that page would leave a card that
  /// can never draw.
  static const _imageMagic = <List<int>>[
    [0xFF, 0xD8, 0xFF], // JPEG
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], // PNG
    [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], // GIF87a
    [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], // GIF89a
    [0x42, 0x4D], // BMP
  ];

  /// A card is a couple of hundred bytes, and a list of [maxCards] a couple
  /// of kilobytes. Anything much larger is not the file this expects, and
  /// reading it into memory to find that out is the mistake this avoids.
  static const maxBytes = 16 * 1024;

  final NexPreferences preferences;
  final String endpoint;
  final http.Client? _client;
  final DateTime Function() _now;

  Future<bool>? _refreshing;

  /// Where the cached picture lives, once one has been kept. Null before the
  /// first successful fetch of a card that has one.
  File? _image;

  /// Whether the picture has been looked for since launch. Until then a
  /// card with a picture waits rather than drawing its text version for a
  /// frame and then changing under the reader.
  bool _imageSettled = false;

  /// The same file through jsDelivr's copy of the repository.
  ///
  /// `raw.githubusercontent.com` is filtered on many networks in Iran, and on
  /// those phones the card simply never arrived — which read as "the banner
  /// sometimes does not show". The mirror serves the identical file from a
  /// different host. It is asked only when the first host cannot be reached
  /// at all: a 404 from GitHub still means the campaign has ended.
  static String? mirrorOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'raw.githubusercontent.com') return null;
    final parts = uri.pathSegments;
    if (parts.length < 4) return null;
    final rest = parts.skip(3).join('/');
    return 'https://cdn.jsdelivr.net/gh/${parts[0]}/${parts[1]}@${parts[2]}/$rest';
  }

  /// Bounded reads and one shared deadline for headers plus body. A large
  /// or slowly streaming error page must not consume unbounded memory/time.
  Future<http.Response> _get(
    http.Client client,
    String url,
    Duration timeout,
    int limit,
  ) async {
    Future<http.Response> fetch(String target) async {
      final clock = Stopwatch()..start();
      final response = await client
          .send(
            http.Request('GET', Uri.parse(target))
              ..headers['Cache-Control'] = 'no-cache'
              ..headers['Pragma'] = 'no-cache',
          )
          .timeout(timeout);
      if (response.statusCode != 200 || (response.contentLength ?? 0) > limit) {
        // StreamIterator subscribes lazily. Discarded responses still need
        // a real subscription cancelled so their connection can be released.
        unawaited(
          response.stream.listen(null).cancel().catchError((Object _) {}),
        );
        if (response.statusCode != 200) {
          return http.Response('', response.statusCode);
        }
        throw const FormatException('Sponsor response too large');
      }
      final chunks = StreamIterator(response.stream);
      try {
        final bytes = BytesBuilder(copy: false);
        while (true) {
          final left = timeout - clock.elapsed;
          if (left <= Duration.zero) {
            throw TimeoutException('Sponsor response deadline');
          }
          if (!await chunks.moveNext().timeout(left)) break;
          if (bytes.length + chunks.current.length > limit) {
            throw const FormatException('Sponsor response too large');
          }
          bytes.add(chunks.current);
        }
        return http.Response.bytes(
          bytes.takeBytes(),
          response.statusCode,
          headers: response.headers,
        );
      } finally {
        // Some transports finish cancellation asynchronously. Releasing a
        // response must not hold the UI or overrun the request deadline.
        unawaited(chunks.cancel().catchError((Object _) {}));
      }
    }

    final mirror = mirrorOf(url);
    http.Response? original;
    try {
      original = await fetch(url);
      // A canonical 404/410 is final. Filtering and server errors can use
      // the same trusted mirror as a connection failure.
      if (mirror == null ||
          (original.statusCode != 403 &&
              original.statusCode != 429 &&
              original.statusCode < 500)) {
        return original;
      }
    } catch (_) {
      if (mirror == null) rethrow;
    }
    final fallback = await fetch(mirror);
    if (fallback.statusCode == 200) return fallback;
    // A mirror that has not cached the file is not proof the campaign ended.
    return original ?? http.Response('', 503);
  }

  /// What was fetched last, whenever that was. Read synchronously so the
  /// first frame of the timeline already knows.
  NexSponsor? get cached {
    final raw = preferences.sponsorPayload;
    return raw == null || raw.isEmpty ? null : NexSponsor.parse(raw);
  }

  /// The picture to draw with the card, or null when it has none.
  File? get image => _image;

  /// Whether the last successful fetch is recent enough to trust.
  bool get _fresh {
    final at = preferences.sponsorFetchedAt;
    if (at == null) return false;
    final age = _now().difference(at);
    return !age.isNegative && age < maxAge;
  }

  /// The days and notes a new install waits for, unless the file says
  /// otherwise ([NexSponsor.minDays], [NexSponsor.minNotes]).
  static const defaultMinDays = 10;
  static const defaultMinNotes = 5;

  /// Whether this phone has earned the card: [NexSponsor.minDays] since Nex
  /// was first opened, *or* [NexSponsor.minNotes] notes — whichever comes
  /// first. A new person's first days are for finding out what the app is,
  /// not for being shown someone else's.
  ///
  /// Once earned it stays earned, so the card does not come and go as notes
  /// are deleted, and deleting notes is not a way to hide it.
  bool earned(NexSponsor sponsor, {required int notes}) {
    if (preferences.sponsorEarned) return true;
    var first = preferences.firstOpenedAt;
    if (first == null) {
      first = _now();
      unawaited(preferences.markFirstOpened(first));
    }
    final days = sponsor.minDays ?? defaultMinDays;
    final enough =
        notes >= (sponsor.minNotes ?? defaultMinNotes) ||
        _now().difference(first) >= Duration(days: days);
    if (enough) unawaited(preferences.markSponsorEarned());
    return enough;
  }

  /// The card to draw, or null. The only method the timeline needs.
  ///
  /// [notes] is how many notes the library holds, for [earned].
  NexSponsor? visible({int notes = 0}) {
    // Stale is the same as absent. See [maxAge].
    if (!_fresh) return null;
    final sponsor = cached;
    if (sponsor == null) return null;
    // A picture that could not be had leaves the card in words: its title is
    // required and always says what it is. Only the first moments after
    // launch wait, while yesterday's picture is still being found on disk.
    if (sponsor.image != null && _image == null && !_imageSettled) return null;
    if (!earned(sponsor, notes: notes)) return null;
    return sponsor.visibleAt(
          now: _now(),
          dismissed: dismissible ? _dismissed : const {},
        )
        ? sponsor
        : null;
  }

  /// Reads a response body as the UTF-8 it is, whatever the server says.
  ///
  /// `http.Response.body` decodes with the charset in the Content-Type
  /// header and falls back to Latin-1 when there is none — which a static
  /// `.json` file on a plain web host often has. Every Persian title came out
  /// as mojibake on those responses, and the same card read correctly from a
  /// host that did send `charset=utf-8`. A byte-order mark, which some
  /// editors write at the start of a saved file, is dropped as well: JSON
  /// does not allow one, and with it the whole card failed to parse.
  static String decodeBody(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  DateTime? get dismissedUntil {
    final at = preferences.sponsorDismissals[cached?.id];
    if (at == null || at.isAfter(_now())) return null;
    final until = at.add(dismissalCoolOff);
    return until.isAfter(_now()) ? until : null;
  }

  /// The cards still inside their [dismissalCoolOff].
  ///
  /// Read through rather than stored as a set: the answer changes with the
  /// clock and not with anything this app does, so there is nothing to
  /// invalidate and no moment at which to invalidate it.
  Set<String> get _dismissed {
    final now = _now();
    return {
      for (final entry in preferences.sponsorDismissals.entries)
        if (!now.isBefore(entry.value) &&
            now.difference(entry.value) < dismissalCoolOff)
          entry.key,
    };
  }

  /// Points [image] at a picture already on disk from a previous run.
  ///
  /// Called once when the timeline starts, before the network is asked,
  /// so a card that was fetched yesterday draws on the first frame today.
  Future<void> restoreCachedImage() async {
    try {
      final path = preferences.sponsorImagePath;
      if (path == null) return;
      final file = File(path);
      if (await file.exists()) _image = file;
    } catch (_) {
      // A cache read failure must not prevent the launch refresh or text fallback.
      _image = null;
    } finally {
      // Settled means "we looked", not "a file exists". Leaving this false
      // when a previous picture fetch failed made a perfectly valid cached
      // card disappear after the next app restart until the next refresh.
      _imageSettled = true;
    }
  }

  /// Refreshes hourly after success; manual refresh can revalidate sooner.
  /// A due automatic check gets one retry, then a 30-minute cool-off across launches
  /// and foreground resumes.
  ///
  /// Never throws and never reports: a card that could not be fetched is
  /// indistinguishable from no card, which is the whole design. Resolves to
  /// whether the cached card changed — a new one kept, or an ended one
  /// forgotten — so a caller redraws only when there is something to draw.
  Future<bool> refresh({bool force = false, bool manual = false}) {
    final active = _refreshing;
    if (active != null) return active;

    final work = _refresh(
      force: force,
      manual: manual,
    ).catchError((Object _) => false);
    _refreshing = work;
    return work.whenComplete(() {
      if (identical(_refreshing, work)) _refreshing = null;
    });
  }

  Future<bool> _refresh({required bool force, required bool manual}) async {
    if (!force) {
      final now = _now();
      // A time stamped in the future means the clock was moved back since —
      // a phone once set to the wrong year. Treated as long ago rather than
      // as recent, or the card would wait out the wrong year to refresh.
      bool within(DateTime? at, Duration window) =>
          at != null && !now.isBefore(at) && now.difference(at) < window;
      if (!manual && within(preferences.sponsorFetchedAt, refreshInterval)) {
        final sponsor = cached;
        if (sponsor?.image != null &&
            _image == null &&
            _imageSettled &&
            !within(preferences.sponsorAttemptedAt, failedRefreshCooldown)) {
          return _retryCachedImage(sponsor!);
        }
        return false;
      }
      if (within(preferences.sponsorAttemptedAt, failedRefreshCooldown)) {
        return false;
      }
    }

    await preferences.setSponsorAttemptedAt(_now());
    final client = _client ?? http.Client();
    final attempts = manual ? 1 : automaticAttempts;
    try {
      for (var attempt = 0; attempt < attempts; attempt++) {
        try {
          final response = await _get(
            client,
            endpoint,
            const Duration(seconds: 10),
            maxBytes,
          );

          // Only "not found" ends a campaign. Anything else that is not a
          // card — a 403 or 5xx from the host, a filtering page served with
          // 200 in place of the file, a body far too large — says nothing
          // about the campaign. The cache stands while this batch retries.
          if (response.statusCode == 404 || response.statusCode == 410) {
            await _forget();
            await preferences.setSponsorFetchedAt(_now());
            return true;
          }

          final raw = response.bodyBytes.length <= maxBytes
              ? decodeBody(response.bodyBytes)
              : null;
          final body = response.statusCode == 200 && raw != null
              ? choose(
                  raw,
                  languageCode:
                      preferences.locale?.languageCode ??
                      (PlatformDispatcher.instance.locale.languageCode == 'fa'
                          ? 'fa'
                          : 'en'),
                )
              : null;
          // A list with nothing for this phone today is a campaign with
          // nothing to show, the same as a file that is not there.
          if (body != null && body.isEmpty) {
            await _forget();
            await preferences.setSponsorFetchedAt(_now());
            return true;
          }
          final sponsor = body == null ? null : NexSponsor.parse(body);
          if (sponsor != null) {
            // The picture first, then the card. A picture that cannot be had
            // no longer takes the whole card down with it; the card is shown
            // in words instead and the image gets another chance tomorrow.
            final previous = cached;
            final kept = await _cacheImage(sponsor, client);
            if (sponsor.image != null && !kept) {
              final stillUsable =
                  previous?.id == sponsor.id &&
                  previous?.image == sponsor.image &&
                  _image != null &&
                  await _image!.exists();
              if (!stillUsable) await _dropImage();
            }
            _imageSettled = true;
            await preferences.setSponsorPayload(body!);
            await preferences.setSponsorFetchedAt(_now());
            return true;
          }
        } catch (_) {
          // Timeout, DNS, filtering and other transient failures use the same
          // tiny retry budget. The last good cache is untouched.
        }
      }
      return false;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Retry only a missing picture after the shorter failure cool-off. A
  /// readable manifest must not postpone image recovery for a whole day.
  Future<bool> _retryCachedImage(NexSponsor sponsor) async {
    await preferences.setSponsorAttemptedAt(_now());
    final client = _client ?? http.Client();
    try {
      final kept = await _cacheImage(sponsor, client);
      _imageSettled = true;
      return kept;
    } catch (_) {
      return false;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Takes the card and its picture off the device.
  Future<void> _dropImage() async {
    final path = preferences.sponsorImagePath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Left for the next successful fetch to overwrite.
      }
    }
    await preferences.setSponsorImagePath(null);
    _image = null;
  }

  Future<void> _forget() async {
    await preferences.setSponsorPayload(null);
    final path = preferences.sponsorImagePath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A file we cannot delete is a few hundred kilobytes, not a bug
        // worth surfacing. It is overwritten by the next card anyway.
      }
    }
    await preferences.setSponsorImagePath(null);
    _image = null;
  }

  /// Fetches the picture and keeps it beside the payload, or answers false.
  ///
  /// Content-addressed files avoid Flutter's stale file-image cache. The old
  /// picture goes only after its replacement is safely on disk.
  Future<bool> _cacheImage(NexSponsor sponsor, http.Client client) async {
    final url = sponsor.image;
    if (url == null) {
      await _dropImage();
      return true;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    try {
      final response = await _get(
        client,
        url,
        const Duration(seconds: 15),
        maxImageBytes,
      );
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.length > maxImageBytes ||
          !_looksLikeImage(bytes)) {
        return false;
      }
      final dir = await getApplicationSupportDirectory();
      // Named after its contents. It used to be one fixed name, overwritten
      // in place — and Flutter's image cache keys a file picture by its path,
      // so a new picture at the old path kept drawing the old one until the
      // app was restarted. A new picture is a new path; the old file goes.
      final digest = sha256.convert(bytes).toString().substring(0, 16);
      final file = File(p.join(dir.path, 'sponsor_image_$digest'));
      if (!await file.exists()) {
        // Written to one side and renamed, the same way the widget snapshot
        // is: the card reads this file whenever it likes, and half a picture
        // must never be the thing it finds.
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
      }
      final previous = preferences.sponsorImagePath;
      await preferences.setSponsorImagePath(file.path);
      _image = file;
      if (previous != null && previous != file.path) {
        try {
          await File(previous).delete();
        } catch (_) {
          // Already gone, or held open by the old frame for a moment.
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF') {
      return ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    }
    for (final magic in _imageMagic) {
      if (bytes.length < magic.length) continue;
      var matches = true;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  Future<void> dismiss(String id) =>
      preferences.dismissSponsor(id, at: _now(), keepFor: dismissalCoolOff);
}
