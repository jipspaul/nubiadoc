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

  /// Raw `data.status` string from the API (ex. `preparing`/`ready`/
  /// `picked_up` pour les commandes pharmacie) — cf. `api/src/pharmacy/
  /// orders.rs`. Sert à discriminer l'action affichée sous une notification
  /// dont le libellé dépend de l'état réel (#6610 : « Afficher mon code »
  /// n'a de sens que si la commande est `ready`). `null` quand `data` ne
  /// porte pas de statut.
  final String? status;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.deepLink,
    this.kind,
    this.status,
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
      status: status,
    );
  }

  @override
  List<Object?> get props => [id, read];
}
