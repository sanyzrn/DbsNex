/// The menu over a selection, with other people's apps left out of it.
///
/// Android lets any installed app register an `ACTION_PROCESS_TEXT` activity
/// and have its name appear on every selection menu on the phone, and Flutter
/// forwards all of them. On a device with a few assistants installed that
/// means Ask Copilot, Ask ChatGPT, Translate, Read aloud, Ask Grok and the
/// rest stacked above the commands that belong to this app — from apps that
/// have nothing to do with the note being read.
///
/// They are told apart by [ContextMenuButtonType.custom], which is the type
/// Flutter gives them and gives nothing else it generates itself. Filtering on
/// that stays correct as the platform's own list grows, where naming the ones
/// to keep would silently drop whatever Android adds next.
///
/// This rule lived in the client's formatting menu and so applied to exactly
/// the two surfaces that had a menu of their own: the capture sheet and the
/// note editor. Everything else took Flutter's default menu, which is how the
/// entries came back the moment text you only read became selectable. One
/// rule, in the package both halves of the app build on, is what keeps that
/// from happening a third time.
library;

import 'package:flutter/material.dart';

/// [items] without the entries other apps put there.
List<ContextMenuButtonItem> nexOwnMenuItems(List<ContextMenuButtonItem> items) {
  return [
    for (final item in items)
      if (item.type != ContextMenuButtonType.custom) item,
  ];
}

/// The selection menu for text that is only read — anything under a
/// [SelectionArea].
Widget nexSelectionMenu(BuildContext context, SelectableRegionState state) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: nexOwnMenuItems(state.contextMenuButtonItems),
  );
}

/// The same menu for a `SelectableText` or a read-only field, which report
/// their commands through an [EditableTextState] rather than a region.
Widget nexReadingMenu(BuildContext context, EditableTextState state) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: nexOwnMenuItems(state.contextMenuButtonItems),
  );
}
