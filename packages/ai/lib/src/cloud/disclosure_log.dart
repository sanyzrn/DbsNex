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
  var _requests = 0;
  var _retiring = false;
  var _closed = false;
  Timer? _retireLimit;

  /// Stop accepting new work; existing response bodies may finish normally.
  void retire() {
    if (_retiring || _closed) return;
    _retiring = true;
    if (_requests == 0) {
      close();
    } else {
      // A body that never finishes must not retain a retired socket forever.
      _retireLimit = Timer(const Duration(minutes: 4), close);
    }
  }

  void _finished() {
    _requests--;
    if (_retiring && _requests == 0) close();
  }

  Stream<List<int>> _body(Stream<List<int>> source) async* {
    try {
      yield* source;
    } finally {
      _finished();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_retiring || _closed) {
      throw http.ClientException(
        'This AI connection has been closed.',
        request.url,
      );
    }
    final content = <DisclosureContent>{DisclosureContent.text};
    var bytes = request.contentLength ?? 0;
    if (request is http.Request) {
      bytes = request.bodyBytes.length;
      try {
        content.addAll(_mediaContent(request.body));
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
    _requests++;
    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (_) {
      _finished();
      rethrow;
    }
    return http.StreamedResponse(
      _body(response.stream),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Inspect serialized MIME metadata without decoding/copying base64 media.
  static Set<DisclosureContent> _mediaContent(String body) {
    final found = <DisclosureContent>{};
    if (body.contains('"image_url"') ||
        RegExp(r'"type"\s*:\s*"image"').hasMatch(body)) {
      found.add(DisclosureContent.image);
    }
    for (final match in RegExp(
      r'"(?:mime_type|mimeType)"\s*:\s*"(audio|image)/',
    ).allMatches(body)) {
      found.add(
        match[1] == 'audio' ? DisclosureContent.audio : DisclosureContent.image,
      );
    }
    return found;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _retireLimit?.cancel();
    _inner.close();
  }
}
