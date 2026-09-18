import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class OpportunitiesState extends Equatable {
  const OpportunitiesState();
}

class OpportunitiesLoading extends OpportunitiesState {
  const OpportunitiesLoading();

  @override
  List<Object?> get props => [];
}

class OpportunitiesError extends OpportunitiesState {
  const OpportunitiesError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class OpportunitiesLoaded extends OpportunitiesState {
  const OpportunitiesLoaded({required this.categories});

  /// Les 5 catégories du widget, dans l'ordre renvoyé par l'API (#7214).
  final List<OpportunityCategory> categories;

  @override
  List<Object?> get props => [categories];
}
