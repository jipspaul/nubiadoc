import 'package:equatable/equatable.dart';

/// Type d'objet produit cité par une [CabinetTeamMessageReference] (#5131).
enum CabinetTeamMessageReferenceType {
  patient,
  devis,
  labWorkOrder,
  stockRequest,
  agendaSlot,
}

/// Référence vers un objet réel du produit attachée à un
/// [CabinetTeamMessage] (#5131) : transforme un message en fil de travail
/// (patient, devis, bon de travail labo, demande de stock, créneau agenda).
class CabinetTeamMessageReference extends Equatable {
  final CabinetTeamMessageReferenceType type;
  final String targetId;
  final String title;
  final String subtitle;

  const CabinetTeamMessageReference({
    required this.type,
    required this.targetId,
    required this.title,
    required this.subtitle,
  });

  @override
  List<Object?> get props => [type, targetId, title, subtitle];
}

class CabinetTeamMessage extends Equatable {
  final String id;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;
  final CabinetTeamMessageReference? reference;

  const CabinetTeamMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    this.reference,
  });

  @override
  List<Object?> get props =>
      [id, senderId, senderName, body, createdAt, reference];
}
