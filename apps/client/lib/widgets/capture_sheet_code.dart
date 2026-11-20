part of 'capture_sheet.dart';

extension _CaptureCode on _CaptureSheetState {
  /// The note's content for the words in the box.
  ///
  /// A snippet has to travel as Markdown — one fenced block with its
  /// language on the opening fence — because that is what every other note
  /// surface already reads, exports and searches. Everything that writes or
  /// journals goes through here, so the database and the crash journal never
  /// disagree about whether the fence is there.
  String _wireContent(String text) {
    if (_kind != CaptureKind.code || text.trim().isEmpty) return text;
    return NexCodeSnippet(code: text, language: _codeLanguage).markdown;
  }

  void _selectLanguage(NexCodeLanguage language) {
    if (_closing || language == _codeLanguage) return;
    if (widget.preferences.haptics) unawaited(HapticFeedback.selectionClick());
    _set(() => _codeLanguage = language);
    // The journal is what a relaunch recovers from; it has to carry the
    // language too, or a snippet recovered after a crash reopens in the
    // language it had before the picker moved.
    try {
      widget.services.captureJournal.writeSoon(
        _draftId,
        _wireContent(controller.text),
      );
    } catch (_) {}
    if (controller.text.trim().isNotEmpty) unawaited(flush());
  }

  Widget _languagePicker(
    BuildContext context,
    AppLocalizations l10n,
    CaptureKind shown,
  ) => AnimatedSize(
    duration: NexMotion.of(context, NexMotion.morph),
    curve: NexMotion.moveCurve,
    alignment: Alignment.topCenter,
    child: shown == CaptureKind.code
        ? Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.sm,
              top: NexSpacing.xs,
            ),
            child: Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.codeLanguage,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                NexCodeLanguageButton(
                  key: const ValueKey('capture-code-language'),
                  language: _codeLanguage,
                  enabled: !_closing,
                  onSelected: _selectLanguage,
                ),
              ],
            ),
          )
        : const SizedBox(width: double.infinity),
  );
}
