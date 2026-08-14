import 'package:nubia_domain/src/entities/cabinet_conversation.dart';
import 'package:nubia_domain/src/entities/conversation_appointment_conversion.dart';
import 'package:nubia_domain/src/entities/message.dart';
import '../messaging/messaging_dto.dart';

class CabinetConversationDto {
  final String id;
  final String patientId;
  final String patientName;
  final String? patientPhone;
  final int unreadCount;
  final String? lastMessageAt;
  final MessageDto? lastMessage;
  final String? lastMessagePreview;
  final String triageFlag;
  final String? orderRef;
  final String? orderStatusLabel;

  const CabinetConversationDto({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.patientPhone,
    required this.unreadCount,
    this.lastMessageAt,
    this.lastMessage,
    this.lastMessagePreview,
    this.triageFlag = 'normal',
    this.orderRef,
    this.orderStatusLabel,
  });

  factory CabinetConversationDto.fromJson(Map<String, dynamic> json) {
    final firstName = json['patient_first_name'] as String? ?? '';
    final lastName = json['patient_last_name'] as String? ?? '';
    final combined = '$firstName $lastName'.trim();
    // #4663 : `patient_name` peut être une chaîne vide (pas `null`) quand le
    // compte patient source n'avait ni prénom ni nom au moment de la
    // création du fil côté API — `?? combined` ne se déclenche jamais sur
    // une chaîne vide, d'où un fallback ultime explicite ('Patient'),
    // symétrique au COALESCE(..., 'Patient') du back.
    final rawName = (json['patient_name'] as String?)?.trim() ?? '';
    final patientName = rawName.isNotEmpty
        ? rawName
        : (combined.isNotEmpty ? combined : 'Patient');
    return CabinetConversationDto(
      id: json['id'] as String,
      patientId: json['patient_id'] as String? ?? '',
      patientName: patientName,
      patientPhone: json['patient_phone'] as String?,
      unreadCount: (json['unread_count'] as num? ?? 0).toInt(),
      lastMessageAt: json['last_message_at'] as String?,
      lastMessage: json['last_message'] == null
          ? null
          : MessageDto.fromJson(json['last_message'] as Map<String, dynamic>),
      lastMessagePreview: json['last_message_preview'] as String?,
      triageFlag: json['triage_flag'] as String? ?? 'normal',
      orderRef: json['order_ref'] as String?,
      orderStatusLabel: json['order_status_label'] as String?,
    );
  }

  CabinetConversation toDomain() => CabinetConversation(
        id: id,
        patientId: patientId,
        patientName: patientName,
        patientPhone: patientPhone,
        unreadCount: unreadCount,
        lastMessageAt:
            lastMessageAt == null ? null : DateTime.parse(lastMessageAt!),
        lastMessage: lastMessage?.toDomain(),
        lastMessagePreview: lastMessagePreview,
        triageFlag: triageFlag == 'urgent'
            ? MessageUrgency.urgent
            : MessageUrgency.normal,
        orderRef: orderRef,
        orderStatusLabel: orderStatusLabel,
      );
}

/// Réponse de `POST /v1/cabinet/conversations/{id}/convert-to-appointment`
/// (#4159/#4160) : `{ appointment_id, status }`.
class ConversationAppointmentConversionDto {
  final String appointmentId;
  final String status;

  const ConversationAppointmentConversionDto({
    required this.appointmentId,
    required this.status,
  });

  factory ConversationAppointmentConversionDto.fromJson(
          Map<String, dynamic> json) =>
      ConversationAppointmentConversionDto(
        appointmentId: json['appointment_id'] as String,
        status: json['status'] as String,
      );

  ConversationAppointmentConversion toDomain() =>
      ConversationAppointmentConversion(
        appointmentId: appointmentId,
        status: status,
      );
}
