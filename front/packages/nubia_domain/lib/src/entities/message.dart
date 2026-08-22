import 'package:equatable/equatable.dart';

enum MessageSender { patient, cabinet }

enum MessageUrgency { normal, urgent }

class Conversation extends Equatable {
  final String id;
  final String cabinetId;
  final String cabinetName;
  final int unreadCount;
  final Message? lastMessage;

  /// Horodatage du dernier message du fil (`last_message_at` du contrat liste).
  /// `null` si le fil n'a encore aucun message. Le contrat liste ne renvoie
  /// pas l'aperçu texte, d'où ce champ dédié pour afficher la date/heure.
  final DateTime? lastMessageAt;

  /// Aperçu tronqué du dernier message (`last_message_preview`).
  final String? lastMessagePreview;

  const Conversation({
    required this.id,
    required this.cabinetId,
    required this.cabinetName,
    required this.unreadCount,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessagePreview,
  });

  Conversation copyWith({int? unreadCount}) {
    return Conversation(
      id: id,
      cabinetId: cabinetId,
      cabinetName: cabinetName,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      lastMessagePreview: lastMessagePreview,
    );
  }

  @override
  List<Object?> get props => [id];
}

class Message extends Equatable {
  final String id;
  final String conversationId;
  final MessageSender sender;
  final String? text;
  final List<String> attachmentIds;
  final MessageUrgency urgency;
  final DateTime sentAt;
  final DateTime? readAt;

  /// Commande jointe au message (#4924), affichée en carte dans le fil.
  /// `null` quand le message ne porte aucune commande.
  final MessageOrderAttachment? attachedOrder;

  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    this.text,
    this.attachmentIds = const [],
    required this.urgency,
    required this.sentAt,
    this.readAt,
    this.attachedOrder,
  });

  @override
  List<Object?> get props => [id];
}

/// Référence de commande jointe à un [Message] (#4924) — n° de commande,
/// nombre de lignes et reste à payer, affichés en carte dans le fil.
class MessageOrderAttachment extends Equatable {
  final String orderRef;
  final int lineCount;
  final int amountDueCents;

  const MessageOrderAttachment({
    required this.orderRef,
    required this.lineCount,
    required this.amountDueCents,
  });

  @override
  List<Object?> get props => [orderRef, lineCount, amountDueCents];
}
