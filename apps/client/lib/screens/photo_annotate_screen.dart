import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:flutter/rendering.dart';

import '../l10n/app_localizations.dart';
import '../platform/editor_drafts.dart';
import 'package:crypto/crypto.dart';
import '../widgets/draft_guard.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/photo_editor_theme.dart';

enum _Mode { draw, text }

const _palette = [
  Colors.white,
  Colors.black,
  Color(0xFFEF4444),
  Color(0xFFFACC15),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
];

sealed class _Mark {
  const _Mark();
}

class _Stroke extends _Mark {
  _Stroke({required this.color, required this.width}) : points = [];
  final Color color;
  final double width;
  final List<Offset> points;
}

class _TextMark extends _Mark {
  _TextMark({
    required this.text,
    required this.position,
    required this.color,
    this.size = _defaultTextSize,
  });
  String text;

  /// Where the middle of the label is: where the finger was.
  Offset position;
  final Color color;
  final double size;
}

const _defaultTextSize = 24.0;

/// Freehand drawing and draggable text labels on top of a photo, reached
/// optionally from [PhotoCropScreen] after the crop is confirmed — cropping
/// first means a stroke never ends up outside the frame a later crop removes.
///
/// Returns the composited PNG bytes, or `null` if nothing was added (the
/// caller then keeps the plain cropped photo — annotating is additive, never
/// a second required confirmation).
class PhotoAnnotateScreen extends StatefulWidget {
  const PhotoAnnotateScreen({
    super.key,
    required this.image,
    this.drafts,
    this.draftKey = 'photo-new',
  });

  final Uint8List image;
  final EditorDrafts? drafts;
  final String draftKey;

  @override
  State<PhotoAnnotateScreen> createState() => _PhotoAnnotateScreenState();
}

