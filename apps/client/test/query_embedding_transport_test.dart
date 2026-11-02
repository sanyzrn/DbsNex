import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nex_ai/cloud.dart';

class _Transport extends http.BaseClient {
  final arrived = Completer<void>();
  var aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.AbortableRequest) {
      final pending = Completer<http.StreamedResponse>();
      request.abortTrigger!.then((_) {
        aborted = true;
        pending.completeError(http.RequestAbortedException(request.url));
      });
      arrived.complete();
      return pending.future;
    }
    return Future.value(
      http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'embedding': {
                'values': [1.0, 0.0],
              },
              'data': [
                {
                  'embedding': [1.0, 0.0],
                },
              ],
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}

void main() {
  for (final provider in [AiProvider.openai, AiProvider.gemini]) {
    test(
      'cancelling $provider query aborts transport and preserves indexing',
      () async {
        final client = _Transport();
        final adapter = CloudAIAdapter(
          config: AiProviderConfig(provider: provider, apiKey: 'test'),
          client: client,
        );
        addTearDown(adapter.close);
        addTearDown(client.close);
        final query = adapter.embedQuery('still typing')!;
        final failed = expectLater(
          query,
          throwsA(isA<http.RequestAbortedException>()),
        );
        await client.arrived.future;
        adapter.cancelQueryEmbedding();
        await failed;
        expect(client.aborted, isTrue);
        final savedNote = await adapter.embed('saved note')!;
        expect(savedNote.values, [1.0, 0.0]);
      },
    );
  }
}
