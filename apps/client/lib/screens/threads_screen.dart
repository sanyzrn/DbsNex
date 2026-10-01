import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/card_strings.dart';
import '../widgets/nex_dialog.dart';
import 'note_detail_sheet.dart';

/// Every thread, the most recently active first (W5.3).
///
/// Library → Threads. A thread is a view over notes, so this screen only
/// ever reads and names; the notes themselves stay on the timeline.
class ThreadsScreen extends StatefulWidget {
  const ThreadsScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  List<NoteThread>? _threads;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final threads = await widget.services.threads();
    if (mounted) setState(() => _threads = threads);
  }

  Future<void> _create() async {
    final name = await nexAskThreadName(context);
    if (name == null) return;
    await widget.services.createThread(name);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final threads = _threads;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.threads),
        actions: [
          IconButton(
            tooltip: l10n.threadNew,
            icon: const Icon(Icons.add),
            onPressed: () => unawaited(_create()),
          ),
        ],
      ),
      body: threads == null
          ? const SizedBox.shrink()
          : threads.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(NexSpacing.xl),
                child: Text(
                  l10n.threadsEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.only(
                top: NexSpacing.sm,
                bottom: NexSpacing.sm + nexBottomInset(context),
              ),
              children: [
                for (final thread in threads)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: NexSpacing.lg,
                    ),
                    leading: const Icon(Icons.timeline_outlined),
                    title: Text(
                      thread.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(l10n.threadNoteCount(thread.noteCount)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        NexPageRoute<void>(
                          builder: (_) => ThreadScreen(
                            services: widget.services,
                            preferences: widget.preferences,
                            thread: thread,
                          ),
                        ),
                      );
                      await _reload();
                    },
                  ),
              ],
            ),
    );
  }
}

/// One thread, read as a story: its notes oldest first.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.services,
    required this.thread,
    this.preferences,
  });

  final NexServices services;

  /// Handed on to the note's details; optional there too.
  final NexPreferences? preferences;
  final NoteThread thread;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  late String _name = widget.thread.name;
  List<Note>? _notes;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final notes = await widget.services.threadNotes(widget.thread.id);
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _open(Note note) async {
    await nexShowSheet<DetailResult>(
      context: context,
      builder: (_) => NoteDetailSheet(
        services: widget.services,
        preferences: widget.preferences,
        noteId: note.id,
      ),
    );
    await widget.services.refreshTimeline();
    await _reload();
  }

  Future<void> _act(String action) async {
    final l10n = AppLocalizations.of(context);
    if (action == 'rename') {
      final name = await nexAskThreadName(context, initial: _name);
      if (name == null) return;
      await widget.services.renameThread(widget.thread.id, name);
      if (mounted) setState(() => _name = name);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.threadDelete),
          content: NexDialogBody(child: Text(l10n.threadDeleteBody)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await widget.services.deleteThread(widget.thread.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notes = _notes;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) => unawaited(_act(action)),
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.threadRename)),
              PopupMenuItem(value: 'delete', child: Text(l10n.threadDelete)),
            ],
          ),
        ],
      ),
      body: notes == null
          ? const SizedBox.shrink()
          : notes.isEmpty
          ? Center(child: Text(l10n.threadEmpty))
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.sm,
                NexSpacing.md,
                NexSpacing.lg + nexBottomInset(context),
              ),
              itemCount: notes.length,
              separatorBuilder: (_, _) => const SizedBox(height: NexSpacing.sm),
              itemBuilder: (context, index) {
                final note = notes[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: NoteCard(
                        note: note,
                        strings: nexCardStrings(context),
                        onTap: () => unawaited(_open(note)),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.threadRemoveNote,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () async {
                        await widget.services.removeFromThread(
                          widget.thread.id,
                          note.id,
                        );
                        await _reload();
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// Asks for a thread's name; null when cancelled or left empty.
Future<String?> nexAskThreadName(
  BuildContext context, {
  String? initial,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: initial ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial == null ? l10n.threadNew : l10n.threadRename),
      content: NexDialogBody(
        child: NexAutoDirection(
          controller: controller,
          builder: (context, direction) => TextField(
            controller: controller,
            selectionWidthStyle: BoxWidthStyle.tight,
            autofocus: true,
            textDirection: direction,
            textAlign: TextAlign.start,
            decoration: InputDecoration(hintText: l10n.threadName),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(initial == null ? l10n.threadNew : l10n.threadRename),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// The threads a note is in, as a sheet of switches, with a way to start one.
///
/// From a note's details and its hold menu. Returns whether anything changed.
Future<bool> showThreadPicker(
  BuildContext context, {
  required NexServices services,
  required String noteId,
}) => showThreadPickerFor(context, services: services, noteIds: [noteId]);

/// The same picker for several notes at once, from the selection bar: a
/// thread is ticked when every one of them is in it, half-ticked when some
/// are, and a tick puts them all in or takes them all out.
Future<bool> showThreadPickerFor(
  BuildContext context, {
  required NexServices services,
  required List<String> noteIds,
}) async {
  final changed = await nexShowSheet<bool>(
    context: context,
    builder: (_) => _ThreadPicker(services: services, noteIds: noteIds),
  );
  return changed ?? false;
}

class _ThreadPicker extends StatefulWidget {
  const _ThreadPicker({required this.services, required this.noteIds});

  final NexServices services;
  final List<String> noteIds;

  @override
  State<_ThreadPicker> createState() => _ThreadPickerState();
}

class _ThreadPickerState extends State<_ThreadPicker> {
  List<NoteThread>? _all;

  /// How many of the notes each thread holds.
  Map<String, int> _in = const {};
  var _changed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await widget.services.threads();
    final counts = <String, int>{};
    for (final id in widget.noteIds) {
      for (final thread in await widget.services.threadsForNote(id)) {
        counts[thread.id] = (counts[thread.id] ?? 0) + 1;
      }
    }
    if (!mounted) return;
    setState(() {
      _all = all;
      _in = counts;
    });
  }

  bool? _ticked(NoteThread thread) {
    final count = _in[thread.id] ?? 0;
    if (count == 0) return false;
    return count == widget.noteIds.length ? true : null;
  }

  Future<void> _toggle(NoteThread thread, bool on) async {
    for (final id in widget.noteIds) {
      if (on) {
        await widget.services.addToThread(thread.id, id);
      } else {
        await widget.services.removeFromThread(thread.id, id);
      }
    }
    _changed = true;
    await _reload();
  }

  Future<void> _create() async {
    final name = await nexAskThreadName(context);
    if (name == null) return;
    await widget.services.createThread(name, noteIds: widget.noteIds);
    _changed = true;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = _all;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: NexSpacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              NexSpacing.sm,
              NexSpacing.lg,
              NexSpacing.sm,
            ),
            child: Text(
              l10n.threads,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (all != null)
            for (final thread in all)
              CheckboxListTile(
                value: _ticked(thread),
                tristate: widget.noteIds.length > 1,
                title: Text(
                  thread.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(l10n.threadNoteCount(thread.noteCount)),
                // Half-ticked goes to all in: the notes were picked together.
                onChanged: (_) =>
                    unawaited(_toggle(thread, _ticked(thread) != true)),
              ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l10n.threadNew),
            onTap: () => unawaited(_create()),
          ),
        ],
      ),
    );
  }
}