class _PhotoAnnotateScreenState extends State<PhotoAnnotateScreen>
    with NexDraftGuard<PhotoAnnotateScreen> {
  @override
  bool get hasUnsavedChanges => _hasChanges;
  String get _draftKey => '${widget.draftKey}-annotation';
  late final String _imageHash = sha256.convert(widget.image).toString();
  @override
  void discardDraft() => widget.drafts?.clear(_draftKey);
  void _snapshot() {
    final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;
    final width = box.size.width;
    widget.drafts?.write(_draftKey, {
      'image': _imageHash,
      'marks': [
        for (final mark in _marks)
          switch (mark) {
            _Stroke() => {
              'kind': 'stroke',
              'color': mark.color.toARGB32(),
              'width': mark.width / width,
              'points': [
                for (final point in mark.points)
                  [point.dx / width, point.dy / width],
              ],
            },
            _TextMark() => {
              'kind': 'text',
              'color': mark.color.toARGB32(),
              'text': mark.text,
              'x': mark.position.dx / width,
              'y': mark.position.dy / width,
              'size': mark.size / width,
            },
          },
      ],
    });
  }

  void _restoreMarks() {
    final d = widget.drafts?.read(_draftKey);
    final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (d == null || d['image'] != _imageHash || box == null) return;
    final width = box.size.width;
    final marks = <_Mark>[];
    try {
      for (final mark in d['marks'] as List) {
        final color = Color(mark['color'] as int);
        if (mark['kind'] == 'stroke') {
          final stroke = _Stroke(
            color: color,
            width: (mark['width'] as num).toDouble() * width,
          );
          for (final point in mark['points'] as List) {
            stroke.points.add(
              Offset(
                (point[0] as num).toDouble() * width,
                (point[1] as num).toDouble() * width,
              ),
            );
          }
          marks.add(stroke);
        } else {
          final size = (mark['size'] as num?)?.toDouble();
          marks.add(
            _TextMark(
              text: mark['text'] as String,
              color: color,
              size: size == null ? _defaultTextSize : size * width,
              position: Offset(
                (mark['x'] as num).toDouble() * width,
                (mark['y'] as num).toDouble() * width,
              ),
            ),
          );
        }
      }
      if (mounted) setState(() => _marks.addAll(marks));
    } catch (_) {
      /* Preserve unreadable draft for recovery. */
    }
  }

  final _boundaryKey = GlobalKey();
  _Mode _mode = _Mode.draw;
  Color _color = _palette.first;
  double _strokeWidth = 6;
  double _textSize = _defaultTextSize;
  final List<_Mark> _marks = [];

  /// What undo took, newest last, for redo. Emptied by any new mark.
  final List<_Mark> _undone = [];

  /// Repaints the strokes as a finger moves, without rebuilding the screen:
  /// every movement used to rebuild everything, the photo and the controls
  /// included.
  final _ink = ValueNotifier<int>(0);

  @override
  void dispose() {
    _ink.dispose();
    super.dispose();
  }

  bool _saving = false;
  int? _nativeWidth;
  int? _nativeHeight;

  @override
  void initState() {
    super.initState();
    unawaited(
      _readNativeSize().then((_) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _restoreMarks();
          });
        }
      }),
    );
  }

  Future<void> _readNativeSize() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(widget.image);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!mounted) return;
      setState(() {
        _nativeWidth = descriptor!.width;
        _nativeHeight = descriptor.height;
      });
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).captureFailed,
        );
      }
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  bool get _hasChanges => _marks.isNotEmpty;

  @override
  Future<void> requestDiscard() async {
    if (_saving) return;
    await super.requestDiscard();
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _undone.clear();
      _marks.add(
        _Stroke(color: _color, width: _strokeWidth)
          ..points.add(details.localPosition),
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_marks.isEmpty) return;
    final last = _marks.last;
    if (last is! _Stroke) return;
    last.points.add(details.localPosition);
    _ink.value++;
  }

  /// A tap with the pen is a dot. It used to be nothing: a stroke only
  /// began once a finger moved.
  void _dot(Offset position) {
    setState(() {
      _undone.clear();
      _marks.add(
        _Stroke(color: _color, width: _strokeWidth)..points.add(position),
      );
    });
    _snapshot();
  }

  Future<void> _placeText(Offset position) async {
    final text = await nexShowDialog<String>(
      context: context,
      builder: (_) => const _AnnotationTextDialog(),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() {
      _undone.clear();
      _marks.add(
        _TextMark(
          text: text.trim(),
          position: position,
          color: _color,
          size: _textSize,
        ),
      );
    });
    _snapshot();
  }

  /// A label held: change its words, or take it off.
  Future<void> _editText(_TextMark mark) async {
    final text = await nexShowDialog<String>(
      context: context,
      builder: (_) => _AnnotationTextDialog(initial: mark.text),
    );
    if (!mounted || text == null) return;
    setState(() {
      if (text.trim().isEmpty) {
        _marks.remove(mark);
      } else {
        mark.text = text.trim();
      }
    });
    _snapshot();
  }

  void _undo() {
    if (_marks.isEmpty) return;
    setState(() => _undone.add(_marks.removeLast()));
    _snapshot();
  }

  void _redo() {
    if (_undone.isEmpty) return;
    setState(() => _marks.add(_undone.removeLast()));
    _snapshot();
  }

  void _clear() {
    if (_marks.isEmpty) return;
    setState(() {
      _undone.clear();
      _marks.clear();
    });
    _snapshot();
  }

  Future<void> _done() async {
    if (_saving || _nativeWidth == null || _nativeHeight == null) return;
    if (!_hasChanges) {
      Navigator.of(context).pop(widget.image);
      return;
    }
    setState(() => _saving = true);
    ui.Image? rendered;
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      // Captured at the source photo's own resolution, not the screen's —
      // otherwise every annotated photo would be downgraded to whatever the
      // device happened to render it at.
      final pixelRatio = _nativeWidth! / boundary.size.width;
      rendered = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.of(context).pop(bytes!.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).captureFailed,
        );
      }
    } finally {
      rendered?.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ratio = _nativeWidth == null || _nativeHeight == null
        ? 1.0
        : _nativeWidth! / _nativeHeight!;
    final drawing = _mode == _Mode.draw;
    return NexPhotoEditorTheme(
      child: guardDraft(
        AbsorbPointer(
          absorbing: _saving,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
              title: Text(l10n.annotateTitle),
              leading: IconButton(
                tooltip: l10n.closeLabel,
                onPressed: requestDiscard,
                icon: const Icon(Icons.close),
              ),
              actions: [
                IconButton(
                  tooltip: l10n.annotateUndo,
                  icon: const Icon(Icons.undo),
                  onPressed: _marks.isEmpty ? null : _undo,
                ),
                IconButton(
                  tooltip: l10n.annotateRedo,
                  icon: const Icon(Icons.redo),
                  onPressed: _undone.isEmpty ? null : _redo,
                ),
                IconButton(
                  tooltip: l10n.annotateClear,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _marks.isEmpty ? null : _clear,
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: ratio,
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(widget.image, fit: BoxFit.contain),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: drawing ? _onPanStart : null,
                              onPanUpdate: drawing ? _onPanUpdate : null,
                              onPanEnd: (_) => _snapshot(),
                              onPanCancel: _snapshot,
                              onTapUp: (d) => drawing
                                  ? _dot(d.localPosition)
                                  : unawaited(_placeText(d.localPosition)),
                              child: CustomPaint(
                                key: const ValueKey('annotate-canvas'),
                                painter: _StrokePainter(
                                  _marks.whereType<_Stroke>().toList(),
                                  repaint: _ink,
                                ),
                              ),
                            ),
                            for (final mark in _marks.whereType<_TextMark>())
                              Positioned(
                                left: mark.position.dx,
                                top: mark.position.dy,
                                // Centred on where the finger was, not hung
                                // below and beside it.
                                child: FractionalTranslation(
                                  translation: const Offset(-0.5, -0.5),
                                  child: GestureDetector(
                                    onLongPress: () =>
                                        unawaited(_editText(mark)),
                                    onPanEnd: (_) => _snapshot(),
                                    onPanUpdate: (d) {
                                      final boundary =
                                          _boundaryKey.currentContext
                                                  ?.findRenderObject()
                                              as RenderBox?;
                                      if (boundary == null) return;
                                      setState(() {
                                        final next = mark.position + d.delta;
                                        mark.position = Offset(
                                          next.dx.clamp(0, boundary.size.width),
                                          next.dy.clamp(
                                            0,
                                            boundary.size.height,
                                          ),
                                        );
                                      });
                                    },
                                    child: Text(
                                      mark.text,
                                      textDirection: nexDirectionOf(mark.text),
                                      style: TextStyle(
                                        color: mark.color,
                                        fontSize: mark.size,
                                        fontWeight: FontWeight.w700,
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 4,
                                            color: Colors.black87,
                                          ),
                                        ],
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
                ),
                if (!drawing)
                  Padding(
                    padding: const EdgeInsets.all(NexSpacing.sm),
                    child: Text(
                      _marks.any((mark) => mark is _TextMark)
                          ? l10n.annotateEditTextHint
                          : l10n.annotateTapToPlaceText,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NexSpacing.md,
                      NexSpacing.sm,
                      NexSpacing.md,
                      NexSpacing.md,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SegmentedButton<_Mode>(
                                segments: [
                                  ButtonSegment(
                                    value: _Mode.draw,
                                    icon: const Icon(Icons.brush_outlined),
                                    label: Text(l10n.annotateDraw),
                                  ),
                                  ButtonSegment(
                                    value: _Mode.text,
                                    icon: const Icon(Icons.text_fields),
                                    label: Text(l10n.annotateText),
                                  ),
                                ],
                                selected: {_mode},
                                onSelectionChanged: (selection) =>
                                    setState(() => _mode = selection.first),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NexSpacing.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final (index, swatch) in _palette.indexed)
                              Semantics(
                                button: true,
                                selected: _color == swatch,
                                label: l10n.annotateColor(
                                  const [
                                    'white',
                                    'black',
                                    'red',
                                    'yellow',
                                    'green',
                                    'blue',
                                  ][index],
                                ),
                                child: InkResponse(
                                  onTap: () => setState(() => _color = swatch),
                                  child: SizedBox.square(
                                    dimension: 44,
                                    child: Center(
                                      child: AnimatedContainer(
                                        duration: NexMotion.fast,
                                        width: _color == swatch ? 32 : 26,
                                        height: _color == swatch ? 32 : 26,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: swatch,
                                          border: Border.all(
                                            color: _color == swatch
                                                ? Colors.white
                                                : Colors.white24,
                                            width: _color == swatch ? 3 : 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // One slider for both: the pen's width while
                        // drawing, the size of new text while placing it —
                        // with the mark it makes drawn beside it.
                        Row(
                          children: [
                            SizedBox.square(
                              dimension: 44,
                              child: Center(
                                child: drawing
                                    ? AnimatedContainer(
                                        duration: NexMotion.fast,
                                        width: _strokeWidth + 2,
                                        height: _strokeWidth + 2,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _color,
                                          border: Border.all(
                                            color: Colors.white38,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        'Aa',
                                        style: TextStyle(
                                          color: _color,
                                          fontSize: _textSize * 0.7,
                                          fontWeight: FontWeight.w700,
                                          shadows: const [
                                            Shadow(
                                              blurRadius: 3,
                                              color: Colors.black,
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                semanticFormatterCallback: (value) =>
                                    '${drawing ? l10n.annotateStrokeWidth : l10n.annotateSize}: ${value.round()}',
                                value: drawing ? _strokeWidth : _textSize,
                                min: drawing ? 2 : 14,
                                max: drawing ? 24 : 56,
                                onChanged: (value) => setState(
                                  () => drawing
                                      ? _strokeWidth = value
                                      : _textSize = value,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NexSpacing.xs),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving || _nativeWidth == null
                                ? null
                                : _done,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check),
                            label: Text(l10n.annotateDone),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                        ),
                      ],
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
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, {super.repaint});

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final points = stroke.points;
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (points.length == 1) {
        canvas.drawCircle(
          points.first,
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      // Through the midpoints, with each sampled point as the curve's
      // control: a line that bends where the finger did, rather than a chain
      // of straight segments that shows its corners on a fast stroke.
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length - 1; i++) {
        final mid = (points[i] + points[i + 1]) / 2;
        path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  // The strokes grow in place as a finger moves, and [repaint] says when;
  // a new list means marks were added or taken away.
  @override
  bool shouldRepaint(_StrokePainter oldDelegate) => true;
}

class _AnnotationTextDialog extends StatefulWidget {
  const _AnnotationTextDialog({this.initial});

  /// The label's words when one is being changed; null for a new one.
  final String? initial;

  @override
  State<_AnnotationTextDialog> createState() => _AnnotationTextDialogState();
}

class _AnnotationTextDialogState extends State<_AnnotationTextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      content: NexAutoDirection(
        controller: _text,
        builder: (context, direction) => TextField(
          controller: _text,
          autofocus: true,
          textDirection: direction,
          textAlign: TextAlign.start,
          selectionWidthStyle: ui.BoxWidthStyle.tight,
          contextMenuBuilder: nexReadingMenu,
          decoration: InputDecoration(hintText: l10n.annotateTextHint),
        ),
      ),
      actions: [
        // Changing a label can also take it off; an empty answer does too.
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(l10n.annotateDelete),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
