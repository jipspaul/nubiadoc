import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/messaging/messaging_dto.dart';

@injectable
class MessagingApi {
  final Dio _dio;

  MessagingApi(ApiClient client) : _dio = client.dio;

  Future<List<ConversationDto>> getConversations() async {
    final response = await _dio.get<List<dynamic>>('/conversations');
    return (response.data!)
        .map((e) => ConversationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MessageDto>> getMessages(String conversationId) async {
    final response =
        await _dio.get<List<dynamic>>('/conversations/$conversationId/messages');
    return (response.data!)
        .map((e) => MessageDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MessageDto> send({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      data: {
        'text': text,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      },
    );
    return MessageDto.fromJson(response.data!);
  }

  Future<void> markRead(String conversationId) async {
    await _dio.patch<void>('/conversations/$conversationId/read');
  }
}
