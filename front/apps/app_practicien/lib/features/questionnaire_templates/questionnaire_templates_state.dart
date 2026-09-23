import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class QuestionnaireTemplatesState extends Equatable {
  const QuestionnaireTemplatesState();

  @override
  List<Object?> get props => [];
}

class QuestionnaireTemplatesInitial extends QuestionnaireTemplatesState {
  const QuestionnaireTemplatesInitial();
}

class QuestionnaireTemplatesLoading extends QuestionnaireTemplatesState {
  const QuestionnaireTemplatesLoading();
}

class QuestionnaireTemplatesError extends QuestionnaireTemplatesState {
  const QuestionnaireTemplatesError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class QuestionnaireTemplatesLoaded extends QuestionnaireTemplatesState {
  const QuestionnaireTemplatesLoaded({
    required this.templates,
    this.actionInProgress = false,
    this.actionError,
  });

  final List<QuestionnaireTemplate> templates;
  final bool actionInProgress;
  final String? actionError;

  /// Modèle propre au cabinet (au plus un — contrairement à
  /// `ConsentTemplate`, il n'y a pas de distinction par catégorie d'acte).
  QuestionnaireTemplate? get cabinetTemplate =>
      templates.where((t) => t.isGlobal != true).firstOrNull;

  List<QuestionnaireTemplate> get globalTemplates =>
      templates.where((t) => t.isGlobal == true).toList();

  QuestionnaireTemplatesLoaded copyWith({
    List<QuestionnaireTemplate>? templates,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      QuestionnaireTemplatesLoaded(
        templates: templates ?? this.templates,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [templates, actionInProgress, actionError];
}
