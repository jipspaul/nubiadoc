import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class ConsultationCliniqueState extends Equatable {
  const ConsultationCliniqueState();

  @override
  List<Object?> get props => [];
}

class ConsultationCliniqueInitial extends ConsultationCliniqueState {
  const ConsultationCliniqueInitial();
}

class ConsultationCliniqueLoading extends ConsultationCliniqueState {
  const ConsultationCliniqueLoading();
}

class ConsultationCliniqueLoaded extends ConsultationCliniqueState {
  final ClinicalSession session;
  final bool actionInProgress;

  /// Message d'erreur transitoire d'une action (ex. 403 sur ajout d'acte —
  /// #3403). Affiché via snackbar puis consommé, sans quitter l'écran.
  final String? actionError;

  const ConsultationCliniqueLoaded({
    required this.session,
    this.actionInProgress = false,
    this.actionError,
  });

  ConsultationCliniqueLoaded copyWith({
    ClinicalSession? session,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      ConsultationCliniqueLoaded(
        session: session ?? this.session,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [session, actionInProgress, actionError];
}

class ConsultationCliniqueError extends ConsultationCliniqueState {
  final String message;
  const ConsultationCliniqueError(this.message);

  @override
  List<Object?> get props => [message];
}

class ConsultationCliniqueCompleted extends ConsultationCliniqueState {
  final SessionCompleteResult result;
  const ConsultationCliniqueCompleted(this.result);

  @override
  List<Object?> get props => [result];
}

class ConsultationHistoriqueLoaded extends ConsultationCliniqueState {
  final List<ClinicalSession> sessions;
  const ConsultationHistoriqueLoaded({required this.sessions});

  @override
  List<Object?> get props => [sessions];
}
