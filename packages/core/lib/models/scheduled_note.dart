/// A note written now and delivered later.
///
/// Held aside until [releaseAt] — not a hidden note, a note that does not
/// exist yet — and then put on the timeline as an ordinary text note under
/// the same [id], so a notification that names the id opens the note it
/// announced.
class ScheduledNote {
  const ScheduledNote({
    required this.id,
    required this.content,
    required this.releaseAt,
    required this.writtenAt,
  });

  final String id;
  final String content;

  /// When it arrives, in UTC.
  final DateTime releaseAt;

  /// When it was written, in UTC.
  final DateTime writtenAt;
}
