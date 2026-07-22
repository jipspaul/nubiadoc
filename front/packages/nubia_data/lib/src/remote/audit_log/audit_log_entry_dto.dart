import 'package:nubia_domain/src/entities/audit_log_entry.dart';

class AuditLogEntryDto {
  final int id;
  final String? actorId;
  final String? actorRole;
  final String action;
  final String entity;
  final String? entityId;
  final String occurredAt;

  const AuditLogEntryDto({
    required this.id,
    this.actorId,
    this.actorRole,
    required this.action,
    required this.entity,
    this.entityId,
    required this.occurredAt,
  });

  factory AuditLogEntryDto.fromJson(Map<String, dynamic> json) =>
      AuditLogEntryDto(
        id: json['id'] as int,
        actorId: json['actor_id'] as String?,
        actorRole: json['actor_role'] as String?,
        action: json['action'] as String,
        entity: json['entity'] as String,
        entityId: json['entity_id'] as String?,
        occurredAt: json['occurred_at'] as String,
      );

  AuditLogEntry toDomain() => AuditLogEntry(
        id: id,
        actorId: actorId,
        actorRole: actorRole,
        action: action,
        entity: entity,
        entityId: entityId,
        occurredAt: DateTime.parse(occurredAt),
      );
}
