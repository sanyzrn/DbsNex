import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nex_client/platform/link_reader.dart';

/// A link preview reads at most its cap off the wire (SEC-03).
void main() {
  test('readCapped stops at the limit and cancels the stream', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final read = readCapped(controller.stream, 10);
    controller.add(List.filled(6, 1));
    controller.add(List.filled(6, 2));
    final bytes = await read;
    expect(bytes, hasLength(10));
    expect(cancelled, isTrue);
  });

  test('previews fetch only public web pages (SEC-04)', () {
    for (final url in [
      'https://example.com/a',
      'http://news.example.org',
      'https://8.8.8.8/',
      'https://[2001:4860:4860::8888]/',
    ]) {
      expect(isPublicWebUrl(Uri.parse(url)), isTrue, reason: url);
    }
    for (final url in [
      'http://127.0.0.1:8080/metrics',
      'http://localhost/',
      'http://10.0.2.2:3000/',
      'http://192.168.1.1/',
      'http://172.16.4.2/',
      'http://100.64.0.1/',
      'http://169.254.169.254/latest/meta-data',
      'http://0.0.0.0/',
      'http://[::1]/',
      'http://[fd00::1]/',
      'http://[::ffff:192.168.1.1]/',
      'http://printer.local/',
      'ftp://example.com/file',
      'file:///etc/hosts',
    ]) {
      expect(isPublicWebUrl(Uri.parse(url)), isFalse, reason: url);
    }
  });

  test(
    'a public page that redirects to a private address is not followed',
    () async {
      final client = _RedirectClient('http://127.0.0.1:8080/secret');
      final preview = await LinkReader(client: client).read('https://e.x/');
      expect(preview.isEmpty, isTrue);
      expect(client.requested, ['https://e.x/']);
    },
  );

  test('an ordinary redirect is followed to the page', () async {
    final client = _RedirectClient('https://www.e.x/home');
    final preview = await LinkReader(client: client).read('https://e.x/');
    expect(preview.title, 'Home');
    expect(client.requested, ['https://e.x/', 'https://www.e.x/home']);
  });

  test('an endless HTML page still yields a preview', () async {
    final client = _EndlessClient();
    final preview = await LinkReader(client: client).read('https://e.x/');
    expect(preview.title, 'Hi');
  });
}

class _EndlessClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> body() async* {
      yield '<html><head><title>Hi</title></head><body>'.codeUnits;
      while (true) {
        yield List.filled(64 * 1024, 0x61);
      }
    }

    return http.StreamedResponse(
      body(),
      200,
      headers: {'content-type': 'text/html'},
    );
  }
}

class _RedirectClient extends http.BaseClient {
  _RedirectClient(this.location);

  final String location;
  final requested = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url.toString());
    if (requested.length == 1) {
      return http.StreamedResponse(
        const Stream.empty(),
        302,
        headers: {'location': location},
        isRedirect: true,
      );
    }
    return http.StreamedResponse(
      Stream.value('<html><head><title>Home</title></head>'.codeUnits),
      200,
      headers: {'content-type': 'text/html'},
    );
  }
}
