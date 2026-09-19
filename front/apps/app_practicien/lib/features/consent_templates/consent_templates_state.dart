import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ConsentTemplatesState extends Equatable {
  const ConsentTemplatesState();

  @override
  List<Object?> get props => [];
}

class ConsentTemplatesInitial extends ConsentTemplatesState {
  const ConsentTemplatesInitial();
}

class ConsentTemplatesLoading extends ConsentTemplatesState {
  const ConsentTemplatesLoading();
}

class ConsentTemplatesError extends ConsentTemplatesState {
  const ConsentTemplatesError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class ConsentTemplatesLoaded extends ConsentTemplatesState {
  const ConsentTemplatesLoaded({
    required this.templates,
    this.actionInProgress = false,
    this.actionError,
  });

  final List<ConsentTemplate> templates;
  final bool actionInProgress;
  final String? actionError;

  ConsentTemplatesLoaded copyWith({
    List<ConsentTemplate>? templates,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      ConsentTemplatesLoaded(
        templates: templates ?? this.templates,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [templates, actionInProgress, actionError];
}
