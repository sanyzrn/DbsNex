import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

  /// A card is a couple of hundred bytes. Anything much larger is not the
  /// file this expects, and reading it into memory to find that out is the
  /// mistake this avoids.
  static const maxBytes = 16 * 1024;

  final NexPreferences preferences;
  final String endpoint;
  final http.Client? _client;
  final DateTime Function() _now;

  /// What was fetched last, whenever that was. Read synchronously so the
  /// first frame of the timeline already knows.
  NexSponsor? get cached {
    final raw = preferences.sponsorPayload;
    return raw == null || raw.isEmpty ? null : NexSponsor.parse(raw);
  }

  /// The card to draw, or null. The only method the timeline needs.
  NexSponsor? visible({required String languageCode}) {
    final sponsor = cached;
    if (sponsor == null) return null;
    return sponsor.visibleAt(
          now: _now(),
          languageCode: languageCode,
          dismissed: preferences.sponsorDismissed,
        )
        ? sponsor
        : null;
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
      if (response.statusCode == 200 &&
          response.bodyBytes.length <= maxBytes &&
          NexSponsor.parse(response.body) != null) {
        await preferences.setSponsorPayload(response.body);
      } else {
        // A 404 is the ordinary way a campaign ends. Clearing rather than
        // keeping the last one is the difference between "taken down" and
        // "runs forever once published".
        await preferences.setSponsorPayload(null);
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

  Future<void> dismiss(String id) =>
      preferences.setSponsorDismissed({...preferences.sponsorDismissed, id});
}
