part of '../note_detail_sheet.dart';

/// **Details**: what is worth knowing about a note that its sheet does not
/// already show.
///
/// It used to repeat the dates — the top of the sheet already says when a
/// note was made — and close with **Cancel**, as if something were being
/// called off. Now each line answers a question someone might actually
/// have: how long ago, whether it has changed since, how long it is, how
/// much of a list is done, how much room it takes on the phone with its
/// attachments, when it was pinned and when it will remind. Lines that have
/// nothing to say are left out, and it closes with **Close**.
extension _DetailFacts on _NoteDetailSheetState {
  Future<void> _showDetails() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final persian = l10n.localeName == 'fa';
    String digits(Object value) => nexDigits('$value', persian: persian);
    String ago(DateTime at) {
      final span = DateTime.now().difference(at);
      if (span.inMinutes < 1) return l10n.timeNow;
      return l10n.detailsAgo(nexRelativeSpan(l10n, span));
    }

    final facts = <_Fact>[
      _Fact(
        icon: Icons.category_outlined,
        label: l10n.noteType(note.type.wireName),
      ),
      _Fact(
        icon: Icons.add_circle_outline,
        label: l10n.created,
        value: _formatWhen(note.createdAt, seconds: true),
        aside: ago(note.createdAt),
      ),
      if (note.updatedAt.difference(note.createdAt).inMinutes < 1)
        _Fact(icon: Icons.edit_outlined, label: l10n.detailsNotEdited)
      else
        _Fact(
          icon: Icons.edit_outlined,
          label: l10n.detailsEdited,
          value: _formatWhen(note.updatedAt, seconds: true),
          aside: ago(note.updatedAt),
        ),
      ..._contentFacts(note, l10n, digits),
      ?_storageFact(note, l10n, digits),
      if (note.pinnedAt case final pinned?)
        _Fact(
          icon: Icons.push_pin_outlined,
          label: l10n.detailsPinned,
          value: _formatWhen(pinned),
        ),
      if (note.dueAt case final due?)
        _Fact(
          icon: Icons.notifications_none,
          label: l10n.detailsReminder,
          value: _formatWhen(due),
        ),
      if (note.tags.isNotEmpty)
        _Fact(
          icon: Icons.sell_outlined,
          label: l10n.tags,
          value: note.tags.map((t) => t.name).join(persian ? '، ' : ', '),
        ),
    ];

    await nexShowDialog<void>(
      context: context,
      builder: (dialog) => NexAlertDialog(
        title: Text(l10n.details),
        content: NexDialogBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final fact in facts) _FactRow(fact: fact)],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('details-close'),
            onPressed: () => Navigator.pop(dialog),
            child: Text(l10n.closeLabel),
          ),
        ],
      ),
    );
  }

  /// How long it is, or how far along: what the kind of note has to say
  /// about itself.
  List<_Fact> _contentFacts(
    Note note,
    AppLocalizations l10n,
    String Function(Object) digits,
  ) {
    switch (note.type) {
      case NoteType.checklist:
        final items = note.checklistItems;
        if (items.isEmpty) return const [];
        return [
          _Fact(
            icon: Icons.checklist,
            label: l10n.detailsProgress,
            value: l10n.detailsChecklist(
              digits(items.where((item) => item.done).length),
              digits(items.length),
            ),
          ),
        ];
      case NoteType.voice:
        final ms = note.durationMs;
        if (ms == null || ms <= 0) return const [];
        final seconds = (ms / 1000).round();
        final clock =
            '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
        return [
          _Fact(
            icon: Icons.timer_outlined,
            label: l10n.detailsDuration,
            value: digits(clock),
          ),
        ];
      case NoteType.link:
        final host = Uri.tryParse(note.content?.trim() ?? '')?.host ?? '';
        if (host.isEmpty) return const [];
        return [
          _Fact(
            icon: Icons.public,
            label: l10n.detailsAddress,
            value: host.startsWith('www.') ? host.substring(4) : host,
          ),
        ];
      case NoteType.file:
        final uri = note.mediaUri;
        final name = note.title ?? (uri == null ? null : p.basename(uri));
        if (name == null || name.isEmpty) return const [];
        return [
          _Fact(
            icon: Icons.insert_drive_file_outlined,
            label: l10n.detailsFile,
            value: name,
          ),
        ];
      default:
        final text = (note.content ?? note.caption ?? '').trim();
        if (text.isEmpty) return const [];
        final words = text.split(RegExp(r'\s+')).length;
        return [
          _Fact(
            icon: Icons.notes,
            label: l10n.detailsLength,
            value: l10n.detailsWords(digits(words), digits(text.runes.length)),
            // Only where it helps: a short note is read before this line is.
            aside: words >= 150
                ? l10n.detailsReading(digits((words / 200).ceil()))
                : null,
          ),
        ];
    }
  }

  /// The room it takes on this phone: its own file and every attachment.
  _Fact? _storageFact(
    Note note,
    AppLocalizations l10n,
    String Function(Object) digits,
  ) {
    int sizeOf(String? uri) {
      if (uri == null) return 0;
      final file = File(uri);
      return file.existsSync() ? file.lengthSync() : 0;
    }

    final own = sizeOf(note.mediaUri);
    final attached = _attachments.fold<int>(
      0,
      (sum, attachment) => sum + sizeOf(attachment.mediaUri),
    );
    if (own + attached == 0) return null;
    final size = digits(nexFormatBytes(own + attached));
    return _Fact(
      icon: Icons.sd_storage_outlined,
      label: l10n.detailsOnPhone,
      value: _attachments.isEmpty
          ? size
          : l10n.detailsWithAttached(size, digits(_attachments.length)),
    );
  }

  String _formatWhen(DateTime value, {bool seconds = false}) => nexDisplayDate(
    value,
    solar: widget.services.solarCalendar,
    persian: Localizations.localeOf(context).languageCode == 'fa',
    time: true,
    seconds: seconds,
  );
}

class _Fact {
  const _Fact({
    required this.icon,
    required this.label,
    this.value,
    this.aside,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// A quieter second line: how long ago, how long to read.
  final String? aside;
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final _Fact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = fact.value;
    final aside = fact.aside;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(fact.icon, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: NexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.label,
                  style: value == null
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                ),
                if (value != null) ...[
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.bodyMedium),
                ],
                if (aside != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    aside,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
