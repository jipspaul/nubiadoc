import 'package:nubia_domain/src/entities/app_notification.dart';

class NotificationDto {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final String createdAt;
  final String? deepLink;

  const NotificationDto({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.deepLink,
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
      );

  AppNotification toDomain() => AppNotification(
        id: id,
        type: _parseType(type),
        title: title,
        body: body,
        read: read,
        createdAt: DateTime.parse(createdAt),
        deepLink: deepLink,
        kind: type,
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
}
