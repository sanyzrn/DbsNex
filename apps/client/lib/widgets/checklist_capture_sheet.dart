import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import 'nex_dialog.dart';

/// Capturing a checklist: one text field, one item per line.
///
/// Not a list of rows with an "add item" button. Nex's capture surface is a
/// field you type into and leave, and a checklist is the one note type where
/// that is *also* the fastest way to write one — five things to buy is five
/// lines and one Enter each, where five rows is five taps into five fields.
/// The rows appear afterwards, on the card and in the detail sheet, where
/// ticking them is what you came back for.
///
/// Enter always breaks a line here, whatever the Enter-submits preference is
/// set to: this is the one capture where a newline is the whole point.
class ChecklistCaptureSheet extends StatefulWidget {
  const ChecklistCaptureSheet({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<ChecklistCaptureSheet> createState() => _ChecklistCaptureSheetState();
}

class _ChecklistCaptureSheetState extends State<ChecklistCaptureSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<ChecklistItem> get _items => parseChecklist(_text.text);

  void _submit() {
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    Navigator.pop(context, _items);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = _items.length;
    return NexSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                nexNoteTypeIcon('checklist'),
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(l10n.checklist, style: theme.textTheme.titleMedium),
              ),
              if (count > 0)
                Text(
                  l10n.noteCount(count),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: TextField(
              controller: _text,
              autofocus: true,
              maxLines: null,
              // Never TextInputAction.send, whatever the capture preference
              // says — see the class comment.
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: l10n.checklistHint,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              // Disabled rather than hidden while empty: the button is where
              // the eye already is, and a control that vanishes is worse to
              // find again than one that is visibly not ready yet.
              onPressed: count == 0 ? null : _submit,
              icon: const Icon(Icons.arrow_upward, size: 18),
              label: Text(l10n.capture),
            ),
          ),
        ],
      ),
    );
  }
}

/// Capturing a link: one field, and a preview of what will be saved.
///
/// The preview is the whole reason this is not just a text capture. A pasted
/// link arrives with tracking parameters, a scheme or no scheme, sometimes
/// wrapped in brackets by whatever sent it — showing the host that Nex read
/// out of it is how someone knows, before committing, that this is going to
/// be the bookmark they meant.
class LinkCaptureSheet extends StatefulWidget {
  const LinkCaptureSheet({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<LinkCaptureSheet> createState() => _LinkCaptureSheetState();
}

class _LinkCaptureSheetState extends State<LinkCaptureSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    // Most link captures are a paste, so the clipboard is offered rather than
    // waited for. It is a suggestion in the field, not a commit: nothing is
    // saved until the button is pressed.
    _offerClipboard();
  }

  Future<void> _offerClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final url = normaliseUrl(data?.text ?? '');
    if (url == null || !mounted || _text.text.isNotEmpty) return;
    _text.text = url;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final typed = _text.text.trim();
    final url = normaliseUrl(typed);
    final host = urlHost(url);
    return NexSheetBody(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                nexNoteTypeIcon('link'),
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: NexSpacing.sm),
              Text(l10n.link, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          TextField(
            controller: _text,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (url != null) Navigator.pop(context, url);
            },
            decoration: InputDecoration(
              hintText: l10n.linkHint,
              border: InputBorder.none,
              // Only once there is something to be wrong about: an error
              // under an empty field is telling someone off for not having
              // started yet.
              errorText: typed.isNotEmpty && url == null
                  ? l10n.linkNotValid
                  : null,
            ),
          ),
          if (host != null) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              host,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: NexSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: url == null
                  ? null
                  : () {
                      if (widget.preferences.haptics) {
                        HapticFeedback.selectionClick();
                      }
                      Navigator.pop(context, url);
                    },
              icon: const Icon(Icons.arrow_upward, size: 18),
              label: Text(l10n.capture),
            ),
          ),
        ],
      ),
    );
  }
}
