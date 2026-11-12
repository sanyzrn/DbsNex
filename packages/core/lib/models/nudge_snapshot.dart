import 'commitment.dart';
import 'note.dart';

/// A bounded local projection for notification planning, never an AI input.
class NexNudgeSnapshot {
  const NexNudgeSnapshot({
    required this.notes,
    required this.commitments,
    required this.hasData,
    this.revision = '',
    this.memories = const [],
  });
  final List<Note> notes;
  final List<NexCommitment> commitments;
  final bool hasData;
  final String revision;

  /// Notes written around this time of year in earlier years, a few per day:
  /// what "on this day" is chosen from. Kept apart from [notes] because
  /// nothing here is due, urgent or unfinished — it is only old.
  final List<Note> memories;
}
