import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../widgets/code_language_button.dart';

/// A note as a card in the desktop grid (`docs/27-desktop.md`): a title, a few
/// lines of what is in it, a tag and a time — mostly white space, one hairline.
///
/// Tinted by its first tag's colour, which is the only colour a note has.
class NexDesktopNoteCard extends StatefulWidget {
  const NexDesktopNoteCard({
    super.key,
    required this.note,
    required this.strings,
    required this.onTap,
    this.selected,
    this.ringing = false,
  });

  final Note note;
  final NexCardStrings strings;
  final VoidCallback onTap;

  /// Null when nothing is being selected; otherwise whether this one is.
  final bool? selected;
  final bool ringing;

  /// The height every card in the grid has.
  static const height = 164.0;

  @override
  State<NexDesktopNoteCard> createState() => _NexDesktopNoteCardState();
}

class _NexDesktopNoteCardState extends State<NexDesktopNoteCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = widget.note;
    final tint = nexParseTagColor(note.tags.firstOrNull?.color);
    final selected = widget.selected ?? false;
    final fill = tint == null
        ? scheme.surfaceContainerLowest
        : Color.alphaBlend(
            tint.withValues(alpha: 0.07),
            scheme.surfaceContainerLowest,
          );
    final line = selected
        ? scheme.primary
        : tint == null
        ? (_hover ? scheme.outline : scheme.outlineVariant)
        : tint.withValues(alpha: _hover ? 0.6 : 0.32);
    final snippet = note.snippetPreview;
    final content = nexSplitNoteText(note, widget.strings);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: content.title,
          child: AnimatedContainer(
            duration: NexMotion.of(context, NexMotion.fast),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(NexRadius.md),
              border: Border.all(color: line, width: selected ? 1.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snippet != null ||
                    content.title.isNotEmpty ||
                    note.pinnedAt != null ||
                    widget.ringing ||
                    widget.selected != null) ...[
                  _Title(
                    title: content.title.isEmpty && snippet != null
                        ? nexCodeLanguageLabel(
                            context,
                            snippet.language,
                            rawLanguage: snippet.rawLanguage,
                          )
                        : content.title,
                    note: note,
                    pinned: note.pinnedAt != null,
                    ringing: widget.ringing,
                    selected: widget.selected,
                  ),
                  const SizedBox(height: 6),
                ],
                Expanded(
                  child: _Body(note: note, text: content.body),
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _Footer(note: note, strings: widget.strings),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card's title and the text under it, whatever kind of note it is.
/// Shared by the desktop grid and the phone's grid view.
({String title, String body}) nexSplitNoteText(
  Note note,
  NexCardStrings strings,
) {
  final named = note.title?.trim();
  if (note.type == NoteType.text) {
    // A snippet is source, not prose: its `#` is a comment, not a heading,
    // and its indentation is the code. The fence stays in the note; the
    // card shows only what is inside it.
    final snippet = note.snippetPreview;
    if (snippet != null) {
      return (title: named ?? '', body: snippet.code);
    }
  }
  final text = NexMarkdownText.preview(note.displayText ?? '').trim();
  switch (note.type) {
    case NoteType.text:
      if (named != null && named.isNotEmpty) return (title: named, body: text);
      // A first line is a heading only when it was written as one — a
      // Markdown `#` — not whenever it happens to be short (2.7.2). The guess
      // made a bold title of an ordinary first sentence, which the list card,
      // reading the same note, never did: one note, two different looks.
      final raw = (note.displayText ?? '').trimLeft();
      if (raw.startsWith('#')) {
        final lines = text.split('\n');
        final first = lines.first.trim();
        final rest = lines.skip(1).join('\n').trim();
        if (first.isNotEmpty) return (title: first, body: rest);
      }
      return (title: '', body: text);
    case NoteType.file:
      return (
        title: note.originalFilename ?? strings.noteOfType(note.type.name),
        body: note.mimeType ?? '',
      );
    case NoteType.link:
      final url = note.linkUrl ?? '';
      final host = Uri.tryParse(url)?.host ?? url;
      final excerpt = note.linkExcerpt?.split('\n').first.trim() ?? '';
      return (
        title: named?.isNotEmpty == true
            ? named!
            : (excerpt.isNotEmpty ? excerpt : host),
        body: host,
      );
    case NoteType.checklist:
    case NoteType.photo:
    case NoteType.voice:
      return (title: named ?? '', body: text);
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.title,
    required this.note,
    required this.pinned,
    required this.ringing,
    required this.selected,
  });

  final String title;
  final Note note;
  final bool pinned;
  final bool ringing;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          if (note.type == NoteType.file ||
              note.type == NoteType.link ||
              note.snippetPreview != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
              child: NexNoteCardGlyph(note, size: 16),
            ),
          if (pinned)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Icon(
                Icons.push_pin,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: nexDirectionOf(title),
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (ringing)
            Icon(Icons.notifications_active, size: 15, color: scheme.primary),
          if (selected != null)
            Icon(
              selected! ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: selected! ? scheme.primary : scheme.outline,
            ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.note, required this.text});

  final Note note;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snippet = note.snippetPreview;
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.5,
      color: scheme.onSurfaceVariant,
    );
    final style = snippet == null
        ? baseStyle
        : baseStyle?.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Courier New', 'monospace'],
          );
    if (note.type == NoteType.checklist) {
      final items = note.checklistItems;
      return ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(
                      item.done
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 14,
                      color: item.done ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: nexDirectionOf(item.text),
                        style: style?.copyWith(
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    final uri = note.mediaUri;
    if (note.type == NoteType.photo && uri != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexRadius.sm),
              child: Image.file(
                File(uri),
                fit: BoxFit.cover,
                cacheWidth: 600,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(Icons.image_outlined, color: scheme.outline),
                ),
              ),
            ),
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: nexDirectionOf(text),
                style: style,
              ),
            ),
        ],
      );
    }
    final seconds = (note.durationMs ?? 0) ~/ 1000;
    final shown = note.type == NoteType.voice && seconds > 0
        ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
              '${text.isEmpty ? '' : '\n$text'}'
        : text;
    return Text(
      shown,
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      textDirection: snippet == null
          ? nexDirectionOf(shown)
          : TextDirection.ltr,
      style: style,
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.note, required this.strings});

  final Note note;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelSmall?.copyWith(
      fontSize: 11,
      color: scheme.onSurfaceVariant,
    );
    final tag = note.tags.firstOrNull;
    return Row(
      children: [
        if (tag != null)
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(NexRadius.xs),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: nexParseTagColor(tag.color) ?? scheme.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        strings.tagName?.call(tag) ?? tag.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small?.copyWith(color: scheme.onSurface),
                      ),
                    ),
                    if (note.tags.length > 1)
                      Text(' +${note.tags.length - 1}', style: small),
                  ],
                ),
              ),
            ),
          ),
        if (note.dueAt != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.notifications_none, size: 13, color: scheme.primary),
        ],
        if (note.attachmentCount > 0) ...[
          const SizedBox(width: 8),
          Icon(Icons.attach_file, size: 13, color: scheme.onSurfaceVariant),
        ],
        const Spacer(),
        Text(
          strings.relativeTime(nexRelativeTimeOf(note.updatedAt)),
          style: small,
        ),
      ],
    );
  }
}
