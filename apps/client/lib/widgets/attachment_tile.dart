import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../platform/pdf_preview.dart';
import '../platform/video_preview.dart';

/// One file a note carries after its own, as a square tile
/// (`docs/14-attachments.md`).
///
/// Each kind shows what it is at a glance, the way a file manager would: a
/// photo as itself, a video as one of its frames with a play mark, a PDF as
/// the top of its first page, a voice clip as its length, and anything else
/// as its kind and its extension. A caption, when there is one, runs along
/// the bottom.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.side,
    required this.onTap,
  });

  final NoteAttachment attachment;
  final double side;
  final VoidCallback onTap;

  /// What a file is, from its type and, failing that, its extension.
  static AttachmentLook lookOf(NoteAttachment attachment) {
    if (attachment.kind == AttachmentKind.photo) return AttachmentLook.photo;
    if (attachment.kind == AttachmentKind.voice) return AttachmentLook.voice;
    final mime = attachment.mimeType?.toLowerCase() ?? '';
    final ext = p
        .extension(attachment.name ?? attachment.mediaUri)
        .toLowerCase();
    if (mime == 'application/pdf' || ext == '.pdf') return AttachmentLook.pdf;
    if (mime.startsWith('video/') ||
        const {'.mp4', '.mov', '.mkv', '.webm', '.3gp'}.contains(ext)) {
      return AttachmentLook.video;
    }
    if (mime.startsWith('image/') ||
        const {
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.heic',
          '.gif',
        }.contains(ext)) {
      return AttachmentLook.photo;
    }
    if (mime.startsWith('audio/') ||
        const {'.m4a', '.mp3', '.aac', '.ogg', '.wav', '.opus'}.contains(ext)) {
      return AttachmentLook.audio;
    }
    if (const {'.xls', '.xlsx', '.csv', '.ods', '.tsv'}.contains(ext)) {
      return AttachmentLook.sheet;
    }
    if (const {'.zip', '.rar', '.7z', '.tar', '.gz'}.contains(ext)) {
      return AttachmentLook.archive;
    }
    if (const {'.doc', '.docx', '.odt', '.rtf', '.txt', '.md'}.contains(ext)) {
      return AttachmentLook.document;
    }
    return AttachmentLook.file;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final look = lookOf(attachment);
    final name =
        attachment.name ??
        attachment.caption ??
        p.basename(attachment.mediaUri);
    final caption = attachment.caption?.trim() ?? '';
    final pictured = look == AttachmentLook.photo;
    return Semantics(
      button: true,
      label: [
        switch (look) {
          AttachmentLook.photo => l10n.photo,
          AttachmentLook.voice => l10n.attachVoice,
          _ => name,
        },
        if (caption.isNotEmpty) caption,
      ].join('. '),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(
              fit: StackFit.expand,
              children: [
                switch (look) {
                  AttachmentLook.photo => Image.file(
                    File(attachment.mediaUri),
                    fit: BoxFit.cover,
                    cacheWidth: (side * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorBuilder: (_, _, _) =>
                        _Kind(look: look, label: name, extension: ''),
                  ),
                  AttachmentLook.pdf || AttachmentLook.video => _Rendered(
                    attachment: attachment,
                    look: look,
                    fallback: _Kind(
                      look: look,
                      label: name,
                      extension: _extensionOf(attachment),
                    ),
                  ),
                  AttachmentLook.voice => _Kind(
                    look: look,
                    label: _clock(attachment.durationMs, l10n),
                    extension: '',
                  ),
                  _ => _Kind(
                    look: look,
                    label: name,
                    extension: _extensionOf(attachment),
                  ),
                },
                if (caption.isNotEmpty && pictured)
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xB3000000), Color(0x00000000)],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          NexSpacing.xs + 2,
                          NexSpacing.md,
                          NexSpacing.xs + 2,
                          NexSpacing.xs,
                        ),
                        child: Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: nexDirectionOf(caption),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _extensionOf(NoteAttachment attachment) {
    final ext = p.extension(attachment.name ?? attachment.mediaUri);
    return ext.length > 1 && ext.length <= 6
        ? ext.substring(1).toUpperCase()
        : '';
  }

  static String _clock(int? ms, AppLocalizations l10n) {
    final seconds = ((ms ?? 0) / 1000).round();
    return nexDigits(
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      persian: l10n.localeName == 'fa',
    );
  }
}

/// The kinds of file a tile tells apart.
enum AttachmentLook {
  photo,
  video,
  pdf,
  voice,
  audio,
  document,
  sheet,
  archive,
  file,
}

/// A file shown as what it is: its kind's icon, its extension on a small
/// badge, and its name — or, for a voice clip, its length.
class _Kind extends StatelessWidget {
  const _Kind({
    required this.look,
    required this.label,
    required this.extension,
  });

  final AttachmentLook look;
  final String label;
  final String extension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final voice = look == AttachmentLook.voice;
    return LayoutBuilder(
      builder: (context, box) {
        // A small tile — the one heading a file's menu — has room for what
        // the file is, not for its name.
        final roomy = box.maxHeight >= 80;
        return Padding(
          padding: EdgeInsets.all(roomy ? NexSpacing.sm : NexSpacing.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                switch (look) {
                  AttachmentLook.voice => Icons.mic_none,
                  AttachmentLook.audio => Icons.audiotrack_outlined,
                  AttachmentLook.pdf => Icons.picture_as_pdf_outlined,
                  AttachmentLook.video => Icons.movie_outlined,
                  AttachmentLook.sheet => Icons.table_chart_outlined,
                  AttachmentLook.archive => Icons.folder_zip_outlined,
                  AttachmentLook.document => Icons.description_outlined,
                  AttachmentLook.photo => Icons.image_outlined,
                  AttachmentLook.file => Icons.insert_drive_file_outlined,
                },
                size: roomy ? 24 : 20,
                color: voice ? scheme.primary : scheme.onSurfaceVariant,
              ),
              if (extension.isNotEmpty) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(NexRadius.xs),
                  ),
                  child: Text(
                    extension,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
              if (roomy || voice) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    label,
                    maxLines: extension.isEmpty ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: voice
                        ? theme.textTheme.labelLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )
                        : theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A PDF's first page or a video's frame, drawn by the platform once and
/// kept: the strip is rebuilt as attachments come and go, and asking the
/// platform for the same picture again each time would make it flicker.
/// [fallback] until it arrives, and for good where there is none.
class _Rendered extends StatefulWidget {
  const _Rendered({
    required this.attachment,
    required this.look,
    required this.fallback,
  });

  final NoteAttachment attachment;
  final AttachmentLook look;
  final Widget fallback;

  static final _cache = <String, Future<Uint8List?>>{};

  @override
  State<_Rendered> createState() => _RenderedState();
}

class _RenderedState extends State<_Rendered> {
  late final Future<Uint8List?> _picture = _Rendered._cache.putIfAbsent(
    widget.attachment.mediaUri,
    () {
      // A handful of tiles at most; the oldest goes first.
      if (_Rendered._cache.length > 48) {
        _Rendered._cache.remove(_Rendered._cache.keys.first);
      }
      return widget.look == AttachmentLook.pdf
          ? NexPdfPreview.firstPage(
              widget.attachment.mediaUri,
              width: 360,
              maxHeight: 360,
            )
          : NexVideoPreview.poster(widget.attachment.mediaUri, width: 360);
    },
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _picture,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null) return widget.fallback;
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            bytes,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            gaplessPlayback: true,
          ),
          if (widget.look == AttachmentLook.video)
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x80000000),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(NexSpacing.xs),
                  child: Icon(Icons.play_arrow, color: Colors.white, size: 20),
                ),
              ),
            )
          else
            PositionedDirectional(
              end: NexSpacing.xs,
              top: NexSpacing.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexSpacing.xs,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(NexRadius.xs),
                ),
                child: const Text(
                  'PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
