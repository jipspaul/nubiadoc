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

  /// Référence de la commande liée à la conversation (ex. `CMD-4821`, #4923).
  /// `null` quand la conversation n'est rattachée à aucune commande.
  final String? orderRef;

  /// Libellé court du statut de la commande liée (ex. « Prête », « En
  /// prépa », #4923). `null` quand [orderRef] est `null`.
  final String? orderStatusLabel;

  const CabinetConversation({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.unreadCount,
    this.lastMessageAt,
    this.lastMessage,
    this.lastMessagePreview,
    this.triageFlag = MessageUrgency.normal,
    this.orderRef,
    this.orderStatusLabel,
  });

  @override
  List<Object?> get props => [id];
}
