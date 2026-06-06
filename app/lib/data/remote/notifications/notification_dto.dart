import 'package:nubia_patient/domain/entities/app_notification.dart';

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
        type: json['type'] as String? ?? 'other',
        title: json['title'] as String,
        body: json['body'] as String,
        read: json['read'] as bool? ?? false,
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
      );

  static NotificationType _parseType(String raw) {
    switch (raw) {
      case 'appointment':
        return NotificationType.appointment;
      case 'message':
        return NotificationType.message;
      case 'document':
        return NotificationType.document;
      case 'payment':
        return NotificationType.payment;
      default:
        return NotificationType.other;
    }
  }
}
