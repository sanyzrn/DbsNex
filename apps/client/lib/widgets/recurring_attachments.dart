import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/export_cache.dart';
import '../platform/nex_services.dart';
import '../platform/vault_store.dart';
import '../screens/camera_sheet.dart';
import '../screens/note_detail_sheet.dart';
import '../screens/vault_screen.dart';
import 'feature_label.dart';
import 'nex_banner.dart';
import 'nex_dialog.dart';
import 'photo_viewer.dart';

/// What a Recurring item carries with it: receipts and related notes, and
/// optionally one bank card from the private vault (W5.4).
///
/// Receipts belong to the item, not the library. They were ordinary photo
/// notes once, so every receipt also landed on the timeline, and deleting it
/// there took it off the item too. Now each is a file of the item's own in
/// `recurring/` under the media folder — inside what a full backup copies,
/// and out of the reach of the media sweep, which only ever looks at the
/// folder's top level — kept on the item by its path relative to that
/// folder, so a backup restored on another phone still finds it. Linked
/// notes stay references to notes, as before. Only those paths, note ids and
/// a vault id are kept on the item. A linked card is shown only
/// after the vault's own unlock, and nothing about it is ever part of what
/// the assistant or the brief can read — the item's details never are.
class RecurringAttachments extends StatefulWidget {
  const RecurringAttachments({
    super.key,
    required this.services,
    required this.details,
    required this.onChanged,
  });

  final NexServices services;
  final Map<String, dynamic> details;
  final ValueChanged<Map<String, dynamic>> onChanged;

  static List<String> noteIdsOf(Map<String, dynamic> details) =>
      (details['notes'] as List? ?? const []).whereType<String>().toList();

  static String? vaultCardOf(Map<String, dynamic> details) =>
      details['vaultCardId'] as String?;

  /// The item's receipt photos, as paths relative to the media folder.
  static List<String> receiptsOf(Map<String, dynamic> details) =>
      (details['receipts'] as List? ?? const []).whereType<String>().toList();

  /// Where the receipts live, under the media folder.
  static const receiptFolder = 'recurring';

  @override
  State<RecurringAttachments> createState() => _RecurringAttachmentsState();
}

class _RecurringAttachmentsState extends State<RecurringAttachments> {
  Map<String, Note> _notes = const {};

