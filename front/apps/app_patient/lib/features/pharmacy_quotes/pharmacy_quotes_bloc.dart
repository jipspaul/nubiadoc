import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class PharmacyQuotesEvent extends Equatable {
  const PharmacyQuotesEvent();

  @override
  List<Object?> get props => [];
}

class PharmacyQuotesRequested extends PharmacyQuotesEvent {
  const PharmacyQuotesRequested();
}

class PharmacyQuoteDecisionRequested extends PharmacyQuotesEvent {
  const PharmacyQuoteDecisionRequested(this.quoteId, {required this.accept});

  final String quoteId;
  final bool accept;

  @override
  List<Object?> get props => [quoteId, accept];
}

// ── States ────────────────────────────────────────────────────────────────────

sealed class PharmacyQuotesState extends Equatable {
  const PharmacyQuotesState();

  @override
  List<Object?> get props => [];
}

class PharmacyQuotesLoading extends PharmacyQuotesState {
  const PharmacyQuotesLoading();
}

class PharmacyQuotesLoaded extends PharmacyQuotesState {
  const PharmacyQuotesLoaded(
    this.quotes, {
    this.decidingId,
    this.erroredId,
    this.errorMessage,
  });

  final List<PharmacyQuote> quotes;

  /// Id du devis dont la décision (accepter/refuser) est en cours — désactive
  /// ses deux boutons le temps de l'appel réseau.
  final String? decidingId;

  /// Id du devis dont la dernière décision a échoué (affichage de
  /// [errorMessage] sous ses boutons) — `null` sinon.
  final String? erroredId;
  final String? errorMessage;

  @override
  List<Object?> get props => [quotes, decidingId, erroredId, errorMessage];
}

class PharmacyQuotesError extends PharmacyQuotesState {
  const PharmacyQuotesError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Devis d'officine reçus par le patient (`/v1/account/pharmacy-quotes`) —
/// consultation + décision (accepter/refuser un devis `sent`, #6580).
class PharmacyQuotesBloc extends Bloc<PharmacyQuotesEvent, PharmacyQuotesState>
    with SafeEmitMixin<PharmacyQuotesState> {
  PharmacyQuotesBloc({
    required ListPharmacyQuotesUseCase list,
    required DecidePharmacyQuoteUseCase decide,
  })  : _list = list,
        _decide = decide,
        super(const PharmacyQuotesLoading()) {
    on<PharmacyQuotesRequested>(_onRequested);
    on<PharmacyQuoteDecisionRequested>(_onDecisionRequested);
  }

  final ListPharmacyQuotesUseCase _list;
  final DecidePharmacyQuoteUseCase _decide;

  Future<void> _onRequested(
    PharmacyQuotesRequested event,
    Emitter<PharmacyQuotesState> emit,
  ) async {
    emit(const PharmacyQuotesLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(PharmacyQuotesError(failure.message)),
      (quotes) => emit(PharmacyQuotesLoaded(quotes)),
    );
  }

  Future<void> _onDecisionRequested(
    PharmacyQuoteDecisionRequested event,
    Emitter<PharmacyQuotesState> emit,
  ) async {
    final current = state;
    if (current is! PharmacyQuotesLoaded) return;
    emit(PharmacyQuotesLoaded(current.quotes, decidingId: event.quoteId));
    final result = await _decide(event.quoteId, accept: event.accept);
    result.fold(
      (failure) => safeEmit(PharmacyQuotesLoaded(
        current.quotes,
        erroredId: event.quoteId,
        errorMessage: failure.message,
      )),
      (updated) => safeEmit(PharmacyQuotesLoaded([
        for (final quote in current.quotes)
          if (quote.id == updated.id) updated else quote,
      ])),
    );
  }
}
