import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import 'nex_tokens.dart';

/// A card's central glyph, sized and colored by the existing note-type disc.
class NexNoteCardGlyph extends StatelessWidget {
  const NexNoteCardGlyph(this.note, {super.key, this.size, this.color});

  final Note note;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final glyph = note.type == NoteType.file
        ? _nameIcon(note.originalFilename) ??
              _mimeIcon(note.mimeType) ??
              _nameIcon(note.mediaUri)
        : null;
    if (glyph != _FileGlyph.markdown) {
      return Icon(
        glyph?.icon ??
            (note.snippetPreview != null
                ? Icons.code_rounded
                : nexNoteTypeIcon(note.type.wireName)),
        size: size,
        color: color,
      );
    }

    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final ink = color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: Center(
        child: SizedBox.square(
          dimension: side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: side, color: color),
              Align(
                alignment: const Alignment(0, 0.42),
                child: Text(
                  'MD',
                  textDirection: TextDirection.ltr,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    inherit: false,
                    color: ink.withValues(alpha: ink.a * (theme.opacity ?? 1)),
                    fontSize: side * 0.27,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FileGlyph {
  markdown(null),
  pdf(Icons.picture_as_pdf_outlined),
  archive(Icons.folder_zip_outlined),
  spreadsheet(Icons.table_chart_outlined),
  slides(Icons.slideshow_outlined),
  document(Icons.description_outlined),
  text(Icons.article_outlined),
  image(Icons.image_outlined),
  book(Icons.menu_book_outlined),
  code(Icons.code_outlined),
  audio(Icons.audio_file_outlined),
  video(Icons.smart_display_outlined);

  const _FileGlyph(this.icon);
  final IconData? icon;
}

_FileGlyph? _nameIcon(String? name) {
  if (name == null || name.isEmpty) return null;
  return switch (NexFileKinds.extensionOf(name)) {
    'pdf' => _FileGlyph.pdf,
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'tgz' ||
    'gz' ||
    'bz2' ||
    'xz' => _FileGlyph.archive,
    'xls' || 'xlsx' || 'xlsm' || 'ods' => _FileGlyph.spreadsheet,
    'ppt' || 'pptx' || 'pps' || 'ppsx' || 'odp' => _FileGlyph.slides,
    'docm' || 'dot' || 'dotx' => _FileGlyph.document,
    'svg' || 'tif' || 'tiff' || 'avif' || 'ico' => _FileGlyph.image,
    'epub' => _FileGlyph.book,
    _ => _kindIcon(NexFileKinds.of(path: name)),
  };
}

_FileGlyph? _mimeIcon(String? mimeType) {
  final type = mimeType?.split(';').first.trim().toLowerCase();
  return switch (type) {
    'application/pdf' => _FileGlyph.pdf,
    'application/zip' ||
    'application/x-zip-compressed' ||
    'application/vnd.rar' ||
    'application/x-rar-compressed' ||
    'application/x-7z-compressed' ||
    'application/x-tar' ||
    'application/gzip' ||
    'application/x-gzip' ||
    'application/x-bzip2' ||
    'application/x-xz' => _FileGlyph.archive,
    'application/vnd.ms-excel' ||
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    'application/vnd.ms-excel.sheet.macroenabled.12' ||
    'application/vnd.oasis.opendocument.spreadsheet' => _FileGlyph.spreadsheet,
    'application/vnd.ms-powerpoint' ||
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' ||
    'application/vnd.openxmlformats-officedocument.presentationml.slideshow' ||
    'application/vnd.oasis.opendocument.presentation' => _FileGlyph.slides,
    'image/svg+xml' => _FileGlyph.image,
    'application/epub+zip' => _FileGlyph.book,
    'application/json' ||
    'application/javascript' ||
    'application/xml' => _FileGlyph.code,
    _ => _kindIcon(NexFileKinds.of(mimeType: type)),
  };
}

_FileGlyph? _kindIcon(NexFileKind kind) => switch (kind) {
  NexFileKind.markdown => _FileGlyph.markdown,
  NexFileKind.plainText => _FileGlyph.text,
  NexFileKind.code => _FileGlyph.code,
  NexFileKind.table => _FileGlyph.spreadsheet,
  NexFileKind.image => _FileGlyph.image,
  NexFileKind.audio => _FileGlyph.audio,
  NexFileKind.video => _FileGlyph.video,
  NexFileKind.document => _FileGlyph.document,
  NexFileKind.other => null,
};
