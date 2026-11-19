part of 'note_card.dart';

const _timelineTextLines = 4;
const _timelineChecklistLines = 2;

String? _timelineCaption(Note note) {
  final caption = note.caption?.trim();
  return note.type == NoteType.text && caption != null && caption.isNotEmpty
      ? NexMarkdownText.preview(caption)
      : null;
}

String? _timelineTextTitle(Note note) {
  final title = note.title?.trim();
  return note.type == NoteType.text && title != null && title.isNotEmpty
      ? title
      : null;
}

String? _timelineFileCaption(Note note) {
  final caption = note.caption?.trim();
  return note.originalFilename?.trim().isNotEmpty == true &&
          caption != null &&
          caption.isNotEmpty
      ? caption
      : null;
}

/// Keeps the preview and caption separate and lets a short note use one line.
class _TimelineWords extends StatelessWidget {
  const _TimelineWords({
    required this.note,
    required this.strings,
    required this.maxLines,
    required this.caption,
    required this.captionLines,
  });

  final Note note;
  final NexCardStrings strings;
  final int maxLines;
  final String? caption;
  final int captionLines;

  @override
  Widget build(BuildContext context) {
    final style = NexCardDensity.of(context).previewStyle(Theme.of(context));
    final title = _timelineTextTitle(note);
    final filename = note.originalFilename?.trim();
    final file = filename != null && filename.isNotEmpty;
    final source = file
        ? filename
        : title != null
        ? note.content
        : note.displayText;
    final text = NexMarkdownText.preview(source ?? '').trim();
    final fileCaption = _timelineFileCaption(note);
    final secondary =
        caption ??
        (fileCaption == null || fileCaption == source
            ? null
            : NexMarkdownText.preview(fileCaption));
    return Column(
      key: const ValueKey('note-card-preview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          NexTextSurface.line(
            title,
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
        if (text.isNotEmpty)
          NexTextSurface(
            text,
            maxLines: maxLines - (title == null ? 0 : 1),
            style: style,
          )
        else if (title == null && secondary == null)
          NexTextSurface.line(strings.noteOfType(note.type.name), style: style),
        if (secondary != null) ...[
          if (title != null || text.isNotEmpty)
            const SizedBox(height: NexSpacing.xs),
          _CardCaption(text: secondary, maxLines: captionLines),
        ],
      ],
    );
  }
}

class _TimelineChecklistHeading extends StatelessWidget {
  const _TimelineChecklistHeading({required this.note, required this.strings});

  final Note note;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = note.checklistItems;
    final done = items.where((item) => item.done).length;
    final title = note.title?.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null && title.isNotEmpty)
          NexTextSurface.line(title, style: theme.textTheme.bodyLarge),
        Text(
          strings.checklistProgress?.call(done, items.length) ??
              '$done/${items.length}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

extension on _CardBody {
  Widget? _timelineChecklist() {
    if (expanded || note.type != NoteType.checklist) return null;
    final items = note.checklistItems;
    if (items.isEmpty) return null;
    final toggle = selected == null ? onToggleChecklistItem : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in items.indexed.take(_timelineChecklistLines))
          Semantics(
            label: item.text,
            checked: item.done,
            enabled: toggle != null,
            onTap: toggle == null ? null : () => toggle(index),
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('list-checklist-${note.id}-$index'),
              onTap: toggle == null ? null : () => toggle(index),
              borderRadius: BorderRadius.circular(NexRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: nexMinTapTarget),
                child: Center(child: _ChecklistLine(item: item)),
              ),
            ),
          ),
      ],
    );
  }
}
