import 'package:nubia_domain/src/entities/cabinet_conversation.dart';
import '../messaging/messaging_dto.dart';

class CabinetConversationDto {
  final String id;
  final String patientId;
  final String patientName;
  final int unreadCount;
  final String? lastMessageAt;
  final MessageDto? lastMessage;
  final String? lastMessagePreview;

  const CabinetConversationDto({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.unreadCount,
    this.lastMessageAt,
    this.lastMessage,
    this.lastMessagePreview,
  });

  factory CabinetConversationDto.fromJson(Map<String, dynamic> json) {
    final firstName = json['patient_first_name'] as String? ?? '';
    final lastName = json['patient_last_name'] as String? ?? '';
    final combined = '$firstName $lastName'.trim();
    return CabinetConversationDto(
      id: json['id'] as String,
      patientId: json['patient_id'] as String? ?? '',
      patientName: json['patient_name'] as String? ??
          (combined.isNotEmpty ? combined : ''),
      unreadCount: (json['unread_count'] as num? ?? 0).toInt(),
      lastMessageAt: json['last_message_at'] as String?,
      lastMessage: json['last_message'] == null
          ? null
          : MessageDto.fromJson(json['last_message'] as Map<String, dynamic>),
      lastMessagePreview: json['last_message_preview'] as String?,
    );
  }

  CabinetConversation toDomain() => CabinetConversation(
        id: id,
        patientId: patientId,
        patientName: patientName,
        unreadCount: unreadCount,
        lastMessageAt:
            lastMessageAt == null ? null : DateTime.parse(lastMessageAt!),
        lastMessage: lastMessage?.toDomain(),
        lastMessagePreview: lastMessagePreview,
      );
}
