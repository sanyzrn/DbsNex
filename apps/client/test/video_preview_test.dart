import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/video_preview.dart';

/// The native half of this is Android's own frame retriever, reached over the
/// channel the share intent already uses. What is testable here is the Dart
/// half: what it asks for, and that every way of having no cover comes back
/// as null rather than as an exception somebody has to catch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nex/os_capture');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger;

  MethodCall? seen;

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      seen = call;
      return handler(call);
    });
  }

  setUp(() => seen = null);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks the platform for a frame, bounded by width', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    answer((_) async => bytes);

    expect(await NexVideoPreview.poster('/x/clip.mp4'), bytes);
    expect(seen?.method, 'videoPreview');
    // The width is the point of the call's shape: a 4K frame at its own size
    // is thirty-three megabytes of bitmap for a thumbnail.
    expect(seen?.arguments, {'path': '/x/clip.mp4', 'width': 1080});
  });

  test('a platform with no retriever is an absence, not a failure', () async {
    // No handler registered at all — which is Windows, where nothing sets the
    // channel up. The caller shows the file row it always showed.
    expect(await NexVideoPreview.poster('/x/clip.mp4'), isNull);
  });

  test('a file no frame can be pulled out of is null too', () async {
    // Not a video, a codec this device has no decoder for, a download that
    // stopped halfway — the native side answers null for some of them and
    // throws for the rest.
    answer((_) async => throw PlatformException(code: 'error'));
    expect(await NexVideoPreview.poster('/x/clip.mp4'), isNull);

    answer((_) async => null);
    expect(await NexVideoPreview.poster('/x/clip.mp4'), isNull);
  });

  test('an empty path never reaches the platform', () async {
    answer((_) async => Uint8List(0));
    expect(await NexVideoPreview.poster(''), isNull);
    expect(seen, isNull);
  });
}
