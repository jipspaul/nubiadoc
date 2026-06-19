import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class ConsultationState extends Equatable {
  const ConsultationState();

  @override
  List<Object?> get props => [];
}

class ConsultationInitial extends ConsultationState {
  const ConsultationInitial();
}

class ConsultationLoading extends ConsultationState {
  const ConsultationLoading();
}

class ConsultationLoaded extends ConsultationState {
  final ClinicalSession session;
  final bool actionInProgress;
  final String? actionError;

  const ConsultationLoaded({
    required this.session,
    this.actionInProgress = false,
    this.actionError,
  });

  ConsultationLoaded copyWith({
    ClinicalSession? session,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      ConsultationLoaded(
        session: session ?? this.session,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [session, actionInProgress, actionError];
}

class ConsultationError extends ConsultationState {
  final String message;
  const ConsultationError(this.message);

  @override
  List<Object?> get props => [message];
}

class ConsultationCompleted extends ConsultationState {
  final SessionCompleteResult result;
  const ConsultationCompleted(this.result);

  @override
  List<Object?> get props => [result];
}
