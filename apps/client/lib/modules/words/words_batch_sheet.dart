import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'words_fields.dart';
import 'words_models.dart';
import 'words_store.dart';
import 'words_strings.dart';
import 'words_batch_parse.dart';
import 'form_draft.dart';
import 'draft_guard.dart';

Future<void> showWordsBatchSheet(
  BuildContext context,
  WordsRepository repository, {
  required Future<void> Function() onDone,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => _WordsBatchSheet(repository: repository, onDone: onDone),
);

class _WordsBatchSheet extends StatefulWidget {
  const _WordsBatchSheet({required this.repository, required this.onDone});
  final WordsRepository repository;
  final Future<void> Function() onDone;
  @override
  State<_WordsBatchSheet> createState() => _WordsBatchSheetState();
}

class _WordsBatchSheetState extends State<_WordsBatchSheet> {
  final _text = TextEditingController();
  final _language = TextEditingController(text: 'English');
  late final FormDraft _draft;
  bool _adding = false;
  bool _restoring = true;
  bool _draftLoadFailed = false;
  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _draft = FormDraft(widget.repository.store, 'batch:new', const {}, {
      'text': _text,
      'language': _language,
    }, () => const {});
    unawaited(_restore(initial: true));
  }

  Future<void> _restore({bool initial = false}) async {
    if (_restoring && !initial) return;
    setState(() => _restoring = true);
    final body = await _draft.load();
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _restoring = false;
        _draftLoadFailed = true;
      });
      return;
    }
    if (body != null) _draft.apply(body);
    _draft.resume();
    setState(() {
      _restoring = false;
      _draftLoadFailed = false;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _draft.close();
    _text.removeListener(_changed);
    _text.dispose();
    _language.dispose();
    super.dispose();
  }

  void _error() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wordsStrings(context, 'saveFailed'))),
      );
    }
  }

  Future<void> _add() async {
    final parsed = parseWordsBatch(_text.text);
    if (_adding ||
        _restoring ||
        parsed.entries.isEmpty ||
        parsed.entries.length > 200) {
      return;
    }
    final entries = List.of(parsed.entries);
    final language = foldWhitespace(_language.text);
    setState(() => _adding = true);
    try {
      final existing = await widget.repository.loadCards();
      final known = existing
          .where(
            (c) =>
                foldWhitespace(c.language).toLowerCase() ==
                language.toLowerCase(),
          )
          .map((c) => foldWhitespace(c.headword).toLowerCase())
          .toSet();
      var added = 0;
      var skipped = parsed.duplicates;
      final pending = <WordsBatchLine>[];
      for (final line in entries) {
        if (known.contains(line.word.toLowerCase())) {
          skipped++;
          continue;
        }
        final card = await widget.repository.newCard(
          headword: line.word,
          language: language,
          meaning: line.meaning,
        );
        if (await widget.repository.saveCard(card)) {
          added++;
          known.add(line.word.toLowerCase());
        } else {
          pending.add(line);
        }
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (pending.isNotEmpty) {
        _text.text = [
          for (final line in pending)
            line.meaning.isEmpty ? line.word : '${line.word}\t${line.meaning}',
        ].join('\n');
        _draft.changed();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              wordsStrings(context, 'batchPartial', {
                'added': added,
                'remaining': pending.length,
              }),
            ),
          ),
        );
        return;
      }
      await _draft.clear();
      if (!mounted) return;
      final message = [
        wordsStrings(context, 'batchAdded', {'count': added}),
        if (skipped > 0)
          wordsStrings(context, 'batchSkipped', {'count': skipped}),
      ].join(' · ');
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(message)));
      await widget.onDone();
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _cancel() async {
    if (_adding || _restoring) return;
    setState(() => _adding = true);
    if (!await _draft.clear()) {
      if (!_draftLoadFailed) _draft.resume();
      _error();
      if (mounted) setState(() => _adding = false);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _preview(List<WordsBatchLine> entries) => nexShowSheet<void>(
    context: context,
    builder: (ctx) => ListView(
      padding: const EdgeInsets.all(NexSpacing.md),
      children: [
        Text(
          wordsStrings(ctx, 'batchPreview', {'count': entries.length}),
          style: Theme.of(ctx).textTheme.titleLarge,
        ),
        for (final line in entries)
          ListTile(
            title: NexTextDirection(text: line.word, child: Text(line.word)),
            subtitle: line.meaning.isEmpty
                ? Text(wordsStrings(ctx, 'meaningNeeded'))
                : NexTextDirection(
                    text: line.meaning,
                    child: Text(line.meaning),
                  ),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final parsed = parseWordsBatch(_text.text);
    final lines = parsed.entries;
    return DraftGuard(
      draft: _draft,
      busy: () => _adding,
      child: AbsorbPointer(
        absorbing: _adding,
        child: _restoring
            ? const Padding(
                padding: EdgeInsets.all(NexSpacing.lg),
                child: NexInlineSpinner(),
              )
            : _draftLoadFailed
            ? NexEmptyState(
                icon: Icons.cloud_off_outlined,
                message: strings(context, 'draftLoadError'),
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => unawaited(_restore()),
                      child: Text(strings(context, 'retry')),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_cancel()),
                      child: Text(AppLocalizations.of(context).cancel),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(NexSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings(context, 'batchTitle'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      strings(context, 'batchFormat'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: NexSpacing.md),
                    WordsNoteField(
                      fieldKey: const ValueKey('words-batch-text'),
                      controller: _text,
                      label: strings(context, 'batchTextLabel'),
                      minLines: 4,
                      maxLines: 8,
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    WordsAutoField(
                      controller: _language,
                      label: strings(context, 'languageLabel'),
                      hint: strings(context, 'languageHint'),
                      fieldKey: const ValueKey('words-batch-language'),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    Text(
                      lines.isEmpty
                          ? strings(context, 'batchEmpty')
                          : strings(context, 'batchPreview', {
                              'count': lines.length,
                            }),
                      key: const ValueKey('words-batch-preview'),
                    ),
                    if (parsed.duplicates > 0)
                      Text(
                        strings(context, 'batchSkipped', {
                          'count': parsed.duplicates,
                        }),
                      ),
                    if (lines.isNotEmpty)
                      TextButton(
                        key: const ValueKey('words-batch-preview-all'),
                        onPressed: () => unawaited(_preview(lines)),
                        child: Text(strings(context, 'batchPreviewAll')),
                      ),
                    if (lines.length > 200)
                      Text(
                        strings(context, 'batchLimit'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (lines.isNotEmpty)
                      FilledButton.icon(
                        key: const ValueKey('words-batch-add'),
                        onPressed: _adding || lines.length > 200
                            ? null
                            : () => unawaited(_add()),
                        icon: const Icon(Icons.playlist_add),
                        label: Text(
                          strings(context, 'batchAdd', {'count': lines.length}),
                        ),
                      ),
                    TextButton(
                      key: const ValueKey('words-batch-cancel'),
                      onPressed: () => unawaited(_cancel()),
                      child: Text(AppLocalizations.of(context).cancel),
                    ),
                    Text(
                      strings(context, 'draftHint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: NexSpacing.sm),
                  ],
                ),
              ),
      ),
    );
  }
}
