import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';

/// The formatting half of a text field's own selection menu.
///
/// Bold, italic and the rest arrive where a phone already puts Cut and Copy —
/// the floating menu that appears over a selection — rather than on a toolbar
/// nailed above the keyboard. That is where the platform teaches people to
/// look for things done *to a selection*, and it costs the capture sheet no
/// vertical space, which matters in a sheet whose whole point is a text field
/// and nothing else.
///
/// The buttons are appended to the platform's own, never substituted for them:
/// `contextMenuButtonItems` is whatever this field would have offered anyway,
/// so Cut, Copy, Paste, Select all and Look Up all survive, and Android's
/// overflow (⋮) paginates the result on its own.
///
/// [host] is the surface the field lives on, not the menu. The menu's own
/// context dies with the menu, and asking for a link's address outlives it.
EditableTextContextMenuBuilder nexFormatContextMenuBuilder(BuildContext host) {
  return (BuildContext context, EditableTextState state) {
    final l10n = AppLocalizations.of(context);
    final items = <ContextMenuButtonItem>[...state.contextMenuButtonItems];
    final selection = state.textEditingValue.selection;

    // Everything here acts on a selection. With nothing selected the menu is
    // the platform's own — offering "Bold" for a caret would be offering to
    // embolden nothing.
    if (selection.isValid && !selection.isCollapsed) {
      void write(NexFormattedText result) {
        state.userUpdateTextEditingValue(
          TextEditingValue(
            text: result.text,
            selection: TextSelection(
              baseOffset: result.start,
              extentOffset: result.end,
            ),
          ),
          SelectionChangedCause.toolbar,
        );
      }

      void apply(NexFormattedText Function(String, int, int) edit) {
        final value = state.textEditingValue;
        final where = value.selection;
        write(edit(value.text, where.start, where.end));
        state.hideToolbar();
      }

      items.addAll(<ContextMenuButtonItem>[
        for (final format in NexInlineFormat.values)
          ContextMenuButtonItem(
            label: _labelFor(l10n, format),
            onPressed: () => apply(
              (text, start, end) =>
                  NexTextFormatting.toggleInline(text, start, end, format),
            ),
          ),
        ContextMenuButtonItem(
          label: l10n.formatQuote,
          onPressed: () => apply(NexTextFormatting.toggleQuote),
        ),
        ContextMenuButtonItem(
          label: l10n.formatLink,
          onPressed: () async {
            // Read the selection before the dialog, not after: opening one
            // takes the focus off the field, and where the selection is by
            // the time an answer comes back is not this code's business.
            final value = state.textEditingValue;
            final where = value.selection;
            state.hideToolbar();
            final url = await _askForUrl(host);
            if (url == null || url.isEmpty || !state.mounted) return;
            write(
              NexTextFormatting.link(value.text, where.start, where.end, url),
            );
          },
        ),
        ContextMenuButtonItem(
          label: l10n.formatClear,
          onPressed: () => apply(NexTextFormatting.clear),
        ),
      ]);
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  };
}

String _labelFor(AppLocalizations l10n, NexInlineFormat format) =>
    switch (format) {
      NexInlineFormat.bold => l10n.formatBold,
      NexInlineFormat.italic => l10n.formatItalic,
      NexInlineFormat.mono => l10n.formatMono,
      NexInlineFormat.strikethrough => l10n.formatStrikethrough,
    };

/// Asks where a link should point. Null when the question was dismissed.
Future<String?> _askForUrl(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final answer = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.addLink),
      content: NexDialogBody(
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          // A URL is left to right in every language, including in an
          // interface that is not.
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: l10n.linkAddress),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  controller.dispose();
  return answer?.trim();
}
