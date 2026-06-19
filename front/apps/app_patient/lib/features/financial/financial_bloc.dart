import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'financial_event.dart';
import 'financial_state.dart';

/// Bloc du wedge financier : liste devis → détail → signature Yousign → paiement acompte.
class FinancialBloc extends Bloc<FinancialEvent, FinancialState> {
  FinancialBloc({
    required GetPendingQuotesUseCase getPendingQuotes,
    required GetQuoteByIdUseCase getQuoteById,
    required InitiateSignatureUseCase initiateSignature,
    required InitiateDepositUseCase initiateDeposit,
  })  : _getPendingQuotes = getPendingQuotes,
        _getQuoteById = getQuoteById,
        _initiateSignature = initiateSignature,
        _initiateDeposit = initiateDeposit,
        super(const FinancialInitial()) {
    on<FinancialLoadRequested>(_onLoad);
    on<FinancialQuoteSelected>(_onQuoteSelected);
    on<FinancialBackToList>(_onBackToList);
    on<FinancialSignatureRequested>(_onSignatureRequested);
    on<FinancialSignatureCompleted>(_onSignatureCompleted);
    on<FinancialPaymentRequested>(_onPaymentRequested);
  }

  final GetPendingQuotesUseCase _getPendingQuotes;
  final GetQuoteByIdUseCase _getQuoteById;
  final InitiateSignatureUseCase _initiateSignature;
  final InitiateDepositUseCase _initiateDeposit;

  Future<void> _onLoad(
    FinancialLoadRequested event,
    Emitter<FinancialState> emit,
  ) async {
    emit(const FinancialLoading());
    final result = await _getPendingQuotes();
    result.fold(
      (f) => emit(FinancialError(message: f.message)),
      (quotes) => emit(FinancialLoaded(quotes)),
    );
  }

  Future<void> _onQuoteSelected(
    FinancialQuoteSelected event,
    Emitter<FinancialState> emit,
  ) async {
    final prevQuotes = _extractQuotes(state);
    emit(const FinancialLoading());
    final result = await _getQuoteById(event.quoteId);
    result.fold(
      (f) => emit(FinancialError(message: f.message, quotes: prevQuotes)),
      (quote) =>
          emit(FinancialQuoteDetail(quote: quote, quotes: prevQuotes)),
    );
  }

  void _onBackToList(
    FinancialBackToList event,
    Emitter<FinancialState> emit,
  ) {
    final quotes = _extractQuotes(state);
    emit(FinancialLoaded(quotes));
  }

  Future<void> _onSignatureRequested(
    FinancialSignatureRequested event,
    Emitter<FinancialState> emit,
  ) async {
    final current = state;
    if (current is! FinancialQuoteDetail) return;
    final result = await _initiateSignature(current.quote.id);
    result.fold(
      (f) => emit(FinancialError(message: f.message, quotes: current.quotes)),
      (url) => emit(FinancialSignatureInProgress(
        quote: current.quote,
        quotes: current.quotes,
        signatureUrl: url,
      )),
    );
  }

  Future<void> _onSignatureCompleted(
    FinancialSignatureCompleted event,
    Emitter<FinancialState> emit,
  ) async {
    final current = state;
    if (current is! FinancialSignatureInProgress) return;
    final result = await _getQuoteById(current.quote.id);
    result.fold(
      (f) => emit(FinancialError(message: f.message, quotes: current.quotes)),
      (quote) =>
          emit(FinancialQuoteDetail(quote: quote, quotes: current.quotes)),
    );
  }

  Future<void> _onPaymentRequested(
    FinancialPaymentRequested event,
    Emitter<FinancialState> emit,
  ) async {
    final current = state;
    if (current is! FinancialQuoteDetail) return;
    emit(FinancialPaymentInProgress(
      quote: current.quote,
      quotes: current.quotes,
    ));
    final result = await _initiateDeposit(
      quoteId: current.quote.id,
      idempotencyKey: event.idempotencyKey,
    );
    result.fold(
      (f) => emit(FinancialError(message: f.message, quotes: current.quotes)),
      (_) => emit(FinancialPaymentSuccess(
        quote: current.quote,
        quotes: current.quotes,
      )),
    );
  }

  List<Quote> _extractQuotes(FinancialState s) => switch (s) {
        FinancialLoaded(:final quotes) => quotes,
        FinancialQuoteDetail(:final quotes) => quotes,
        FinancialSignatureInProgress(:final quotes) => quotes,
        FinancialPaymentInProgress(:final quotes) => quotes,
        FinancialPaymentSuccess(:final quotes) => quotes,
        FinancialError(:final quotes) => quotes,
        _ => const [],
      };
}
