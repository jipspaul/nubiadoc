import 'package:nubia_domain/src/entities/message.dart';

class ConversationDto {
  final String id;
  final String cabinetId;
  final String cabinetName;
  final int unreadCount;
  final MessageDto? lastMessage;

  const ConversationDto({
    required this.id,
    required this.cabinetId,
    required this.cabinetName,
    required this.unreadCount,
    this.lastMessage,
  });

  factory ConversationDto.fromJson(Map<String, dynamic> json) =>
      ConversationDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        cabinetName: json['cabinet_name'] as String,
        unreadCount: (json['unread_count'] as num).toInt(),
        lastMessage: json['last_message'] == null
            ? null
            : MessageDto.fromJson(
                json['last_message'] as Map<String, dynamic>),
      );

  Conversation toDomain() => Conversation(
        id: id,
        cabinetId: cabinetId,
        cabinetName: cabinetName,
        unreadCount: unreadCount,
        lastMessage: lastMessage?.toDomain(),
      );
}

class MessageDto {
  final String id;
  final String conversationId;
  final String sender;
  final String? text;
  final List<String> attachmentIds;
  final String urgency;
  final String sentAt;
  final String? readAt;

  const MessageDto({
    required this.id,
    required this.conversationId,
    required this.sender,
    this.text,
    required this.attachmentIds,
    required this.urgency,
    required this.sentAt,
    this.readAt,
  });

  factory MessageDto.fromJson(Map<String, dynamic> json) => MessageDto(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        sender: json['sender'] as String,
        text: json['text'] as String?,
        attachmentIds: (json['attachment_ids'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        urgency: json['urgency'] as String? ?? 'normal',
        sentAt: json['sent_at'] as String,
        readAt: json['read_at'] as String?,
      );

  Message toDomain() => Message(
        id: id,
        conversationId: conversationId,
        sender: sender == 'cabinet' ? MessageSender.cabinet : MessageSender.patient,
        text: text,
        attachmentIds: attachmentIds,
        urgency: urgency == 'urgent' ? MessageUrgency.urgent : MessageUrgency.normal,
        sentAt: DateTime.parse(sentAt),
        readAt: readAt == null ? null : DateTime.parse(readAt!),
      );
}
