import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

import '../tokens/nex_tokens.dart';

/// Timeline / search card aligned with mockup.html (bordered 22px card).
///
/// Outer horizontal padding is applied by [SwipeableNoteCard] on the Timeline
/// so swipe reveals clip per-card; when used outside swipe, wrap with padding.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.footnote,
    this.onPlayVoice,
    this.isVoicePlaying = false,
    this.padded = false,
  });

  final Note note;
  final VoidCallback? onTap;
  final String? footnote;
  /// Timeline one-tap voice playback (item 14).
  final VoidCallback? onPlayVoice;
  final bool isVoicePlaying;
  /// When true, applies mockup horizontal padding (Search results).
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexColors.cardRadius),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeadingVisual(
                    note: note,
                    onPlayVoice: onPlayVoice,
                    isVoicePlaying: isVoicePlaying,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _preview(theme),
                        if (note.caption != null &&
                            note.caption!.trim().isNotEmpty &&
                            note.type != NoteType.text) ...[
                          const SizedBox(height: 4),
                          Text(
                            note.caption!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        if (footnote != null) ...[
                          const SizedBox(height: NexSpacing.xs),
                          Text(
                            footnote!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w400,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: NexSpacing.sm),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _relativeTime(note.createdAt),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                              ),
                            ),
                            if (note.type == NoteType.voice &&
                                note.durationMs != null) ...[
                              Text(
                                '·',
                                style: TextStyle(
                                  color: theme.colorScheme.secondary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              Text(
                                _formatDuration(note.durationMs!),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            for (final tag in note.tags) ...[
                              Text(
                                '·',
                                style: TextStyle(
                                  color: theme.colorScheme.secondary
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              TagChip(tag: tag, compact: true),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!padded) return card;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: NexSpacing.xs + 1,
      ),
      child: card,
    );
  }

  Widget _preview(ThemeData theme) {
    switch (note.type) {
      case NoteType.text:
        return Text(
          note.content ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
          textDirection: _detectDirection(note.content ?? ''),
        );
      case NoteType.voice:
        final caption = note.caption?.trim();
        if (caption != null && caption.isNotEmpty) {
          return Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          );
        }
        final secs = ((note.durationMs ?? 0) / 1000).ceil();
        return Text(
          'Voice · ${secs}s',
          style: theme.textTheme.bodyLarge,
        );
      case NoteType.photo:
        final caption = note.caption?.trim();
        if (caption != null && caption.isNotEmpty) {
          return Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          );
        }
        return Text(
          note.ocrText?.trim().isNotEmpty == true ? note.ocrText! : 'Photo',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        );
      case NoteType.file:
        final name = note.content?.trim().isNotEmpty == true
            ? note.content!
            : (note.mediaUri != null ? p.basename(note.mediaUri!) : 'File');
        String? sizeLabel;
        final uri = note.mediaUri;
        if (uri != null && File(uri).existsSync()) {
          sizeLabel = nexFormatBytes(File(uri).lengthSync());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
            if (sizeLabel != null || note.mimeType != null)
              Text(
                [
                  if (sizeLabel != null) sizeLabel,
                  if (note.mimeType != null) note.mimeType!,
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                ),
              ),
          ],
        );
    }
  }

  static TextDirection _detectDirection(String text) {
    for (final code in text.runes) {
      if (code >= 0x0600 && code <= 0x06FF) return TextDirection.rtl;
    }
    return TextDirection.ltr;
  }

  static String _relativeTime(DateTime at) {
    final diff = DateTime.now().toUtc().difference(at.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }

  static String _formatDuration(int ms) {
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _LeadingVisual extends StatelessWidget {
  const _LeadingVisual({
    required this.note,
    this.onPlayVoice,
    this.isVoicePlaying = false,
  });

  final Note note;
  final VoidCallback? onPlayVoice;
  final bool isVoicePlaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boxDecoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    );
    switch (note.type) {
      case NoteType.photo:
        final uri = note.mediaUri;
        if (uri != null && File(uri).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(uri),
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _iconBox(
                theme,
                Icons.image_outlined,
                boxDecoration,
              ),
            ),
          );
        }
        return _iconBox(theme, Icons.image_outlined, boxDecoration);
      case NoteType.voice:
        if (onPlayVoice != null) {
          return Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onPlayVoice,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  isVoicePlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 28,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          );
        }
        return _iconBox(theme, Icons.graphic_eq, boxDecoration);
      case NoteType.file:
        return _iconBox(
          theme,
          _fileIcon(note.content ?? note.mediaUri, note.mimeType),
          boxDecoration,
        );
      case NoteType.text:
        return _iconBox(theme, Icons.short_text, boxDecoration);
    }
  }

  static IconData _fileIcon(String? name, String? mime) {
    final lower = '${name ?? ''} ${mime ?? ''}'.toLowerCase();
    if (lower.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.contains('image') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (lower.contains('audio') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav')) {
      return Icons.audiotrack;
    }
    if (lower.contains('zip') || lower.endsWith('.rar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Widget _iconBox(ThemeData theme, IconData icon, BoxDecoration decoration) {
    return Container(
      width: 56,
      height: 56,
      decoration: decoration,
      child: Icon(icon, size: 22, color: theme.colorScheme.onSurface),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    this.onRemove,
    this.compact = false,
  });

  final Tag tag;
  final VoidCallback? onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = tag.color != null
        ? Color(int.parse(tag.color!.substring(1), radix: 16) + 0xFF000000)
        : null;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accent != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            tag.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w400,
              fontSize: 14,
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accent != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(tag.name, style: theme.textTheme.bodyMedium),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 14,
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
