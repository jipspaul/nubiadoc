import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class ConsultationCliniqueState extends Equatable {
  const ConsultationCliniqueState();
}

class ConsultationCliniqueInitial extends ConsultationCliniqueState {
  const ConsultationCliniqueInitial();

  @override
  List<Object?> get props => [];
}

class ConsultationCliniqueLoading extends ConsultationCliniqueState {
  const ConsultationCliniqueLoading();

  @override
  List<Object?> get props => [];
}

class ConsultationCliniqueLoaded extends ConsultationCliniqueState {
  const ConsultationCliniqueLoaded({
    required this.session,
    this.actionInProgress = false,
    this.actionError,
  });
  final ClinicalSession session;
  final bool actionInProgress;
  final String? actionError;

  @override
  List<Object?> get props => [session, actionInProgress, actionError];
}

class ConsultationCliniqueError extends ConsultationCliniqueState {
  const ConsultationCliniqueError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class ConsultationCliniqueCompleteSuccess extends ConsultationCliniqueState {
  const ConsultationCliniqueCompleteSuccess({this.invoiceId});
  final String? invoiceId;

  @override
  List<Object?> get props => [invoiceId];
}
