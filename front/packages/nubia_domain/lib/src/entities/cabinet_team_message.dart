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

  /// Libellé de rôle de l'auteur (#5125), ex. `Praticienne`, `Secrétaire` —
  /// affiché en badge à côté de [senderName] dans un fil où praticiens et
  /// secrétariat se mêlent. `null` : pas de badge (rétro-compatibilité).
  final String? senderRole;
  final String body;
  final DateTime createdAt;
  final CabinetTeamMessageReference? reference;

  /// Épinglage (#5130) : garde visible une consigne durable (fermeture
  /// exceptionnelle, changement d'horaire) en tête de fil / aside, plutôt
  /// que de la laisser se noyer dans le fil.
  final bool pinned;
  final String? pinnedBy;
  final DateTime? pinnedAt;

  /// Noms des membres mentionnés (`@Nom`) dans [body] (#5129) : une mention
  /// est une tâche adressée, distincte visuellement du reste du message.
  final List<String> mentions;

  const CabinetTeamMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderRole,
    required this.body,
    required this.createdAt,
    this.reference,
    this.pinned = false,
    this.pinnedBy,
    this.pinnedAt,
    this.mentions = const [],
  });

  @override
  List<Object?> get props => [
        id,
        senderId,
        senderName,
        senderRole,
        body,
        createdAt,
        reference,
        pinned,
        pinnedBy,
        pinnedAt,
        mentions,
      ];
}
