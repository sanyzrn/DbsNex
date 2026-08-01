// Phase 0 of the offline-AI roadmap (../../docs/09-ai.md). A standalone app,
// not part of Nex itself — see this project's pubspec.yaml for why.
//
// Run on a real Android device (an emulator gives no useful timing numbers):
//   flutter run -d <device-id>
//
// One-time setup before it can load a model — see:
//   - android/app/libs/README.md   (the native llama.cpp library)
//   - README.md                    (getting a .gguf model onto the device)
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:nex_ai/nex_ai.dart';

void main() => runApp(const _BenchApp());

class _BenchApp extends StatelessWidget {
  const _BenchApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nex — local AI bench',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
    home: const _BenchScreen(),
  );
}

/// A handful of prompts spanning the "everyday, short" requests the offline
/// AI is actually meant to handle (docs conversation, phase-0 scoping) —
/// writing help, translation, light arithmetic, summarization. The point is
/// comparable numbers across request shapes, not any one of them.
const _presetPrompts = <String, String>{
  'Reschedule reply':
      'Write a two-sentence reply to a coworker asking to reschedule '
      "tomorrow's meeting to Thursday.",
  'Translate to Persian':
      "Translate to Persian: 'Please send the invoice by Friday.'",
  'Percentage': 'What is 17% of 850? Show the calculation briefly.',
  'Summarize':
      'Summarize in one sentence: "The quarterly report showed revenue up '
      '12% year over year, driven mainly by the new subscription tier, '
      'while support ticket volume grew faster than the team could hire '
      'for, prompting a hiring freeze review next month."',
};

class _BenchScreen extends StatefulWidget {
  const _BenchScreen();

  @override
  State<_BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<_BenchScreen> {
  String? _modelPath;
  NexLocalBenchEngine? _engine;
  bool _busy = false;
  final _log = StringBuffer();

  Future<void> _pickModel() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'GGUF model', extensions: ['gguf']),
      ],
    );
    if (file == null) return;
    setState(() => _modelPath = file.path);
  }

  Future<void> _loadModel() async {
    final path = _modelPath;
    if (path == null) return;
    setState(() {
      _busy = true;
      _log.writeln('Loading $path ...');
    });
    try {
      final stopwatch = Stopwatch()..start();
      final engine = await NexLocalBenchEngine.load(modelPath: path);
      stopwatch.stop();
      setState(() {
        _engine = engine;
        _log.writeln('Loaded in ${stopwatch.elapsedMilliseconds}ms.\n');
      });
    } catch (e) {
      setState(() => _log.writeln('Load failed: $e\n'));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _run(String label, String prompt) async {
    final engine = _engine;
    if (engine == null) return;
    setState(() {
      _busy = true;
      _log.writeln('--- $label ---');
    });
    try {
      final result = await engine.ask(prompt);
      setState(() {
        _log
          ..writeln(result)
          ..writeln(result.text)
          ..writeln();
      });
    } catch (e) {
      setState(() => _log.writeln('Failed: $e\n'));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _runAllPresets() async {
    for (final entry in _presetPrompts.entries) {
      await _run(entry.key, entry.value);
    }
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Phase 0 targets Android only — see ../../docs/09-ai.md.',
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nex — local AI bench (dev only)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _modelPath ?? 'No model selected',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _pickModel,
                  child: const Text('Pick .gguf'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: (_busy || _modelPath == null)
                        ? null
                        : _loadModel,
                    child: Text(_engine == null ? 'Load model' : 'Reload'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_busy || _engine == null)
                        ? null
                        : _runAllPresets,
                    child: const Text('Run all presets'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _presetPrompts.entries)
                  ActionChip(
                    label: Text(entry.key),
                    onPressed: (_busy || _engine == null)
                        ? null
                        : () => _run(entry.key, entry.value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _log.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
