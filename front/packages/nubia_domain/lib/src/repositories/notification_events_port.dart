/// Notification poussée en temps réel sur le canal WS `notifications`.
///
/// Quoi : le strict nécessaire pour réagir côté UI (badge, bandeau, refresh) —
/// la liste complète reste chargée par le REST (source de vérité).
/// Pourquoi pas `AppNotification` : l'enveloppe WS est un sous-ensemble
/// volontaire (zéro PII, cf. notify.rs côté API) ; on ne fait pas semblant
/// d'avoir l'objet complet.
class IncomingNotification {
  const IncomingNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.data = const {},
  });

  /// Id de la ligne `notification` (permet un mark-read direct).
  final String id;

  /// Kind serveur (`message_received`, `patient_checked_in`, …).
  final String kind;

  /// Titre générique sans donnée de santé — affichable tel quel en bandeau.
  final String title;

  /// Payload deeplink (`conversation_id`, `appointment_id`, …).
  final Map<String, dynamic> data;
}

/// Flux temps réel des notifications de l'utilisateur connecté.
///
/// Port framework-free. Implémentation data : WebSocket `/v1/ws`, canal
/// `notifications` (abonnement au canal PERSONNEL, dérivé du JWT côté
/// serveur — impossible d'écouter un autre utilisateur). Interim « app
/// vivante » en attendant le push FCM/APNs : une app tuée ne reçoit rien,
/// le polling 60 s existant reste le filet.
///
/// Modes d'échec : best-effort — pas de token ou WS injoignable ⇒ flux
/// silencieux (aucune erreur remontée aux blocs), reconnexion gérée par le
/// client WS sous-jacent.
abstract class NotificationEventsPort {
  /// Notifications entrantes, dans l'ordre d'arrivée. Broadcast : plusieurs
  /// écouteurs possibles (cloche + page).
  Stream<IncomingNotification> watch();

  /// Libère la socket et les abonnements.
  void dispose();
}
