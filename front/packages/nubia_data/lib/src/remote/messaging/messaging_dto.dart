import 'package:nubia_domain/src/entities/message.dart';

import '../documents/document_dto.dart';

class ConversationDto {
  final String id;
  final String cabinetId;
  final String cabinetName;
  final int unreadCount;
  final MessageDto? lastMessage;

  /// `last_message_at` du contrat `GET /v1/conversations` — horodatage ISO du
  /// dernier message.
  final String? lastMessageAt;

  /// `last_message_preview` — aperçu du dernier message, tronqué côté serveur.
  final String? lastMessagePreview;

  /// `type` — discriminant explicite du destinataire (`"cabinet"` ou
  /// `"pharmacy"`, cf. `ConversationItem` côté API) ; absent des anciens
  /// payloads, on retombe alors sur `"cabinet"`.
  final String type;

  const ConversationDto({
    required this.id,
    required this.cabinetId,
    required this.cabinetName,
    required this.unreadCount,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.type = 'cabinet',
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
        lastMessagePreview: json['last_message_preview'] as String?,
        type: json['type'] as String? ?? 'cabinet',
      );

  Conversation toDomain() => Conversation(
        id: id,
        cabinetId: cabinetId,
        cabinetName: cabinetName,
        unreadCount: unreadCount,
        lastMessage: lastMessage?.toDomain(),
        lastMessageAt:
            lastMessageAt == null ? null : DateTime.parse(lastMessageAt!),
        lastMessagePreview: lastMessagePreview,
        interlocutorType: type == 'pharmacy'
            ? ConversationInterlocutorType.pharmacy
            : ConversationInterlocutorType.cabinet,
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
  final String? orderRef;
  final int? orderLineCount;
  final int? orderAmountDueCents;
  final List<MessageAttachmentDto> attachments;

  const MessageDto({
    required this.id,
    required this.conversationId,
    required this.sender,
    this.text,
    required this.attachmentIds,
    required this.urgency,
    required this.sentAt,
    this.readAt,
    this.orderRef,
    this.orderLineCount,
    this.orderAmountDueCents,
    this.attachments = const [],
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
        orderRef: json['order_ref'] as String?,
        orderLineCount: (json['order_line_count'] as num?)?.toInt(),
        orderAmountDueCents: (json['order_amount_due_cents'] as num?)?.toInt(),
        attachments: (json['attachments'] as List<dynamic>?)
                ?.map((e) =>
                    MessageAttachmentDto.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
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
        attachedOrder: orderRef == null
            ? null
            : MessageOrderAttachment(
                orderRef: orderRef!,
                lineCount: orderLineCount ?? 0,
                amountDueCents: orderAmountDueCents ?? 0,
              ),
        attachments: attachments.map((a) => a.toDomain()).toList(),
      );
}

/// Pièce jointe d'un message liée à un document du coffre-fort (#5282) —
/// contrat anticipé `{document_id, title, subtitle, category}` par entrée de
/// `attachments`, `category` suivant la même nomenclature que `DocumentDto`.
class MessageAttachmentDto {
  final String documentId;
  final String title;
  final String? subtitle;
  final String? category;

  const MessageAttachmentDto({
    required this.documentId,
    required this.title,
    this.subtitle,
    this.category,
  });

  factory MessageAttachmentDto.fromJson(Map<String, dynamic> json) =>
      MessageAttachmentDto(
        documentId: json['document_id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        category: json['category'] as String?,
      );

  MessageAttachment toDomain() => MessageAttachment(
        documentId: documentId,
        title: title,
        subtitle: subtitle,
        category: DocumentDto.parseCategory(category ?? ''),
      );
}
