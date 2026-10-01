import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/update_service.dart';

import 'support/nex_harness.dart';

class _Downloading extends UpdateService {
  _Downloading({required super.preferences, required this.downloading});

  final bool downloading;

  @override
  bool get isDownloading => downloading;

  @override
  Future<void> maybeCheck({bool force = false}) async {}
}

/// Back on the home screen with an update downloading puts Nex in the
/// background rather than closing it: the download runs in the app's engine,
/// and closing the window stopped it.
void main() {
  late NexTestHarness harness;
  late List<String> calls;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_back_download_');
    calls = [];
  });

  tearDown(() => harness.dispose());

  Future<void> pressBack(
    WidgetTester tester, {
    required bool downloading,
  }) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('nex/os_capture'), (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'moveTaskToBack' ? true : null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('nex/os_capture'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final updates = _Downloading(
      preferences: harness.preferences,
      downloading: downloading,
    );
    await tester.pumpWidget(harness.app(updates: updates));
    await tester.pumpAndSettle();
    calls.clear();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('while downloading, Back goes to the background', (tester) async {
    await pressBack(tester, downloading: true);
    expect(calls, contains('moveTaskToBack'));
    expect(calls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets('otherwise Back closes the app as it always did', (tester) async {
    await pressBack(tester, downloading: false);
    expect(calls, isNot(contains('moveTaskToBack')));
    expect(calls, contains('SystemNavigator.pop'));
  });
}
