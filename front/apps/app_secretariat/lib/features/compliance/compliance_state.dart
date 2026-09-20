import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ComplianceState extends Equatable {
  const ComplianceState();

  @override
  List<Object?> get props => [];
}

class ComplianceInitial extends ComplianceState {
  const ComplianceInitial();
}

class ComplianceLoading extends ComplianceState {
  const ComplianceLoading();
}

class ComplianceError extends ComplianceState {
  const ComplianceError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class ComplianceLoaded extends ComplianceState {
  const ComplianceLoaded({
    required this.items,
    this.actionInProgress = false,
    this.actionError,
  });

  final List<ComplianceItem> items;
  final bool actionInProgress;
  final String? actionError;

  List<ComplianceItem> get pending =>
      items.where((i) => !i.isDone).toList();
  List<ComplianceItem> get done => items.where((i) => i.isDone).toList();

  ComplianceLoaded copyWith({
    List<ComplianceItem>? items,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      ComplianceLoaded(
        items: items ?? this.items,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [items, actionInProgress, actionError];
}
