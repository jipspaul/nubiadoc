import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/messaging/messaging_dto.dart';

class MessagingApi {
  final Dio _dio;

  MessagingApi(ApiClient client) : _dio = client.dio;

  Future<List<ConversationDto>> getConversations() async {
    // GET /v1/conversations → { data: [...] }
    final response = await _dio.get<Map<String, dynamic>>('/conversations');
    final data = (response.data?['data'] as List<dynamic>? ?? []);
    return data
        .map((e) => ConversationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/conversations/:id/messages — récupère TOUT le fil.
  ///
  /// L'API pagine en avant (`created_at ASC`, curseur `page.next_cursor`) :
  /// la 1re page ne renvoie que les messages les plus ANCIENS. Un unique
  /// appel sans suivre `next_cursor` laissait donc les réponses récentes du
  /// praticien et les envois du patient invisibles dès qu'un fil dépasse la
  /// taille de page (#3848). On suit le curseur jusqu'à épuisement, avec
  /// `limit=100` (max serveur) pour minimiser les allers-retours.
  Future<List<MessageDto>> getMessages(String conversationId) async {
    final messages = <MessageDto>[];
    String? cursor;
    while (true) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/conversations/$conversationId/messages',
        queryParameters: {
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final data = (response.data?['data'] as List<dynamic>? ?? []);
      messages.addAll(
        data.map(
          (e) => MessageDto.fromJson(
            e as Map<String, dynamic>,
            conversationId: conversationId,
          ),
        ),
      );
      cursor = response.data?['page']?['next_cursor'] as String?;
      if (cursor == null) break;
    }
    return messages;
  }

  Future<MessageDto> send({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      // Le back attend le champ `body` (SendMessageBody), pas `text` → 422 sinon.
      data: {
        'body': text,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      },
    );
    return MessageDto.fromJson(response.data!);
  }

  Future<void> markRead(String conversationId) async {
    // Route back = POST (pas PATCH) → 405 sinon ; et elle attend un corps JSON
    // (`Json<MarkReadBody>`) → 415 sans corps. On envoie un objet vide.
    await _dio.post<void>(
      '/conversations/$conversationId/read',
      data: <String, dynamic>{},
    );
  }
}
