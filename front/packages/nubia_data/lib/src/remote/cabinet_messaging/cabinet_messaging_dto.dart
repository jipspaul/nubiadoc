import 'package:nubia_domain/src/entities/cabinet_conversation.dart';
import '../messaging/messaging_dto.dart';

class CabinetConversationDto {
  final String id;
  final String patientId;
  final String patientName;
  final int unreadCount;
  final MessageDto? lastMessage;

  const CabinetConversationDto({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.unreadCount,
    this.lastMessage,
  });

  factory CabinetConversationDto.fromJson(Map<String, dynamic> json) =>
      CabinetConversationDto(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String,
        unreadCount: (json['unread_count'] as num).toInt(),
        lastMessage: json['last_message'] == null
            ? null
            : MessageDto.fromJson(
                json['last_message'] as Map<String, dynamic>),
      );

  CabinetConversation toDomain() => CabinetConversation(
        id: id,
        patientId: patientId,
        patientName: patientName,
        unreadCount: unreadCount,
        lastMessage: lastMessage?.toDomain(),
      );
}
