part of 'quote_list_cubit.dart';

sealed class QuoteListState extends Equatable {
  const QuoteListState();

  @override
  List<Object?> get props => [];
}

/// Chargement en cours.
final class QuoteListLoading extends QuoteListState {
  const QuoteListLoading();
}

/// Devis chargés avec succès.
final class QuoteListLoaded extends QuoteListState {
  const QuoteListLoaded(this.quotes);

  final List<Quote> quotes;

  @override
  List<Object?> get props => [quotes];
}

/// Erreur lors du chargement.
final class QuoteListError extends QuoteListState {
  const QuoteListError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
