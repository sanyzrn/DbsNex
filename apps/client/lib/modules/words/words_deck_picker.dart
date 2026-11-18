/// Choosing, making, renaming and removing a deck. One sheet does all of
/// it, from the word page, the paste sheet and the home page, so a deck is
/// never created in one place and unreachable in another.
///
/// A deck that is removed takes nothing with it: its words go back to «no
/// deck», with their review history untouched (docs/18, rule 5).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_decks.dart';
import 'words_fields.dart';
import 'words_models.dart';
import 'words_store.dart';
import 'words_strings.dart';

/// The deck a word is in, as one row on the word's page: what it is now,
/// and the way to change it.
class WordsDeckField extends StatelessWidget {
  const WordsDeckField({
    super.key,
    required this.repository,
    required this.deckId,
    required this.onChanged,
  });

  final WordsRepository repository;

  /// The deck's id, or empty for «no deck».
  final String deckId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<List<WordsDeck>>(
      future: repository.loadDecks(),
      builder: (context, snapshot) {
        final decks = snapshot.data ?? const <WordsDeck>[];
        final name = wordsDeckName(decks, deckId);
        return InkWell(
          key: const ValueKey('words-deck-field'),
          borderRadius: BorderRadius.circular(NexRadius.md),
          onTap: () => unawaited(
            showWordsDeckPicker(
              context,
              repository,
              selectedId: deckId,
              onPicked: onChanged,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wordsStrings(context, 'deckLabel'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        name ?? wordsStrings(context, 'deckNone'),
                        key: const ValueKey('words-deck-name'),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Opens the deck sheet. [onPicked] is called with the chosen deck's id
/// (empty for «no deck») when the person chooses one.
Future<void> showWordsDeckPicker(
  BuildContext context,
  WordsRepository repository, {
  required String selectedId,
  required ValueChanged<String> onPicked,
}) => nexShowSheet<void>(
  context: context,
  builder: (_) => _DeckPickerSheet(
    repository: repository,
    selectedId: selectedId,
    onPicked: onPicked,
  ),
);

class _DeckPickerSheet extends StatefulWidget {
  const _DeckPickerSheet({
    required this.repository,
    required this.selectedId,
    required this.onPicked,
  });

  final WordsRepository repository;
  final String selectedId;
  final ValueChanged<String> onPicked;

  @override
  State<_DeckPickerSheet> createState() => _DeckPickerSheetState();
}

class _DeckPickerSheetState extends State<_DeckPickerSheet> {
  List<WordsDeck>? _decks;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final decks = await widget.repository.loadDecks();
      if (mounted) setState(() => _decks = decks);
    } catch (_) {
      if (mounted) setState(() => _decks = const []);
    }
  }

  void _failed() {
    if (mounted) {
      nexShowBanner(
        context,
        message: wordsStrings(context, 'saveFailed'),
        kind: NexBannerKind.failed,
      );
    }
  }

  void _pick(String id) {
    widget.onPicked(id);
    Navigator.pop(context);
  }

  Future<String?> _askName({required String title, String initial = ''}) =>
      nexShowDialog<String>(
        context: context,
        builder: (_) => _DeckNameDialog(title: title, initial: initial),
      );

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final name = await _askName(title: wordsStrings(context, 'newDeck'));
      if (!mounted) return;
      final clean = foldWhitespace(name ?? '');
      if (clean.isEmpty) return;
      final deck = await widget.repository.createDeck(clean);
      if (!mounted) return;
      if (deck == null) {
        _failed();
        return;
      }
      _pick(deck.id);
    } catch (_) {
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(WordsDeck deck) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final name = await _askName(
        title: wordsStrings(context, 'deckRename'),
        initial: deck.name,
      );
      if (!mounted || name == null) return;
      final clean = foldWhitespace(name);
      if (clean.isEmpty || clean == deck.name) return;
      if (!await widget.repository.renameDeck(deck.id, clean)) {
        _failed();
        return;
      }
      await _load();
    } catch (_) {
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(WordsDeck deck) async {
    if (_busy) return;
    final confirmed = await nexShowDialog<bool>(
      context: context,
      builder: (ctx) => NexAlertDialog(
        title: Text(wordsStrings(ctx, 'deckDeleteTitle')),
        content: NexDialogBody(
          child: Text(wordsStrings(ctx, 'deckDeleteBody', {'name': deck.name})),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          TextButton(
            key: const ValueKey('words-deck-delete-confirm'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx).delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (!await widget.repository.deleteDeck(deck.id)) {
        _failed();
        return;
      }
      if (widget.selectedId == deck.id) widget.onPicked('');
      await _load();
    } catch (_) {
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final decks = _decks;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(NexSpacing.md),
        children: [
          Text(
            strings(context, 'decksTitle'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: NexSpacing.sm),
          if (decks == null)
            const Padding(
              padding: EdgeInsets.all(NexSpacing.md),
              child: Center(child: NexInlineSpinner()),
            )
          else ...[
            ListTile(
              key: const ValueKey('words-deck-new'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(strings(context, 'newDeck')),
              onTap: _busy ? null : () => unawaited(_create()),
            ),
            if (decks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(NexSpacing.sm),
                child: Text(
                  strings(context, 'deckEmpty'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ListTile(
              key: const ValueKey('words-deck-none'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(strings(context, 'deckNone')),
              trailing: widget.selectedId.isEmpty
                  ? const Icon(Icons.check_rounded)
                  : null,
              selected: widget.selectedId.isEmpty,
              onTap: _busy ? null : () => _pick(''),
            ),
            for (final deck in decks)
              ListTile(
                key: ValueKey('words-deck-${deck.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(deck.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.selectedId == deck.id)
                      const Icon(Icons.check_rounded),
                    NexPopupMenuButton<String>(
                      tooltip: strings(context, 'deckActions'),
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) => unawaited(
                        value == 'rename' ? _rename(deck) : _delete(deck),
                      ),
                      itemBuilder: (_) => [
                        nexMenuItem(
                          value: 'rename',
                          icon: Icons.edit_outlined,
                          label: strings(context, 'deckRename'),
                        ),
                        nexMenuItem(
                          value: 'delete',
                          icon: Icons.delete_outline,
                          destructive: true,
                          label: AppLocalizations.of(context).delete,
                        ),
                      ],
                    ),
                  ],
                ),
                selected: widget.selectedId == deck.id,
                onTap: _busy ? null : () => _pick(deck.id),
              ),
          ],
        ],
      ),
    );
  }
}

/// One line of text for a deck's name; nothing is saved until the button.
class _DeckNameDialog extends StatefulWidget {
  const _DeckNameDialog({required this.title, this.initial = ''});

  final String title;
  final String initial;

  @override
  State<_DeckNameDialog> createState() => _DeckNameDialogState();
}

class _DeckNameDialogState extends State<_DeckNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    return NexAlertDialog(
      title: Text(widget.title),
      content: NexDialogBody(
        child: WordsAutoField(
          fieldKey: const ValueKey('words-deck-name-field'),
          controller: _controller,
          label: strings(context, 'deckNameLabel'),
          hint: strings(context, 'deckNameHint'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        TextButton(
          key: const ValueKey('words-deck-name-save'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(AppLocalizations.of(context).save),
        ),
      ],
    );
  }
}
