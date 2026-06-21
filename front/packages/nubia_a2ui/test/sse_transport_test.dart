import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';

/// Mock SSE client that emits exactly 2 events then closes.
class _TwoEventSseClient implements SseHttpClient {
  Uri? capturedUri;
  Map<String, String>? capturedHeaders;

  @override
  Stream<String> getLines(Uri uri, Map<String, String> headers) async* {
    capturedUri = uri;
    capturedHeaders = headers;
    yield 'data: {"type":"createSurface","surfaceId":"s1"}';
    yield '';
    yield 'data: {"type":"deleteSurface","surfaceId":"s1"}';
    yield '';
  }
}

void main() {
  test('SseTransport émet 2 événements parsés depuis un HttpClient mocké',
      () async {
    final client = _TwoEventSseClient();
    final transport = SseTransport(client, 'test-token');

    final messages = await transport
        .connect(Uri.parse('http://localhost/v1/a2ui/stream'))
        .take(2)
        .toList();

    expect(messages, hasLength(2));
    expect(messages[0], isA<CreateSurface>());
    expect(messages[1], isA<DeleteSurface>());
  });

  test('SseTransport injecte le header Authorization Bearer', () async {
    final client = _TwoEventSseClient();
    final transport = SseTransport(client, 'my-secret-token');

    await transport
        .connect(Uri.parse('http://localhost/v1/a2ui/stream'))
        .take(2)
        .drain<void>();

    expect(client.capturedHeaders?['Authorization'], 'Bearer my-secret-token');
  });
}
