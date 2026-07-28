/// Typed decodes of the sync API's two responses.
///
/// Every field here used to be read inline with `as T?` and `?? const []`,
/// which is why five separate protocol changes went unnoticed for as long as
/// they did: the server renamed `server_time` to `cursor`, renamed `merged_ids`
/// to `merged`, and added `tag_remap` and `has_more`, and each break degraded
/// into a plausible-looking null or empty list instead of an error. Reading a
/// contract defensively does not make the contract safer; it makes a broken one
/// indistinguishable from an empty one.
///
/// So: required fields are read with `as T` and a missing one throws. The right
/// failure for "the server is not speaking the protocol we think it is" is a
/// loud one.
library;

class SyncProtocolError extends StateError {
  SyncProtocolError(super.message);
}

/// One note the server accepted, and the revision it gave it.
typedef MergedNote = ({String id, int rev});

/// One local tag id the server folded into a different, canonical one.
typedef TagRemapEntry = ({String clientId, String canonicalId});

class PushResponse {
  const PushResponse({
    required this.merged,
    required this.mediaDeduped,
    required this.tagRemap,
  });

  factory PushResponse.fromJson(Map<String, dynamic> json) {
    final merged = json['merged'];
    if (merged is! List) {
      throw SyncProtocolError(
        'sync push: response has no "merged" list — the client cannot tell '
        'which writes were accepted',
      );
    }
    return PushResponse(
      merged: [
        for (final entry in merged)
          if (entry is Map)
            (id: entry['id'] as String, rev: (entry['rev'] as num).toInt()),
      ],
      mediaDeduped: [
        for (final hash in (json['media_deduped'] as List? ?? const []))
          hash as String,
      ],
      tagRemap: [
        for (final entry in (json['tag_remap'] as List? ?? const []))
          if (entry is Map)
            (
              clientId: entry['client_id'] as String,
              canonicalId: entry['canonical_id'] as String,
            ),
      ],
    );
  }

  /// The writes the server took. Anything absent was rejected as stale and
  /// must stay in the outbox.
  final List<MergedNote> merged;
  final List<String> mediaDeduped;
  final List<TagRemapEntry> tagRemap;

  Set<String> get acceptedIds => {for (final m in merged) m.id};
}

class PullPage {
  const PullPage({
    required this.notes,
    required this.tags,
    required this.cursor,
    required this.hasMore,
  });

  factory PullPage.fromJson(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    if (cursor is! String) {
      throw SyncProtocolError(
        'sync pull: response carries no cursor — without one every pull '
        'restarts from zero and re-downloads the whole corpus',
      );
    }
    return PullPage(
      notes: (json['notes'] as List).cast<Map<String, dynamic>>(),
      tags: (json['tags'] as List).cast<Map<String, dynamic>>(),
      cursor: cursor,
      hasMore: json['has_more'] == true,
    );
  }

  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> tags;

  /// The sequence value to ask from next time. Opaque to the client.
  final String cursor;

  /// Whether the server truncated this page.
  final bool hasMore;
}
