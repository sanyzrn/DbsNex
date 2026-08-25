import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../l10n/app_localizations.dart';

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
  _TextMark({required this.text, required this.position, required this.color});
  final String text;
  Offset position;
  final Color color;
}

/// Freehand drawing and draggable text labels on top of a photo, reached
/// optionally from [PhotoCropScreen] after the crop is confirmed — cropping
/// first means a stroke never ends up outside the frame a later crop removes.
///
/// Returns the composited PNG bytes, or `null` if nothing was added (the
/// caller then keeps the plain cropped photo — annotating is additive, never
/// a second required confirmation).
class PhotoAnnotateScreen extends StatefulWidget {
  const PhotoAnnotateScreen({super.key, required this.image});

  final Uint8List image;

  @override
  State<PhotoAnnotateScreen> createState() => _PhotoAnnotateScreenState();
}

class _PhotoAnnotateScreenState extends State<PhotoAnnotateScreen> {
  final _boundaryKey = GlobalKey();
  _Mode _mode = _Mode.draw;
  Color _color = _palette.first;
  double _strokeWidth = 6;
  final List<_Mark> _marks = [];
  bool _saving = false;
  int? _nativeWidth;
  int? _nativeHeight;

  @override
  void initState() {
    super.initState();
    unawaited(_readNativeSize());
  }

  Future<void> _readNativeSize() async {
    final decoded = await Future(() => img.decodeImage(widget.image));
    if (!mounted || decoded == null) return;
    setState(() {
      _nativeWidth = decoded.width;
      _nativeHeight = decoded.height;
    });
  }

  bool get _hasChanges => _marks.isNotEmpty;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _marks.add(
        _Stroke(color: _color, width: _strokeWidth)
          ..points.add(details.localPosition),
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final last = _marks.last;
    if (last is! _Stroke) return;
    setState(() => last.points.add(details.localPosition));
  }

  Future<void> _placeText(Offset position) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: NexAutoDirection(
          controller: controller,
          builder: (context, direction) => TextField(
            controller: controller,
            autofocus: true,
            textDirection: direction,
            textAlign: TextAlign.start,
            decoration: InputDecoration(hintText: l10n.annotateTextHint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _marks.add(
        _TextMark(text: text.trim(), position: position, color: _color),
      );
    });
  }

  void _undo() {
    if (_marks.isEmpty) return;
    setState(() => _marks.removeLast());
  }

  void _clear() {
    if (_marks.isEmpty) return;
    setState(_marks.clear);
  }

  Future<void> _done() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    // Captured at the source photo's own resolution, not the screen's —
    // otherwise every annotated photo would be downgraded to whatever the
    // device happened to render it at.
    final nativeWidth = _nativeWidth;
    final pixelRatio = nativeWidth == null
        ? MediaQuery.of(context).devicePixelRatio
        : nativeWidth / boundary.size.width;
    final rendered = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.of(context).pop(bytes!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ratio = _nativeWidth == null || _nativeHeight == null
        ? 1.0
        : _nativeWidth! / _nativeHeight!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.annotateTitle),
        actions: [
          IconButton(
            tooltip: l10n.annotateUndo,
            icon: const Icon(Icons.undo),
            onPressed: _marks.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: l10n.annotateClear,
            icon: const Icon(Icons.delete_outline),
            onPressed: _marks.isEmpty ? null : _clear,
          ),
          TextButton(
            onPressed: _saving ? null : _done,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    l10n.annotateDone,
                    style: const TextStyle(color: Colors.white),
                  ),
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
                        onPanStart: _mode == _Mode.draw ? _onPanStart : null,
                        onPanUpdate: _mode == _Mode.draw ? _onPanUpdate : null,
                        onTapUp: _mode == _Mode.text
                            ? (d) => unawaited(_placeText(d.localPosition))
                            : null,
                        child: CustomPaint(
                          painter: _StrokePainter(
                            _marks.whereType<_Stroke>().toList(),
                          ),
                        ),
                      ),
                      for (final mark in _marks.whereType<_TextMark>())
                        Positioned(
                          left: mark.position.dx,
                          top: mark.position.dy,
                          child: GestureDetector(
                            onPanUpdate: (d) =>
                                setState(() => mark.position += d.delta),
                            child: Text(
                              mark.text,
                              style: TextStyle(
                                color: mark.color,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                shadows: const [
                                  Shadow(blurRadius: 4, color: Colors.black87),
                                ],
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
          if (_mode == _Mode.text)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                l10n.annotateTapToPlaceText,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final swatch in _palette)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => setState(() => _color = swatch),
                            child: Container(
                              width: 28,
                              height: 28,
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
                    ],
                  ),
                  if (_mode == _Mode.draw)
                    Slider(
                      value: _strokeWidth,
                      min: 2,
                      max: 20,
                      onChanged: (value) =>
                          setState(() => _strokeWidth = value),
                    ),
                  SegmentedButton<_Mode>(
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.strokes);

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
