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

  /// Raw `notification.kind` string from the API (e.g. `order_received`,
  /// `stock_request_received`) — unlike [type], which buckets it into 5
  /// coarse families, this preserves the exact value the pro apps' kind→route
  /// `NotificationRouteResolver`s (#6264) switch on. `null` when unset (e.g.
  /// in tests that don't need deep-linking).
  final String? kind;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.deepLink,
    this.kind,
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
      kind: kind,
    );
  }

  @override
  List<Object?> get props => [id, read];
}
