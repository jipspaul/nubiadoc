import 'package:equatable/equatable.dart';

/// Une entrée du journal d'accès (#4155). Source :
/// `GET /v1/cabinet/audit-log`.
class AuditLogEntry extends Equatable {
  final int id;
  final String? actorId;
  final String? actorRole;
  final String action;
  final String entity;
  final String? entityId;
  final DateTime occurredAt;

  const AuditLogEntry({
    required this.id,
    this.actorId,
    this.actorRole,
    required this.action,
    required this.entity,
    this.entityId,
    required this.occurredAt,
  });

  @override
  List<Object?> get props => [id];
}
