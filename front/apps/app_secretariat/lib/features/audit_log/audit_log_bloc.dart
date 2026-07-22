import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'audit_log_event.dart';
import 'audit_log_state.dart';

/// Journal d'accès du cabinet (#4155) : `GET /v1/cabinet/audit-log`,
/// filtrable date/entité, réservé admin/manager (403 sinon).
class AuditLogBloc extends Bloc<AuditLogEvent, AuditLogState>
    with SafeEmitMixin<AuditLogState> {
  AuditLogBloc({required GetAuditLogUseCase getAuditLog})
      : _getAuditLog = getAuditLog,
        super(const AuditLogLoading()) {
    on<AuditLogLoadRequested>(_onLoad);
  }

  final GetAuditLogUseCase _getAuditLog;

  Future<void> _onLoad(
    AuditLogLoadRequested event,
    Emitter<AuditLogState> emit,
  ) async {
    emit(const AuditLogLoading());
    final result = await _getAuditLog(
      from: event.from,
      to: event.to,
      entity: event.entity,
    );
    result.fold(
      (failure) {
        if (failure is ServerFailure && failure.statusCode == 403) {
          safeEmit(AuditLogForbidden(failure.message));
        } else {
          safeEmit(AuditLogError(failure.message));
        }
      },
      (entries) => safeEmit(AuditLogLoaded(entries)),
    );
  }
}
