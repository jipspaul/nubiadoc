import 'package:equatable/equatable.dart';
import 'message.dart';

class CabinetConversation extends Equatable {
  final String id;
  final String patientId;
  final String patientName;
  final int unreadCount;
  final DateTime? lastMessageAt;
  final Message? lastMessage;

  /// Aperçu tronqué du dernier message (`last_message_preview`, #3373).
  final String? lastMessagePreview;

  /// `urgent` tant qu'un message patient urgent est non lu dans le fil
  /// (`triage_flag` du contrat liste, #3556) — pas dérivé du seul dernier
  /// message, qui peut être un message normal postérieur.
  final MessageUrgency triageFlag;

  const CabinetConversation({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.unreadCount,
    this.lastMessageAt,
    this.lastMessage,
    this.lastMessagePreview,
    this.triageFlag = MessageUrgency.normal,
  });

  @override
  List<Object?> get props => [id];
}
