import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'cabinet_messaging_dto.dart';
import '../messaging/messaging_dto.dart';

class CabinetMessagingApi {
  final Dio _dio;

  CabinetMessagingApi(ApiClient client) : _dio = client.dio;

  Future<List<CabinetConversationDto>> getConversations() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/conversations');
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((e) => CabinetConversationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MessageDto>> getMessages(String conversationId) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/cabinet/conversations/$conversationId/messages');
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((e) => MessageDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MessageDto> send({
    required String conversationId,
    required String text,
    List<String> attachmentIds = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/conversations/$conversationId/messages',
      data: {
        'text': text,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      },
    );
    return MessageDto.fromJson(response.data!);
  }
}
