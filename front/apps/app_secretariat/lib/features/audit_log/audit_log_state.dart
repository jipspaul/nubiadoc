import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class AuditLogState extends Equatable {
  const AuditLogState();

  @override
  List<Object?> get props => [];
}

final class AuditLogLoading extends AuditLogState {
  const AuditLogLoading();
}

final class AuditLogLoaded extends AuditLogState {
  const AuditLogLoaded(this.entries);

  final List<AuditLogEntry> entries;

  @override
  List<Object?> get props => [entries];
}

final class AuditLogError extends AuditLogState {
  const AuditLogError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Accès refusé (403) : rôle `secretary`/`practitioner`, réservé
/// admin/manager côté back (`ProAdminOrManagerClaims`, #4155).
final class AuditLogForbidden extends AuditLogState {
  const AuditLogForbidden(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
