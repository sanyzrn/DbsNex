import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A recording's shape, as bars, with the part already played in the
/// accent.
///
/// Drawn at once: until the real shape is read — the platform decodes the
/// file for it — a faint, even stand-in holds its place, so nothing below it
/// moves when the real one arrives. With [onSeek], a touch or a drag on it
/// moves playback there; time runs left to right in either language, as on
/// every media bar.
class AudioWaveform extends StatefulWidget {
  const AudioWaveform({
    super.key,
    required this.path,
    required this.progress,
    this.onSeek,
    this.height = 40,
  });
  final String path;
  final double progress;

  /// Where along the recording a touch or a drag landed, from 0 to 1.
  final ValueChanged<double>? onSeek;
  final double height;
  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform> {
  late Future<List<double>> peaks = _load();
  @override
  void didUpdateWidget(AudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) peaks = _load();
  }

  Future<List<double>> _load() async {
    if (!Platform.isAndroid) return [];
    try {
      final stat = await File(widget.path).stat();
      final key = sha256.convert(
        utf8.encode(
          '${widget.path}:${stat.size}:${stat.modified.microsecondsSinceEpoch}',
        ),
      );
      final cache = File(
        p.join((await getTemporaryDirectory()).path, 'waveforms', '$key.json'),
      );
      if (await cache.exists()) {
        return (jsonDecode(await cache.readAsString()) as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
      }
      final values = await const MethodChannel(
        'nex/os_capture',
      ).invokeListMethod<num>('audioWaveform', {'path': widget.path});
      final result = values?.map((v) => v.toDouble()).toList() ?? <double>[];
      if (result.isNotEmpty) {
        await cache.parent.create(recursive: true);
        await cache.writeAsString(jsonEncode(result), flush: true);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// A gentle, fixed rise and fall: the stand-in until the shape is read.
  static final _standIn = [
    for (var i = 0; i < 64; i++)
      0.18 +
          0.22 *
              (0.5 + 0.5 * math.sin(i * 0.55)) *
              (0.6 + 0.4 * math.cos(i * 0.21)),
  ];

  @override
  Widget build(BuildContext context) => FutureBuilder<List<double>>(
    future: peaks,
    builder: (context, snapshot) {
      final scheme = Theme.of(context).colorScheme;
      final values = snapshot.data;
      final real = values != null && values.isNotEmpty;
      final onSeek = widget.onSeek;
      Widget bars = SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _Envelope(
            real ? values : _standIn,
            real ? widget.progress : 0,
            scheme.primary,
            scheme.onSurfaceVariant.withValues(alpha: real ? 0.28 : 0.14),
          ),
        ),
      );
      if (onSeek != null) {
        // Its own name: the builder runs later, when `bars` is this
        // LayoutBuilder, and a child of itself recurses until the stack ends.
        final drawn = bars;
        bars = LayoutBuilder(
          builder: (context, box) {
            void seek(double dx) => onSeek((dx / box.maxWidth).clamp(0.0, 1.0));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seek(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
              child: drawn,
            );
          },
        );
      }
      return ExcludeSemantics(
        child: Directionality(textDirection: TextDirection.ltr, child: bars),
      );
    },
  );
}

class _Envelope extends CustomPainter {
  _Envelope(this.values, this.progress, this.played, this.ahead);
  final List<double> values;
  final double progress;
  final Color played;
  final Color ahead;
  @override
  void paint(Canvas canvas, Size size) {
    final count = math.min(values.length, (size.width / 5).floor());
    if (count <= 0) return;
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final from = i * values.length ~/ count;
      final to = math.max(from + 1, (i + 1) * values.length ~/ count);
      final peak = values.sublist(from, to).reduce(math.max).clamp(0.0, 1.0);
      final height = math.max(3.0, math.sqrt(peak) * size.height);
      paint.color = (i + 0.5) / count <= progress ? played : ahead;
      final x = (i + .5) * size.width / count;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Envelope old) =>
      old.values != values ||
      old.progress != progress ||
      old.played != played ||
      old.ahead != ahead;
}
