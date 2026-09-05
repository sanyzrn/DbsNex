import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/share_window.dart';

/// The native half is a second Activity with a translucent theme. What is
/// testable here is the protocol: the app has to know which kind of window it
/// is *before* it paints anything, and it has to find out whether the window
/// really closed before it decides that a message has been delivered.
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

  test('the silent window says so, and the ordinary one does not', () async {
    answer((_) async => true);
    expect(await NexShareWindow.isSilent(), isTrue);
    expect(seen.single.method, 'isShareWindow');

    answer((_) async => false);
    expect(await NexShareWindow.isSilent(), isFalse);
  });

  test('a platform with no share window is not one', () async {
    // No handler at all — Windows, where nothing registers this channel and
    // every launch is the app itself. The false is what lets the bootstrap
    // host go on and draw something.
    expect(await NexShareWindow.isSilent(), isFalse);
    expect(await NexShareWindow.done('Saved to Nex.'), isFalse);
  });

  test('the closing message carries the text and reports the close', () async {
    // The answer is load-bearing rather than decorative: the caller only
    // treats a refusal as delivered when the window actually went, because a
    // window that stayed is the ordinary app, and the timeline there still
    // owes the person the message.
    answer((_) async => true);

    expect(await NexShareWindow.done('Saved to Nex.'), isTrue);
    expect(seen.single.method, 'shareDone');
    expect(seen.single.arguments, {'message': 'Saved to Nex.'});
  });

  test('a window that would not close says false, not nothing', () async {
    answer((_) async => false);
    expect(await NexShareWindow.done('Saved to Nex.'), isFalse);

    answer((_) async => throw PlatformException(code: 'error'));
    expect(await NexShareWindow.done('Saved to Nex.'), isFalse);
  });
}
