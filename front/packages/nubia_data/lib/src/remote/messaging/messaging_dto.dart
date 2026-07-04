import 'package:nubia_domain/src/entities/message.dart';

class ConversationDto {
  final String id;
  final String cabinetId;
  final String cabinetName;
  final int unreadCount;
  final MessageDto? lastMessage;

  /// `last_message_at` du contrat `GET /v1/conversations` — horodatage ISO du
  /// dernier message. Le contrat liste ne renvoie pas l'aperçu texte.
  final String? lastMessageAt;

  const ConversationDto({
    required this.id,
    required this.cabinetId,
    required this.cabinetName,
    required this.unreadCount,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory ConversationDto.fromJson(Map<String, dynamic> json) =>
      ConversationDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        cabinetName: json['cabinet_name'] as String,
        unreadCount: (json['unread_count'] as num).toInt(),
        lastMessage: json['last_message'] == null
            ? null
            : MessageDto.fromJson(json['last_message'] as Map<String, dynamic>),
        lastMessageAt: json['last_message_at'] as String?,
      );

  Conversation toDomain() => Conversation(
        id: id,
        cabinetId: cabinetId,
        cabinetName: cabinetName,
        unreadCount: unreadCount,
        lastMessage: lastMessage?.toDomain(),
        lastMessageAt:
            lastMessageAt == null ? null : DateTime.parse(lastMessageAt!),
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

  /// Contrat réel : {id, body, sender, created_at, read_at} — pas de
  /// conversation_id (injecté par l'appelant), `body`≠`text`, `created_at`≠
  /// `sent_at`. Reste rétro-compatible avec l'ancienne forme.
  factory MessageDto.fromJson(
    Map<String, dynamic> json, {
    String conversationId = '',
  }) =>
      MessageDto(
        id: json['id'] as String,
        conversationId: (json['conversation_id'] as String?) ?? conversationId,
        sender: json['sender'] as String,
        text: (json['text'] as String?) ?? (json['body'] as String?),
        attachmentIds: (json['attachment_ids'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        urgency: json['urgency'] as String? ?? 'normal',
        sentAt: (json['sent_at'] as String?) ?? (json['created_at'] as String),
        readAt: json['read_at'] as String?,
      );

  Message toDomain() => Message(
        id: id,
        conversationId: conversationId,
        sender:
            sender == 'patient' ? MessageSender.patient : MessageSender.cabinet,
        text: text,
        attachmentIds: attachmentIds,
        urgency:
            urgency == 'urgent' ? MessageUrgency.urgent : MessageUrgency.normal,
        sentAt: DateTime.parse(sentAt),
        readAt: readAt == null ? null : DateTime.parse(readAt!),
      );
}
