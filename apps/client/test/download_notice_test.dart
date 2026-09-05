import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/download_notice.dart';

/// The native half is a foreground service, and what is testable here is the
/// Dart half: what it asks for, and — the part the caller depends on — that
/// "there is no service here" comes back as an answer rather than as an
/// exception, because that answer is what makes the app post its own
/// notification instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final seen = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      seen.add(call);
      return handler(call);
    });
  }

  setUp(seen.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks for the notification by title and whole percent', () async {
    answer((_) async => true);

    expect(
      await NexDownloadNotice.show(title: 'Downloading Nex', percent: 42),
      isTrue,
    );
    expect(seen.single.method, 'downloadNotice');
    expect(seen.single.arguments, {
      'title': 'Downloading Nex',
      'percent': 42,
    });
  });

  test('taking it down is its own call, so the service can stop', () async {
    // Not a zero-percent update: the notification going away is the service
    // stopping, and the service stopping is the process being allowed to be
    // suspended again. Leaving it running after the download would be a
    // permanent entry in the shade for nothing.
    answer((_) async => true);

    expect(await NexDownloadNotice.hide(), isTrue);
    expect(seen.single.method, 'stopDownloadNotice');
  });

  test('a platform with no service says so instead of throwing', () async {
    // Windows, where nothing registers this channel — and where nothing
    // suspends the process either, so an ordinary notification is all this
    // ever needed to be. The false is what tells the app to post one.
    expect(await NexDownloadNotice.show(title: 'x', percent: 1), isFalse);
    expect(await NexDownloadNotice.hide(), isFalse);
  });

  test('a start Android refused is the old behaviour, not a crash', () async {
    // Starting a foreground service from the background throws on Android 12
    // and later. The native side catches it and answers false; a download
    // that cannot keep the process alive still downloads while the app is
    // open, which is where it was before any of this.
    answer((_) async => false);
    expect(await NexDownloadNotice.show(title: 'x', percent: 1), isFalse);

    answer((_) async => throw PlatformException(code: 'error'));
    expect(await NexDownloadNotice.show(title: 'x', percent: 1), isFalse);
  });
}
