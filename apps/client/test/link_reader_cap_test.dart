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
