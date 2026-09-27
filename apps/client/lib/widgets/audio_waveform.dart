import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioWaveform extends StatefulWidget {
  const AudioWaveform({super.key, required this.path, required this.progress});
  final String path;
  final double progress;
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

  @override
  Widget build(BuildContext context) => FutureBuilder<List<double>>(
    future: peaks,
    builder: (context, snapshot) {
      final values = snapshot.data;
      if (values == null || values.isEmpty) return const SizedBox.shrink();
      return ExcludeSemantics(
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: CustomPaint(
            painter: _Envelope(
              values,
              widget.progress,
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    },
  );
}

class _Envelope extends CustomPainter {
  _Envelope(this.values, this.progress, this.color);
  final List<double> values;
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final count = math.min(values.length, (size.width / 4).floor());
    if (count <= 0) return;
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final from = i * values.length ~/ count;
      final to = (i + 1) * values.length ~/ count;
      final peak = values.sublist(from, to).reduce(math.max).clamp(0.0, 1.0);
      final height = math.max(1.0, math.sqrt(peak) * size.height);
      paint.color = color.withValues(alpha: i / count <= progress ? 1 : .35);
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
      old.values != values || old.progress != progress || old.color != color;
}
