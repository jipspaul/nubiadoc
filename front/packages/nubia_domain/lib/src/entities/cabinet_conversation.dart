import 'package:equatable/equatable.dart';
import 'message.dart';

class CabinetConversation extends Equatable {
  final String id;
  final String patientId;
  final String patientName;

  /// Téléphone du patient (`patient_phone`, #4926 colonne contexte) —
  /// `null` quand le contrat back ne l'expose pas encore.
  final String? patientPhone;
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

  /// Statut de qualification cabinet (`open`/`in_progress`/`done`/`closed`,
  /// #7151) — distinct du statut brut `scope`/messagerie. `open` par défaut
  /// tant que la conversation n'a pas été qualifiée.
  final String status;

  /// `low`/`medium`/`high`/`urgent` — `null` tant que non qualifiée (#7151).
  final String? priority;

  /// `phone`/`app`/`web`/`email`/`other` — `null` tant que non qualifiée
  /// (#7151).
  final String? origin;

  /// Synthèse non clinique rédigée par le secrétariat (#7151) — jamais de
  /// motif clinique : cloisonnement §07 §4.1, cf. `CabinetConversation` ne
  /// porte aucun champ `motif`/`notes_medicales`.
  final String? summary;

  /// `app_user.id` du membre du cabinet assigné à la conversation, `null`
  /// si non assignée (#7151).
  final String? assigneeUserId;

  const CabinetConversation({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.patientPhone,
    required this.unreadCount,
    this.lastMessageAt,
    this.lastMessage,
    this.lastMessagePreview,
    this.triageFlag = MessageUrgency.normal,
    this.orderRef,
    this.orderStatusLabel,
    this.status = 'open',
    this.priority,
    this.origin,
    this.summary,
    this.assigneeUserId,
  });

  // `status`/`priority`/`origin`/`summary`/`assigneeUserId` dans `props` (en
  // plus de `id`) — même convention que `CabinetAppointment`/`AgendaEntry`
  // ([id, status]) : sans ça, une conversation ré-assignée en place (#7151)
  // reste `==` à l'ancienne (Equatable ne compare que `id`), et le bloc
  // (`BlocBase.emit` déduplique par `==`) ignore silencieusement l'émission.
  @override
  List<Object?> get props =>
      [id, status, priority, origin, summary, assigneeUserId];
}
