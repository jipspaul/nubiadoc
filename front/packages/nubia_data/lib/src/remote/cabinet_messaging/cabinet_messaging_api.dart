import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'cabinet_messaging_dto.dart';
import '../messaging/messaging_dto.dart';

class CabinetMessagingApi {
  final Dio _dio;

  /// Espace API : `/cabinet` (praticien/secrétariat) ou `/pharmacy`
  /// (app pharmacie — mêmes formes JSON, lot B6).
  final String basePath;

  CabinetMessagingApi(ApiClient client, {this.basePath = '/cabinet'})
      : _dio = client.dio;

  Future<List<CabinetConversationDto>> getConversations() async {
    final response =
        await _dio.get<Map<String, dynamic>>('$basePath/conversations');
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((e) => CabinetConversationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MessageDto>> getMessages(String conversationId) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '$basePath/conversations/$conversationId/messages');
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
      '$basePath/conversations/$conversationId/messages',
      // Le back attend le champ `body` (SendCabinetMessageBody), pas `text` →
      // 422 sinon (identique au fil patient).
      data: {
        'body': text,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      },
    );
    return MessageDto.fromJson(response.data!);
  }

  /// `POST $basePath/conversations/{id}/convert-to-appointment` (#4159/#4160).
  Future<ConversationAppointmentConversionDto> convertToAppointment({
    required String conversationId,
    required String slotId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$basePath/conversations/$conversationId/convert-to-appointment',
      data: {'slot_id': slotId},
    );
    return ConversationAppointmentConversionDto.fromJson(response.data!);
  }
}
