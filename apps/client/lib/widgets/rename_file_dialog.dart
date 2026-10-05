import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';

/// Asks for a file note's new name, keeping its extension.
///
/// Only the part before the extension is editable, and the extension is
/// shown beside it: renaming `report.pdf` to `report` must not leave a file
/// nothing can open. A name the file system would refuse is explained under
/// the field, with Save disabled, rather than quietly rewritten. Returns the
/// whole new name, or null when cancelled or unchanged.
Future<String?> nexAskFileName(
  BuildContext context, {
  required String current,
}) => showDialog<String>(
  context: context,
  builder: (_) => _RenameFileDialog(current: current),
);

class _RenameFileDialog extends StatefulWidget {
  const _RenameFileDialog({required this.current});

  final String current;

  @override
  State<_RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<_RenameFileDialog> {
  late final String _extension = fileExtensionOf(widget.current);
  late final _controller = TextEditingController(
    text: fileBaseNameOf(widget.current),
  )..addListener(() => setState(() {}));

  FileNameProblem? get _problem =>
      checkFileBaseName(_controller.text, extension: _extension);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_problem != null) return;
    final name = '${_controller.text.trim()}$_extension';
    Navigator.pop(context, name == widget.current ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final problem = _problem;
    return AlertDialog(
      title: Text(l10n.renameFileTitle),
      content: NexDialogBody(
        child: NexAutoDirection(
          controller: _controller,
          builder: (context, direction) => TextField(
            key: const ValueKey('rename-file-field'),
            controller: _controller,
            textDirection: direction,
            autofocus: true,
            maxLength: nexMaxFileNameLength,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              counterText: '',
              suffixText: _extension.isEmpty ? null : _extension,
              errorText: switch (problem) {
                null => null,
                FileNameProblem.empty => l10n.fileNameEmpty,
                FileNameProblem.forbiddenCharacters => l10n.fileNameForbidden,
                FileNameProblem.tooLong => l10n.fileNameTooLong,
              },
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: problem == null ? _submit : null,
          child: Text(l10n.rename),
        ),
      ],
    );
  }
}
