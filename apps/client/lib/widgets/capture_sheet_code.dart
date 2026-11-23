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
    if (_closing) return;
    _codeLanguageChosen = true;
    if (language == _codeLanguage) return;
    if (widget.preferences.haptics) unawaited(HapticFeedback.selectionClick());
    _set(() {
      _codeLanguage = language;
      controller.language = language;
    });
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

  void _codeChanged(String text) {
    if (!_codeLanguageChosen &&
        _codeLanguage == NexCodeLanguage.plainText &&
        _latestText.trim().isEmpty &&
        text.length > 1) {
      if (nexSuggestCodeLanguage(text) case final language?) {
        _set(() {
          _codeLanguage = language;
          controller.language = language;
        });
      }
    }
    changed(text);
  }

  Widget _codeToolbar() => NexCodeToolbar(
    key: const ValueKey('capture-code-toolbar'),
    pickerKey: const ValueKey('capture-code-language'),
    language: _codeLanguage,
    controller: controller,
    focus: _fieldFocus,
    enabled: !_closing,
    onEdited: changed,
    onSelected: _selectLanguage,
  );
}

bool get _hardwareCodeModifier {
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isControlPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed;
}
