import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/crash_reporter.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/nex_harness.dart';

/// 2.1.10: failures the app handles itself — a video that could not be
/// analysed, a refused AI request — are written to the local diagnostics log,
/// by kind and code and never by address, reply or note text.
class _SupportDir extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _SupportDir(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('nex_failure_log_');
    PathProviderPlatform.instance = _SupportDir(support.path);
  });

  tearDown(() {
    nexVideoClientForTest = null;
    NexAiFailureLog.sink = null;
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  Future<String> logText() async {
    await NexCrashLog.failed('flush', 'barrier');
    final file = File('${support.path}/crash_log.txt');
    return file.existsSync() ? file.readAsStringSync() : '';
  }

  test('a video that could not be analysed says why in the log', () async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
    );
    final note = (await h.services.captureLink(
      'https://youtu.be/dQw4w9WgXcQ',
    ))!;
    nexVideoClientForTest = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {'message': 'Resource has been exhausted.'},
        }),
        429,
      ),
    );
    final result = await h.services.analyzeVideo(note.id);
    expect(result.failure, NexVideoFailure.limit);
    final text = await logText();
    expect(text, contains('Failed video.analysis (limit · HTTP 429)'));
    expect(text, isNot(contains('dQw4w9WgXcQ')));
    expect(text, isNot(contains('exhausted')));
  });

  test('handled errors carry a fixed detail word and nothing else', () async {
    await NexCrashLog.handled('x', const FormatException('private words'));
    final text = await logText();
    expect(text, contains('Handled x: FormatException'));
    expect(text, isNot(contains('private words')));
  });
}
