import 'package:equatable/equatable.dart';

enum NotificationType {
  appointment,
  message,
  document,
  payment,
  other,
}

class AppNotification extends Equatable {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;
  /// Optional deep-link target (e.g. `/appointments/42`).
  final String? deepLink;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.deepLink,
  });

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      read: read ?? this.read,
      createdAt: createdAt,
      deepLink: deepLink,
    );
  }

  @override
  List<Object?> get props => [id, read];
}
