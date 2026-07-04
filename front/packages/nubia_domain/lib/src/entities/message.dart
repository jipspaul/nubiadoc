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

  const Conversation({
    required this.id,
    required this.cabinetId,
    required this.cabinetName,
    required this.unreadCount,
    this.lastMessage,
    this.lastMessageAt,
  });

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

  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    this.text,
    this.attachmentIds = const [],
    required this.urgency,
    required this.sentAt,
    this.readAt,
  });

  @override
  List<Object?> get props => [id];
}
