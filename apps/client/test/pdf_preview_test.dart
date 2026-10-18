import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/pdf_preview.dart';

/// The native half of this is Android's own PDF renderer, reached over the
/// channel the share intent already uses. What is testable here is the Dart
/// half: what it asks for, and that every way of having no preview comes back
/// as null rather than as an exception somebody has to catch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MethodCall? seen;

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      seen = call;
      return handler(call);
    });
  }

  setUp(() => seen = null);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks the platform for the first page at a given width', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    answer((_) async => bytes);

    expect(await NexPdfPreview.firstPage('/x/report.pdf'), bytes);
    expect(seen?.method, 'pdfPreview');
    // The height cap is the point of the call's shape: only the band the
    // sheet shows is drawn, so a full page's bitmap is never allocated.
    expect(seen?.arguments, {
      'path': '/x/report.pdf',
      'width': 1200,
      'maxHeight': 960,
    });
  });

  test('a platform with no renderer is an absence, not a failure', () async {
    // No handler registered at all — which is Windows, where nothing sets the
    // channel up. The caller shows the file row it always showed.
    expect(await NexPdfPreview.firstPage('/x/report.pdf'), isNull);
  });

  test('a file the renderer will not open is null too', () async {
    // Not a PDF, encrypted, empty — the native side answers null for all of
    // them, and throws for the rest.
    answer((_) async => throw PlatformException(code: 'error'));
    expect(await NexPdfPreview.firstPage('/x/report.pdf'), isNull);

    answer((_) async => null);
    expect(await NexPdfPreview.firstPage('/x/report.pdf'), isNull);
  });

  test(
    'complete-page reader requests one page and validates its page count',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      answer((_) async => {'bytes': bytes, 'pageCount': 7});
      final page = await NexPdfPreview.page('/x/report.pdf', index: 2);
      expect(page?.bytes, bytes);
      expect(page?.pageCount, 7);
      expect(seen?.method, 'pdfPage');
      expect(seen?.arguments, {
        'path': '/x/report.pdf',
        'index': 2,
        'width': 1400,
      });
      answer((_) async => {'bytes': bytes, 'pageCount': 2});
      expect(await NexPdfPreview.page('/x/report.pdf', index: 2), isNull);
    },
  );

  test(
    'complete-page reader treats absent, empty and invalid pages as unavailable',
    () async {
      expect(await NexPdfPreview.page('/x/report.pdf'), isNull);
      answer((_) async => throw PlatformException(code: 'invalid_pdf'));
      expect(await NexPdfPreview.page('/x/report.pdf'), isNull);
      answer((_) async => {'bytes': Uint8List(0), 'pageCount': 1});
      expect(await NexPdfPreview.page('/x/report.pdf'), isNull);
      seen = null;
      expect(await NexPdfPreview.page('', index: 0), isNull);
      expect(await NexPdfPreview.page('/x/report.pdf', index: -1), isNull);
      expect(seen, isNull);
    },
  );

  test('an empty path never reaches the platform', () async {
    answer((_) async => Uint8List(0));
    expect(await NexPdfPreview.firstPage(''), isNull);
    expect(seen, isNull);
  });
}
