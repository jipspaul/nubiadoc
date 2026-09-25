import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class MesCongesState extends Equatable {
  const MesCongesState();

  @override
  List<Object?> get props => [];
}

class MesCongesLoading extends MesCongesState {
  const MesCongesLoading();
}

class MesCongesError extends MesCongesState {
  const MesCongesError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class MesCongesLoaded extends MesCongesState {
  const MesCongesLoaded({
    required this.requests,
    this.userId,
    this.status,
    this.actionInProgress = false,
    this.actionError,
  });

  final List<LeaveRequest> requests;

  /// Filtres courants (conservés pour recharger après une action).
  final String? userId;
  final String? status;

  final bool actionInProgress;
  final String? actionError;

  MesCongesLoaded copyWith({
    List<LeaveRequest>? requests,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      MesCongesLoaded(
        requests: requests ?? this.requests,
        userId: userId,
        status: status,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props =>
      [requests, userId, status, actionInProgress, actionError];
}
