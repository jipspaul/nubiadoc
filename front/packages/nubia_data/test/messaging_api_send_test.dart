import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/messaging/messaging_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #6739 : POST /v1/conversations/:id/messages ne renvoie que
  // `{message_id}` (SendMessageResponse côté API), jamais le message complet.
  // `MessageDto.fromJson` levait alors sur `id`/`sender`/`created_at`, le
  // repository transformait ça en ParseFailure, et le bloc l'avalait sans
  // message : la bulle envoyée n'apparaissait qu'après réouverture du fil.
  group('MessagingApi.send', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    test('réponse courte {message_id} → message utilisable, pas d\'exception',
        () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/conversations/conv-1/messages',
          data: {'body': 'Bonjour'},
        ),
      ).thenAnswer(
        (_) async => Response(
          data: {'message_id': 'msg-42'},
          requestOptions: RequestOptions(path: ''),
        ),
      );

      final dto = await MessagingApi(apiClient)
          .send(conversationId: 'conv-1', text: 'Bonjour');

      expect(dto.id, 'msg-42');
      expect(dto.conversationId, 'conv-1');
      expect(dto.text, 'Bonjour');
      expect(dto.sender, 'patient');
      // Horodatage renseigné : la bulle se place au bon endroit du fil.
      expect(DateTime.parse(dto.sentAt).isUtc, isTrue);
    });

    test('réponse complète → parsée telle quelle', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/conversations/conv-1/messages',
          data: {'body': 'Salut'},
        ),
      ).thenAnswer(
        (_) async => Response(
          data: {
            'id': 'msg-7',
            'sender': 'cabinet',
            'body': 'Salut',
            'created_at': '2026-09-08T10:00:00Z',
          },
          requestOptions: RequestOptions(path: ''),
        ),
      );

      final dto = await MessagingApi(apiClient)
          .send(conversationId: 'conv-1', text: 'Salut');

      expect(dto.id, 'msg-7');
      expect(dto.sender, 'cabinet');
      expect(dto.conversationId, 'conv-1');
    });
  });
}
