import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// What a request to an AI provider was for.
enum DisclosurePurpose {
  chat,
  tags,
  summary,
  dailySummary,
  greeting,
  translation,
  rewrite,
  transcription,
  photoText,
  searchIndex,
  connectionTest,
  other,
}

/// What kind of content a request carried.
enum DisclosureContent { text, fileText, image, audio }

/// One request that left the device (W3.2).
class DisclosureEntry {
  const DisclosureEntry({
    required this.at,
    required this.provider,
    required this.host,
    required this.purpose,
    required this.content,
    required this.bytes,
    this.noteIds = const [],
    this.media,
  });

  final DateTime at;

  /// The provider's name as Settings shows it.
  final String provider;

  /// Where it went: the host only, never the path, key or query.
  final String host;
  final DisclosurePurpose purpose;
  final Set<DisclosureContent> content;

  /// The size of the request body, as sent.
  final int bytes;

  /// The notes it came from, when the caller knew them.
  final List<String> noteIds;

  /// The file name of a photo or recording that was sent, when one was.
  final String? media;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'provider': provider,
    'host': host,
    'purpose': purpose.name,
    'content': [for (final c in content) c.name],
    'bytes': bytes,
    if (noteIds.isNotEmpty) 'notes': noteIds,
    if (media != null) 'media': media,
  };

  static DisclosureEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return DisclosureEntry(
      at: at.toLocal(),
      provider: '${json['provider'] ?? ''}',
      host: '${json['host'] ?? ''}',
      purpose:
          DisclosurePurpose.values.asNameMap()['${json['purpose']}'] ??
          DisclosurePurpose.other,
      content: {
        for (final name in (json['content'] as List?) ?? const [])
          ?DisclosureContent.values.asNameMap()['$name'],
      },
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      noteIds: [for (final id in (json['notes'] as List?) ?? const []) '$id'],
      media: json['media'] as String?,
    );
  }
}

/// The local record of what left this device for an AI provider (W3.2).
///
/// Written by [DisclosureClient], which every cloud request goes through, in
/// whichever isolate made it — the app's for the assistant, the database
/// worker's for tags, summaries, transcripts and the search index. Each
/// isolate [configure]s the same file beside the library; lines are appended
/// whole, so the two never interleave. Readable and clearable in Settings,
/// never uploaded, and not part of any backup.
///
/// Callers that know more than the request does — which notes a question was
/// asked about, what a request is for — say so with [about], which travels
/// with the request through the zone it runs in.
abstract final class NexDisclosureLog {
  static const fileName = 'disclosures.jsonl';

  /// Kept to the newest entries; older lines are dropped on read.
  static const keep = 1000;

  static String? _path;

  /// Where this isolate records. Without it nothing is recorded — which is
  /// what tests and the local model get.
  static void configure(String libraryDir) =>
      _path = p.join(libraryDir, fileName);

  static const _purposeKey = #nexDisclosurePurpose;
  static const _notesKey = #nexDisclosureNotes;
  static const _contentKey = #nexDisclosureContent;
  static const _mediaKey = #nexDisclosureMedia;

  /// Runs [body] with what its requests are about. Nested calls add to the
  /// notes and content of the outer one; the innermost purpose wins.
  static Future<T> about<T>(
    Future<T> Function() body, {
    DisclosurePurpose? purpose,
    Iterable<String> notes = const [],
    Set<DisclosureContent> content = const {},
    String? media,
  }) => runZoned(
    body,
    zoneValues: {
      _purposeKey: purpose ?? Zone.current[_purposeKey],
      _notesKey: {...?Zone.current[_notesKey] as Set<String>?, ...notes},
      _contentKey: {
        ...?Zone.current[_contentKey] as Set<DisclosureContent>?,
        ...content,
      },
      _mediaKey: media ?? Zone.current[_mediaKey],
    },
  );

  /// Records one request. Never throws: a log that cannot be written must not
  /// cost anyone their answer.
  static void record({
    required String provider,
    required Uri url,
    required int bytes,
    Set<DisclosureContent> content = const {},
  }) {
    final path = _path;
    if (path == null) return;
    final entry = DisclosureEntry(
      at: DateTime.now(),
      provider: provider,
      host: url.host,
      purpose:
          Zone.current[_purposeKey] as DisclosurePurpose? ??
          DisclosurePurpose.other,
      content: {
        ...content,
        ...?Zone.current[_contentKey] as Set<DisclosureContent>?,
      },
      bytes: bytes,
      noteIds: [...?Zone.current[_notesKey] as Set<String>?],
      media: Zone.current[_mediaKey] as String?,
    );
    try {
      File(path).writeAsStringSync(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  /// Newest first. Trims the file to [keep] entries as it goes.
  static Future<List<DisclosureEntry>> read() async {
    final path = _path;
    if (path == null) return const [];
    final file = File(path);
    if (!file.existsSync()) return const [];
    final lines = (await file.readAsLines())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length > keep + keep ~/ 5) {
      final kept = lines.sublist(lines.length - keep);
      await file.writeAsString('${kept.join('\n')}\n', flush: true);
      lines
        ..clear()
        ..addAll(kept);
    }
    final entries = <DisclosureEntry>[];
    for (final line in lines.reversed) {
      try {
        final entry = DisclosureEntry.fromJson(jsonDecode(line));
        if (entry != null) entries.add(entry);
      } catch (_) {
        // A line cut short by a crash mid-write; the rest still reads.
      }
    }
    return entries;
  }

  static Future<void> clear() async {
    final path = _path;
    if (path == null) return;
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}

/// An HTTP client that records every request it sends in [NexDisclosureLog].
///
/// Wraps the client every [CloudAIAdapter] talks through, so nothing can
/// reach a provider without being written down.
class DisclosureClient extends http.BaseClient {
  DisclosureClient(this._inner, {required this.provider});

  final http.Client _inner;
  final String provider;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final content = <DisclosureContent>{DisclosureContent.text};
    var bytes = request.contentLength ?? 0;
    if (request is http.Request) {
      bytes = request.bodyBytes.length;
      try {
        if (_carriesImage(request.body)) content.add(DisclosureContent.image);
      } on FormatException {
        // Not text at all; what it was for still gets recorded.
      }
    } else if (request is http.MultipartRequest) {
      for (final file in request.files) {
        final type = file.contentType.mimeType;
        if (type.startsWith('audio/') ||
            (file.filename ?? '').contains(
              RegExp(r'\.(m4a|aac|mp3|wav|ogg|opus|webm)$'),
            )) {
          content.add(DisclosureContent.audio);
        } else if (type.startsWith('image/')) {
          content.add(DisclosureContent.image);
        } else {
          content.add(DisclosureContent.fileText);
        }
      }
      content.remove(DisclosureContent.text);
      bytes = request.contentLength;
    }
    NexDisclosureLog.record(
      provider: provider,
      url: request.url,
      bytes: bytes,
      content: content,
    );
    return _inner.send(request);
  }

  /// Inline media in any of the three wire formats.
  static bool _carriesImage(String body) =>
      body.contains('"image_url"') ||
      body.contains('"inline_data"') ||
      body.contains('"inlineData"') ||
      body.contains('"type":"image"');

  @override
  void close() => _inner.close();
}
