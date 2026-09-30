import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/disclosure_log.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_dialog.dart';

/// "What left this device" (W3.2): every request Nex made to an AI provider,
/// newest first — which provider, what it was for, what kind of content went
/// with it and from which notes. Kept on the phone only, and clearable.
class DisclosuresScreen extends StatefulWidget {
  const DisclosuresScreen({super.key, required this.services});

  final NexServices services;

  @override
  State<DisclosuresScreen> createState() => _DisclosuresScreenState();
}

class _DisclosuresScreenState extends State<DisclosuresScreen> {
  List<DisclosureEntry>? _entries;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final entries = await NexDisclosureLog.read();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.disclosuresClear),
        content: NexDialogBody(child: Text(l10n.disclosuresClearBody)),
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
            child: Text(l10n.disclosuresClear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NexDisclosureLog.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.disclosuresTitle),
        actions: [
          if (entries != null && entries.isNotEmpty)
            IconButton(
              tooltip: l10n.disclosuresClear,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => unawaited(_clear()),
            ),
        ],
      ),
      body: entries == null
          ? const SizedBox.shrink()
          : ListView(
              padding: EdgeInsets.only(
                top: NexSpacing.sm,
                bottom: NexSpacing.lg + nexBottomInset(context),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.lg,
                    NexSpacing.sm,
                    NexSpacing.lg,
                    NexSpacing.md,
                  ),
                  child: Text(
                    l10n.disclosuresIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(NexSpacing.xl),
                    child: Text(
                      l10n.disclosuresEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                for (final entry in entries)
                  _EntryTile(entry: entry, services: widget.services),
              ],
            ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.services});

  final DisclosureEntry entry;
  final NexServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final when = nexDisplayDate(
      entry.at,
      solar: services.solarCalendar,
      persian: Localizations.localeOf(context).languageCode == 'fa',
      time: true,
    );
    final what = [
      for (final kind in DisclosureContent.values)
        if (entry.content.contains(kind)) contentLabel(l10n, kind),
    ].join(Localizations.localeOf(context).languageCode == 'fa' ? '، ' : ', ');
    final details = [
      '${entry.provider} · ${entry.host}',
      '$what · ${nexFormatBytes(entry.bytes)}',
      if (entry.noteIds.isNotEmpty)
        l10n.disclosuresFromNotes(entry.noteIds.length),
      ?entry.media,
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
      leading: Icon(_icon(entry.purpose)),
      title: Text(purposeLabel(l10n, entry.purpose)),
      subtitle: Text('$when\n${details.join('\n')}'),
      isThreeLine: true,
      onTap: entry.noteIds.isEmpty
          ? null
          : () => unawaited(_showNotes(context)),
    );
  }

  Future<void> _showNotes(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final notes = <Note>[];
    for (final id in entry.noteIds) {
      try {
        final note = await services.getById(id);
        if (note != null) notes.add(note);
      } catch (_) {}
    }
    if (!context.mounted) return;
    await nexShowSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NexSpacing.lg),
          children: [
            Text(
              l10n.disclosuresFromNotes(entry.noteIds.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: NexSpacing.sm),
            for (final note in notes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _preview(note),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (notes.length < entry.noteIds.length)
              Text(
                l10n.disclosuresNotesGone(entry.noteIds.length - notes.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  static String _preview(Note note) {
    final text = (note.content ?? '').trim();
    if (text.isNotEmpty) return text.split('\n').first;
    final uri = note.mediaUri;
    return uri == null ? note.type.name : uri.split(RegExp(r'[/\\]')).last;
  }

  static IconData _icon(DisclosurePurpose purpose) => switch (purpose) {
    DisclosurePurpose.chat => Icons.chat_bubble_outline,
    DisclosurePurpose.tags => Icons.sell_outlined,
    DisclosurePurpose.summary => Icons.short_text,
    DisclosurePurpose.dailySummary => Icons.wb_twilight_outlined,
    DisclosurePurpose.greeting => Icons.waving_hand_outlined,
    DisclosurePurpose.translation => Icons.translate,
    DisclosurePurpose.rewrite => Icons.edit_note,
    DisclosurePurpose.transcription => Icons.mic_none,
    DisclosurePurpose.photoText => Icons.document_scanner_outlined,
    DisclosurePurpose.searchIndex => Icons.manage_search,
    DisclosurePurpose.connectionTest => Icons.wifi_tethering,
    DisclosurePurpose.other => Icons.cloud_upload_outlined,
  };

  static String purposeLabel(AppLocalizations l10n, DisclosurePurpose p) =>
      switch (p) {
        DisclosurePurpose.chat => l10n.disclosureChat,
        DisclosurePurpose.tags => l10n.disclosureTags,
        DisclosurePurpose.summary => l10n.disclosureSummary,
        DisclosurePurpose.dailySummary => l10n.disclosureDailySummary,
        DisclosurePurpose.greeting => l10n.disclosureGreeting,
        DisclosurePurpose.translation => l10n.disclosureTranslation,
        DisclosurePurpose.rewrite => l10n.disclosureRewrite,
        DisclosurePurpose.transcription => l10n.disclosureTranscription,
        DisclosurePurpose.photoText => l10n.disclosurePhotoText,
        DisclosurePurpose.searchIndex => l10n.disclosureSearchIndex,
        DisclosurePurpose.connectionTest => l10n.disclosureConnectionTest,
        DisclosurePurpose.other => l10n.disclosureOther,
      };

  static String contentLabel(AppLocalizations l10n, DisclosureContent c) =>
      switch (c) {
        DisclosureContent.text => l10n.disclosureText,
        DisclosureContent.fileText => l10n.disclosureFileText,
        DisclosureContent.image => l10n.disclosureImage,
        DisclosureContent.audio => l10n.disclosureAudio,
      };
}
