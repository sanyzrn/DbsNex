import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  });

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

  /// Language codes this card is for, empty meaning everyone. A sponsor
  /// writing in Persian has no business appearing for an English reader.
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
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether this card belongs on screen right now.
  ///
  /// Pure, and separate from the fetch, because every one of these rules is a
  /// way to show somebody the wrong thing and none of them needs a network to
  /// be tested.
  bool visibleAt({
    required DateTime now,
    required String languageCode,
    required Set<String> dismissed,
  }) {
    if (dismissed.contains(id)) return false;
    if (starts != null && now.isBefore(starts!)) return false;
    if (ends != null && !now.isBefore(ends!)) return false;
    if (locales.isNotEmpty && !locales.contains(languageCode.toLowerCase())) {
      return false;
    }
    return true;
  }
}

/// Fetches [NexSponsor] and remembers the answer.
///
/// On the same daily cadence as the update check and for the same reason: the
/// thing being asked about changes at most daily, and an app that phones home
/// on every launch is one that costs battery to learn nothing.
///
/// The cache is what makes the card appear instantly rather than a second
/// after the timeline draws. A card that pops in under the reader's thumb is
/// worse than no card.
class NexSponsorService {
  NexSponsorService({
    required this.preferences,
    http.Client? client,
    this.endpoint = defaultEndpoint,
    DateTime Function()? now,
  }) : _client = client,
       _now = now ?? DateTime.now;

  /// Beside the releases, on the host that already serves them.
  ///
  /// No new infrastructure and no new trust boundary: this is the same
  /// repository the updater reads, so a build that can be updated can already
  /// reach it. Publishing a card is committing a file; taking it down is
  /// deleting one, and a 404 is the "nothing to show" case working exactly as
  /// intended.
  static const defaultEndpoint =
      'https://raw.githubusercontent.com/sanyzrn/DbsNex-releases/main/banner.json';

  static const refreshInterval = Duration(hours: 24);

  /// How stale the last *successful* fetch may be before the card stops
  /// appearing.
  ///
  /// This is what "nothing while offline" means in an app with no
  /// connectivity plugin and no wish for one. A phone that cannot reach the
  /// host stops refreshing, the last answer ages out, and the card goes —
  /// rather than a campaign that ended last month sitting in somebody's
  /// timeline because their data has been off since then.
  ///
  /// Twice the refresh interval, so one missed check is not enough to lose a
  /// card that is still running.
  static const maxAge = Duration(hours: 48);

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
    [0x89, 0x50, 0x4E, 0x47], // PNG
    [0x47, 0x49, 0x46, 0x38], // GIF87a / GIF89a, animated included
    [0x52, 0x49, 0x46, 0x46], // RIFF — WebP, still or animated
    [0x42, 0x4D], // BMP
  ];

  /// A card is a couple of hundred bytes. Anything much larger is not the
  /// file this expects, and reading it into memory to find that out is the
  /// mistake this avoids.
  static const maxBytes = 16 * 1024;

  final NexPreferences preferences;
  final String endpoint;
  final http.Client? _client;
  final DateTime Function() _now;

  /// Where the cached picture lives, once one has been kept. Null before the
  /// first successful fetch of a card that has one.
  File? _image;

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
    return at != null && _now().difference(at) < maxAge;
  }

  /// The card to draw, or null. The only method the timeline needs.
  NexSponsor? visible({required String languageCode}) {
    // Stale is the same as absent. See [maxAge].
    if (!_fresh) return null;
    final sponsor = cached;
    if (sponsor == null) return null;
    // A card that asked for a picture and has none is not a card. Better an
    // empty space than a banner with a hole where its design was.
    if (sponsor.image != null && _image == null) return null;
    return sponsor.visibleAt(
          now: _now(),
          languageCode: languageCode,
          dismissed: preferences.sponsorDismissed,
        )
        ? sponsor
        : null;
  }

  /// Points [image] at a picture already on disk from a previous run.
  ///
  /// Called once when the timeline starts, before the network is asked,
  /// so a card that was fetched yesterday draws on the first frame today.
  Future<void> restoreCachedImage() async {
    final path = preferences.sponsorImagePath;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) _image = file;
  }

  /// Refreshes at most once a day. Never throws, and never reports: a card
  /// that could not be fetched is indistinguishable from no card, which is
  /// the whole design.
  Future<void> refresh({bool force = false}) async {
    if (!force) {
      final last = preferences.sponsorFetchedAt;
      if (last != null && _now().difference(last) < refreshInterval) return;
    }
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 10));
      final sponsor = response.statusCode == 200 &&
              response.bodyBytes.length <= maxBytes
          ? NexSponsor.parse(response.body)
          : null;
      if (sponsor != null) {
        // The picture first. A card whose image cannot be had is not shown
        // at all, so writing the payload before knowing would leave the
        // timeline briefly certain of a card it cannot draw.
        final kept = await _cacheImage(sponsor, client);
        if (sponsor.image != null && !kept) {
          await _forget();
          return;
        }
        await preferences.setSponsorPayload(response.body);
      } else {
        // A 404 is the ordinary way a campaign ends. Clearing rather than
        // keeping the last one is the difference between "taken down" and
        // "runs forever once published".
        await _forget();
      }
      await preferences.setSponsorFetchedAt(_now());
    } catch (_) {
      // Offline, blocked, timed out, or a proxy serving something else. The
      // cache stands, and the timestamp is deliberately *not* written, so the
      // next launch tries again rather than waiting a day.
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Takes the card and its picture off the device.
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
  /// One file, always the same name, replaced in place: a card is one at a
  /// time, so there is nothing to garbage-collect and no way for a
  /// campaign's leftovers to accumulate on somebody's phone.
  Future<bool> _cacheImage(NexSponsor sponsor, http.Client client) async {
    final url = sponsor.image;
    if (url == null) {
      await preferences.setSponsorImagePath(null);
      _image = null;
      return true;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.length > maxImageBytes ||
          !_looksLikeImage(bytes)) {
        return false;
      }
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'sponsor_image'));
      // Written to one side and renamed, the same way the widget snapshot
      // is: the card reads this file whenever it likes, and half a picture
      // must never be the thing it finds.
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      await preferences.setSponsorImagePath(file.path);
      _image = file;
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeImage(Uint8List bytes) {
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
      preferences.setSponsorDismissed({...preferences.sponsorDismissed, id});
}