  List<String> get _ids => RecurringAttachments.noteIdsOf(widget.details);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final found = <String, Note>{};
    for (final id in _ids) {
      final note = await widget.services.getById(id);
      if (note != null) found[id] = note;
    }
    if (mounted) setState(() => _notes = found);
  }

  @override
  void didUpdateWidget(RecurringAttachments old) {
    super.didUpdateWidget(old);
    final before = RecurringAttachments.noteIdsOf(old.details);
    if (before.join(',') != _ids.join(',')) unawaited(_load());
  }

  void _setNotes(List<String> ids) =>
      widget.onChanged({...widget.details, 'notes': ids});

  Future<void> _addReceipt() async {
    final source = await nexShowSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(nexLabel(context, 'Camera', 'دوربین')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(nexLabel(context, 'Gallery', 'گالری')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      // Nex's own camera, as on the timeline.
      final taking = source == ImageSource.camera
          ? nexTakePhoto(context)
          : ImagePicker().pickImage(source: source);
      final picked = await taking;
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      // The camera's or the picker's own copy, now that it is read.
      unawaited(
        getTemporaryDirectory().then(
          (cache) => discardPickedCopy(picked.path, cache),
        ),
      );
      final extension = p.extension(picked.path).isEmpty
          ? '.jpg'
          : p.extension(picked.path);
      final relative = p.join(
        RecurringAttachments.receiptFolder,
        'receipt-${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      final dest = File(p.join(widget.services.mediaDir, relative));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(bytes, flush: true);
      widget.onChanged({
        ...widget.details,
        'receipts': [
          ...RecurringAttachments.receiptsOf(widget.details),
          relative,
        ],
      });
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: nexLabel(
            context,
            'The photo could not be added.',
            'عکس اضافه نشد.',
          ),
        );
      }
    }
  }

  Future<void> _linkNote() async {
    final note = await nexShowSheet<Note>(
      context: context,
      builder: (_) => _NoteSearch(services: widget.services),
    );
    if (note == null || _ids.contains(note.id)) return;
    _setNotes([..._ids, note.id]);
  }

  Future<void> _open(Note note) async {
    await nexShowSheet<DetailResult>(
      context: context,
      builder: (_) =>
          NoteDetailSheet(services: widget.services, noteId: note.id),
    );
    if (mounted) await _load();
  }

  Future<void> _pickCard() async {
    final id = await Navigator.push<String>(
      context,
      NexPageRoute<String>(
        builder: (_) => const VaultScreen(kind: VaultKind.card, picking: true),
      ),
    );
    if (id == null) return;
    widget.onChanged({...widget.details, 'vaultCardId': id});
  }

  Future<void> _openCard(String id) => Navigator.push<void>(
    context,
    NexPageRoute<void>(
      builder: (_) => VaultScreen(kind: VaultKind.card, focusId: id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = RecurringAttachments.vaultCardOf(widget.details);
    final receipts = RecurringAttachments.receiptsOf(widget.details);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          nexLabel(context, 'Attachments', 'پیوست‌ها'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: NexSpacing.xs),
        // Receipts as the pictures they are: tap to look, × to take one off
        // the item. Taken off, the file goes with the next media sweep.
        if (receipts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.xs),
            child: Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.sm,
              children: [
                for (final relative in receipts)
                  _ReceiptThumb(
                    key: ValueKey('receipt-$relative'),
                    path: p.join(widget.services.mediaDir, relative),
                    onRemove: () => widget.onChanged({
                      ...widget.details,
                      'receipts': [
                        for (final other in receipts)
                          if (other != relative) other,
                      ],
                    }),
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: NexSpacing.xs,
          runSpacing: NexSpacing.xs,
          children: [
            for (final id in _ids)
              if (_notes[id] case final note?)
                InputChip(
                  avatar: Icon(nexNoteTypeIcon(note.type.wireName), size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      _label(note),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onPressed: () => unawaited(_open(note)),
                  onDeleted: () =>
                      _setNotes([..._ids.where((other) => other != id)]),
                ),
            if (card != null)
              InputChip(
                avatar: const Icon(Icons.lock_outline, size: 16),
                label: Text(
                  nexLabel(context, 'Linked bank card', 'کارت بانکی پیوست‌شده'),
                ),
                tooltip: nexLabel(
                  context,
                  'Opens after unlocking the vault',
                  'پس از بازکردن قفل خزانه باز می‌شود',
                ),
                onPressed: () => unawaited(_openCard(card)),
                onDeleted: () => widget.onChanged(
                  Map.of(widget.details)..remove('vaultCardId'),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: NexSpacing.xs,
          children: [
            TextButton.icon(
              onPressed: () => unawaited(_addReceipt()),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(nexLabel(context, 'Receipt photo', 'عکس رسید')),
            ),
            TextButton.icon(
              onPressed: () => unawaited(_linkNote()),
              icon: const Icon(Icons.link),
              label: Text(nexLabel(context, 'Link a note', 'پیوند یادداشت')),
            ),
            if (card == null)
              TextButton.icon(
                onPressed: () => unawaited(_pickCard()),
                icon: const Icon(Icons.credit_card),
                label: Text(nexLabel(context, 'Bank card', 'کارت بانکی')),
              ),
          ],
        ),
      ],
    );
  }

  static String _label(Note note) {
    for (final source in [
      note.title,
      note.content,
      note.caption,
      note.ocrText,
      note.transcriptText,
    ]) {
      final line = (source ?? '')
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
      if (line.isNotEmpty) return line;
    }
    return note.type.wireName;
  }
}

/// A search field and what it finds; tapping a note picks it.
class _NoteSearch extends StatefulWidget {
  const _NoteSearch({required this.services});

  final NexServices services;

  @override
  State<_NoteSearch> createState() => _NoteSearchState();
}

class _NoteSearchState extends State<_NoteSearch> {
  final _query = TextEditingController();
  List<Note> _found = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _query.text.trim();
    final found = text.isEmpty
        ? await widget.services.timeline(limit: 20)
        : await widget.services.search(SearchFilters(query: text));
    if (mounted) setState(() => _found = found.take(30).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        MediaQuery.viewInsetsOf(context).bottom + NexSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexAutoDirection(
            controller: _query,
            builder: (context, direction) => TextField(
              controller: _query,
              textDirection: direction,
              textAlign: TextAlign.start,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: nexLabel(context, 'Find a note', 'جست‌وجوی یادداشت'),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 250),
                  () => unawaited(_run()),
                );
              },
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final note in _found)
                  ListTile(
                    leading: Icon(nexNoteTypeIcon(note.type.wireName)),
                    title: Text(
                      _RecurringAttachmentsState._label(note),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, note),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One receipt: a rounded thumbnail that opens full screen, with a small ×.
class _ReceiptThumb extends StatelessWidget {
  const _ReceiptThumb({super.key, required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(NexRadius.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  NexPageRoute<void>(
                    builder: (_) => NexPhotoViewer.file(path),
                    swipeBackEnabled: false,
                  ),
                ),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: 216,
                  semanticLabel: nexLabel(context, 'Receipt', 'رسید'),
                  errorBuilder: (_, _, _) => Icon(
                    Icons.receipt_long_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: -6,
            end: -6,
            child: Material(
              color: scheme.surface,
              shape: const CircleBorder(),
              elevation: 1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    semanticLabel: nexLabel(context, 'Remove', 'برداشتن'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
