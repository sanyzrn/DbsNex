import 'commitment.dart';
import 'note.dart';

/// A bounded local projection for notification planning, never an AI input.
class NexNudgeSnapshot {
  const NexNudgeSnapshot({
    required this.notes,
    required this.commitments,
    required this.hasData,
    this.revision = '',
  });
  final List<Note> notes;
  final List<NexCommitment> commitments;
  final bool hasData;
  final String revision;
}
