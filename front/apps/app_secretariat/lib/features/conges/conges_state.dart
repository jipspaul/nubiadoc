import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CongesState extends Equatable {
  const CongesState();

  @override
  List<Object?> get props => [];
}

class CongesLoading extends CongesState {
  const CongesLoading();
}

class CongesError extends CongesState {
  const CongesError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class CongesLoaded extends CongesState {
  const CongesLoaded({
    required this.requests,
    this.status = 'pending',
    this.actionInProgress = false,
    this.actionError,
  });

  final List<LeaveRequest> requests;

  /// Filtre courant (conservé pour recharger après une action) — défaut
  /// `pending` : la file de validation, pas l'historique du cabinet.
  final String? status;

  final bool actionInProgress;
  final String? actionError;

  CongesLoaded copyWith({
    List<LeaveRequest>? requests,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      CongesLoaded(
        requests: requests ?? this.requests,
        status: status,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [requests, status, actionInProgress, actionError];
}
