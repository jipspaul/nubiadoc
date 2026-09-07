import 'package:nubia_domain/src/entities/app_notification.dart';

class NotificationDto {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final String createdAt;
  final String? deepLink;

  /// Métadonnées non-PII (`data.status`, ids…) — jamais chiffrées côté API,
  /// contrairement à `body` (cf. `api/src/notifications.rs` `NotificationItem`).
  /// Sert à dériver une ligne de détail côté client quand `body` est absent
  /// (#6376 : le backend n'écrit jamais de `body` réel, `body_ciphertext` est
  /// un stub — `api/src/notify.rs` `notify_user`).
  final Map<String, dynamic> data;

  const NotificationDto({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.deepLink,
    this.data = const {},
  });

  factory NotificationDto.fromJson(Map<String, dynamic> json) =>
      NotificationDto(
        id: json['id'] as String,
        // Contrat réel : kind, is_read, pas de body.
        type: (json['type'] ?? json['kind']) as String? ?? 'other',
        title: json['title'] as String,
        body: (json['body'] as String?) ?? '',
        read: (json['read'] ?? json['is_read']) as bool? ?? false,
        createdAt: json['created_at'] as String,
        deepLink: json['deep_link'] as String?,
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  AppNotification toDomain() => AppNotification(
        id: id,
        type: _parseType(type),
        title: title,
        body: body.isNotEmpty ? body : _deriveBody(type, data),
        read: read,
        createdAt: DateTime.parse(createdAt),
        deepLink: deepLink,
        kind: type,
        status: data['status'] as String?,
      );

  // Le backend émet des kinds préfixés/composés (ex: appointment_confirmed,
  // order_status_changed, visit_status_changed — cf. api/src/notifications.rs
  // `derive_deep_link` et les appels `notify::notify_*`), jamais les
  // chaînes bare 'appointment'/'message'/'document'/'payment'. On matche
  // donc par préfixe/famille plutôt que par égalité stricte.
  static NotificationType _parseType(String raw) {
    if (raw.startsWith('appointment') ||
        raw.startsWith('visit') ||
        raw.startsWith('waiting_room') ||
        raw.startsWith('waiting_list') ||
        raw.startsWith('rdv_') ||
        raw.startsWith('recall_')) {
      return NotificationType.appointment;
    }
    if (raw.startsWith('message') || raw.startsWith('review_request')) {
      return NotificationType.message;
    }
    if (raw.startsWith('document') || raw.startsWith('lab_work')) {
      return NotificationType.document;
    }
    if (raw.startsWith('payment') ||
        raw.startsWith('quote') ||
        raw == 'unpaid_invoice' ||
        raw.startsWith('pharmacy_quote')) {
      return NotificationType.payment;
    }
    // Commandes pharmacie (click-and-collect) : bucket 'other' volontaire,
    // c'est lui qui porte l'action "Afficher mon code" côté UI.
    if (raw.startsWith('order') || raw.startsWith('pharmacy_order')) {
      return NotificationType.other;
    }
    return NotificationType.other;
  }

  /// Ligne de détail par `kind` (maquette design-v2, écran Patient ·
  /// Notifications) quand l'API ne fournit pas de `body` (cf. `data` doc
  /// ci-dessus). Contenu générique zéro-PII, même contrainte que
  /// `api/src/reminder_dispatch.rs` `sms_body_for_kind` : le détail réel se
  /// consulte authentifié dans l'app. Quand `data` porte un `status`
  /// distinguant plusieurs notifications de même `kind`/titre (ex.
  /// `visit_status_changed`), on l'utilise pour lever l'ambiguïté.
  static String _deriveBody(String kind, Map<String, dynamic> data) {
    switch (kind) {
      case 'visit_status_changed':
        return switch (data['status']) {
          'accepted' =>
            'Une infirmière a accepté votre demande de visite à domicile.',
          'en_route' => 'Votre infirmière est en route vers votre domicile.',
          'arrived' => 'Votre infirmière est arrivée à votre domicile.',
          'done' => 'Votre visite à domicile est terminée.',
          _ => 'Le statut de votre visite à domicile a changé.',
        };
      case 'order_received':
        return 'Nouvelle commande à préparer.';
      case 'order_status_changed':
        return switch (data['status']) {
          'preparing' => 'Votre commande est en cours de préparation.',
          'ready' => 'Votre commande est prête, vous pouvez la retirer.',
          'picked_up' => 'Votre commande a bien été retirée.',
          'cancelled' => 'Votre commande a été annulée.',
          _ => 'Le statut de votre commande a changé.',
        };
      case 'waiting_room_called':
        return "Le cabinet est prêt à vous recevoir, présentez-vous à l'accueil.";
      case 'waiting_list_slot_offered':
        return "Un créneau s'est libéré pour vous, réservez-le rapidement.";
      case 'appointment_confirmed':
        return 'Le cabinet a confirmé votre rendez-vous.';
      case 'appointment_rescheduled':
        return 'La date de votre rendez-vous a changé.';
      case 'appointment_motif_changed':
        return 'Le motif de votre rendez-vous a été modifié.';
      case 'appointment_requested':
        return 'Une nouvelle demande de rendez-vous est en attente.';
      case 'rdv_confirmation':
        return 'Merci de confirmer votre prochain rendez-vous.';
      case 'rdv_follow_up':
      case 'review_request':
        return "Comment s'est passé votre rendez-vous ? Donnez votre avis.";
      case 'recall_annual':
        return 'Il est temps de planifier votre bilan annuel.';
      case 'callback_requested':
        return 'Le patient souhaite être rappelé.';
      case 'message_received':
        return 'Vous avez reçu un nouveau message.';
      case 'lab_work_returned':
        return 'Votre prothèse est arrivée au cabinet.';
      case 'quote_relance':
        return 'Un devis est toujours en attente de votre signature.';
      case 'quote_received':
        return 'Un nouveau devis vous a été envoyé, consultez-le.';
      case 'quote_signed':
        return 'Le patient a signé un devis.';
      case 'pharmacy_quote_sent':
        return 'La pharmacie vous a envoyé un devis à signer.';
      case 'pharmacy_quote_decided':
        return 'Le patient a répondu à votre devis.';
      case 'unpaid_invoice':
        return 'Une facture reste impayée depuis plus de 30 jours.';
      case 'visit_offer':
        return 'Une nouvelle demande de visite est disponible près de chez vous.';
      case 'visit_request_expired':
        return "Aucune infirmière n'était disponible pour cette demande de visite.";
      case 'stock_request_received':
        return 'Une officine a besoin de ce produit, vérifiez votre stock.';
      default:
        return '';
    }
  }
}
