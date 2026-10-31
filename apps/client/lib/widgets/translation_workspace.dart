part of 'translate_sheet.dart';

/// Bounded, process-only checkpoint for one exact source. It owns no DB state.
class _TranslationWorkspace extends ChangeNotifier {
  _TranslationWorkspace(
    this.source,
    this.noteId,
    this.target, {
    required this.explicitTarget,
  }) : chunks = source.length > maxCharacters
           ? const []
           : NexTranslationChunk.split(source);

  static const maxCharacters = 100000;
  final String source;
  final String? noteId;
  final List<NexTranslationChunk> chunks;
  NexTranslationLanguage target;
  bool explicitTarget;
  List<String>? languages;
  bool detectionAttempted = false;
  bool loading = false;
  bool started = false;
  bool consent = false;
  bool cancelled = false;
  bool invalidated = false;
  bool suggestedTarget = false;
  Object? failure;
  final _outputs = <String, List<String>>{};
  List<String> get _parts => _outputs.putIfAbsent(target.code, () => []);
  int get completedChunks => _parts.length;
  bool get complete => chunks.isNotEmpty && completedChunks == chunks.length;
  bool get tooLarge => source.length > maxCharacters;
  bool get needsConsent => !consent && !cancelled && source.length >= 12000;
  String get result => [
    for (var i = 0; i < _parts.length; i++)
      '${chunks[i].prefix}${_parts[i]}${chunks[i].separator}',
  ].join();

  void choose(NexTranslationLanguage language) {
    if (loading) return;
    target = language;
    explicitTarget = true;
    suggestedTarget = false;
    failure = null;
    notifyListeners();
  }

  Future<void> run(
    NexPreferences preferences, {
    CloudAIAdapter? adapter,
  }) async {
    if (loading ||
        invalidated ||
        complete ||
        tooLarge ||
        needsConsent ||
        cancelled) {
      return;
    }
    loading = true;
    started = true;
    failure = null;
    notifyListeners();
    final client = adapter ?? CloudAIAdapter(config: preferences.aiProvider);
    try {
      await NexDisclosureLog.about(
        () async {
          if (!detectionAttempted) {
            languages = await client.detectTranslationLanguages(source);
            if (languages == null && client.lastFailureStatus != null) {
              failure = client.lastFailureKind;
              return;
            }
            detectionAttempted = true;
            if (!explicitTarget &&
                languages?.length == 1 &&
                languages!.single == target.code) {
              target = NexTranslationLanguage.fromCode(
                target.code == 'en' ? 'fa' : 'en',
              )!;
              suggestedTarget = true;
            }
            if (!invalidated) notifyListeners();
          }
          while (!invalidated && !complete) {
            final translated = await client.translateChunk(
              chunks[completedChunks].text,
              target: target,
            );
            if (invalidated) return;
            if (translated == null || translated.trim().isEmpty) {
              failure = client.lastFailureKind;
              return;
            }
            _parts.add(translated);
            notifyListeners();
          }
        },
        notes: [?noteId],
        purpose: DisclosurePurpose.translation,
      );
    } catch (error) {
      failure = error;
    } finally {
      client.close();
      loading = false;
      if (!invalidated) notifyListeners();
    }
  }
}
