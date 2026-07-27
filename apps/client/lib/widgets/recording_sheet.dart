import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:record/record.dart';
import '../l10n/app_localizations.dart';

class RecordingSheet extends StatefulWidget {
  const RecordingSheet({super.key, required this.recorder});
  final AudioRecorder recorder;
  @override
  State<RecordingSheet> createState() => _RecordingSheetState();
}

class _RecordingSheetState extends State<RecordingSheet> {
  final watch = Stopwatch()..start();
  Timer? timer;
  StreamSubscription<Amplitude>? amplitudeSub;
  double amplitude = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
    amplitudeSub = widget.recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((value) {
      if (mounted) setState(() => amplitude = ((value.current + 60) / 60).clamp(0, 1));
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    amplitudeSub?.cancel();
    watch.stop();
    super.dispose();
  }

  String get elapsed {
    final minutes = watch.elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = watch.elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = 72 + math.max(0, amplitude * 18);
    return PopScope(
      canPop: true,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : NexMotion.fast,
            width: size.toDouble(),
            height: size.toDouble(),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            child: IconButton(
              tooltip: l10n.stopRecording,
              color: Theme.of(context).colorScheme.surface,
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.stop, size: 32),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, label: l10n.recordingElapsed(elapsed),
            child: Text(elapsed, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.discard)),
        ]),
      ),
    );
  }
}