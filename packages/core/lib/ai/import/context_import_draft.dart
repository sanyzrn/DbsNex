import '../../models/memory_record.dart';

/// One candidate fact/preference/habit found while parsing a pasted-in reply
/// from another AI, awaiting the user's review (09-ai.md — Phase 3+ cross-AI
/// context import).
///
/// Deliberately just a data shape: the parsing step that produces these
/// drafts depends on which model ends up doing the structuring, which is
/// Phase 3+ work. Nothing is written to [MemoryRepository] until the user
/// reviews a draft and it becomes [accepted] — importing is opt-in per item,
/// never a bulk silent write.
class ImportedMemoryDraft {
  ImportedMemoryDraft({
    required this.suggestedKind,
    this.suggestedKey,
    required this.valueText,
    this.accepted = false,
  });

  final MemoryKind suggestedKind;
  final String? suggestedKey;
  final String valueText;

  /// Set once the user has reviewed and approved this draft for writing.
  bool accepted;
}
