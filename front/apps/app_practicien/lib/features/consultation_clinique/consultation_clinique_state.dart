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

  const ConsultationCliniqueLoaded({
    required this.session,
    this.actionInProgress = false,
  });

  ConsultationCliniqueLoaded copyWith({
    ClinicalSession? session,
    bool? actionInProgress,
  }) =>
      ConsultationCliniqueLoaded(
        session: session ?? this.session,
        actionInProgress: actionInProgress ?? this.actionInProgress,
      );

  @override
  List<Object?> get props => [session, actionInProgress];
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
