import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

final class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

final class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

final class DashboardLoaded extends DashboardState {
  final ProDashboardSummary summary;
  final bool actionInProgress;
  final String? actionError;

  /// Id de la séance qui vient d'être démarrée depuis le hero « Patient
  /// suivant » — consommé par la page pour naviguer vers /consultation
  /// (#6241, même pattern que `AgendaLoaded.startedConsultationId`), puis
  /// remis à null.
  final String? startedConsultationId;

  const DashboardLoaded(
    this.summary, {
    this.actionInProgress = false,
    this.actionError,
    this.startedConsultationId,
  });

  DashboardLoaded copyWith({
    ProDashboardSummary? summary,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    String? startedConsultationId,
    bool clearStartedConsultation = false,
  }) =>
      DashboardLoaded(
        summary ?? this.summary,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        startedConsultationId: clearStartedConsultation
            ? null
            : (startedConsultationId ?? this.startedConsultationId),
      );

  @override
  List<Object?> get props =>
      [summary, actionInProgress, actionError, startedConsultationId];
}

final class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);

  @override
  List<Object?> get props => [message];
}
