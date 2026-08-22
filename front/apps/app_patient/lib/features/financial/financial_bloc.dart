import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'financial_event.dart';
import 'financial_state.dart';

/// Bloc du wedge financier : liste devis → détail → signature Yousign → paiement acompte.
class FinancialBloc extends Bloc<FinancialEvent, FinancialState>
    with SafeEmitMixin<FinancialState> {
  FinancialBloc({
    required GetPendingQuotesUseCase getPendingQuotes,
    required GetQuoteByIdUseCase getQuoteById,
    required InitiateSignatureUseCase initiateSignature,
    required InitiateDepositUseCase initiateDeposit,
    required GetDocumentSignedUrlUseCase getDocumentSignedUrl,
  })  : _getPendingQuotes = getPendingQuotes,
        _getQuoteById = getQuoteById,
        _initiateSignature = initiateSignature,
        _initiateDeposit = initiateDeposit,
        _getDocumentSignedUrl = getDocumentSignedUrl,
        super(const FinancialInitial()) {
    on<FinancialLoadRequested>(_onLoad);
    on<FinancialQuoteSelected>(_onQuoteSelected);
    on<FinancialBackToList>(_onBackToList);
    on<FinancialSignatureRequested>(_onSignatureRequested);
    on<FinancialPaymentRequested>(_onPaymentRequested);
    on<FinancialDownloadRequested>(_onDownloadRequested);
  }

  final GetPendingQuotesUseCase _getPendingQuotes;
  final GetQuoteByIdUseCase _getQuoteById;
  final InitiateSignatureUseCase _initiateSignature;
  final InitiateDepositUseCase _initiateDeposit;
  final GetDocumentSignedUrlUseCase _getDocumentSignedUrl;

  Future<void> _onLoad(
    FinancialLoadRequested event,
    Emitter<FinancialState> emit,
  ) async {
    emit(const FinancialLoading());
    try {
      final result = await _getPendingQuotes();
      result.fold(
        (f) => safeEmit(FinancialError(message: f.message)),
        (quotes) => safeEmit(FinancialLoaded(quotes)),
      );
    } catch (_) {
      safeEmit(const FinancialError(message: 'Erreur de chargement.'));
    }
  }

  Future<void> _onQuoteSelected(
    FinancialQuoteSelected event,
    Emitter<FinancialState> emit,
  ) async {
    final prevQuotes = _extractQuotes(state);
    emit(const FinancialLoading());
    try {
      final result = await _getQuoteById(event.quoteId);
      result.fold(
        (f) => safeEmit(FinancialError(message: f.message, quotes: prevQuotes)),
        (quote) =>
            safeEmit(FinancialQuoteDetail(quote: quote, quotes: prevQuotes)),
      );
    } catch (_) {
      safeEmit(
          FinancialError(message: 'Erreur de chargement.', quotes: prevQuotes));
    }
  }

  void _onBackToList(
    FinancialBackToList event,
    Emitter<FinancialState> emit,
  ) {
    final quotes = _extractQuotes(state);
    emit(FinancialLoaded(quotes));
  }

  // Signature synchrone (stub Yousign, cf. api/src/billing.rs sign_quote) :
  // pas de redirection à attendre, le devis est signé et verrouillé dès la
  // réponse de _initiateSignature. On réémet directement FinancialQuoteDetail
  // avec le devis à jour (#3705 — avant, un état intermédiaire attendait une
  // confirmation qui n'arrivait jamais que via un bouton manuel).
  Future<void> _onSignatureRequested(
    FinancialSignatureRequested event,
    Emitter<FinancialState> emit,
  ) async {
    final current = state;
    if (current is! FinancialQuoteDetail) return;
    try {
      final result = await _initiateSignature(current.quote.id);
      result.fold(
        (f) => safeEmit(
            FinancialError(message: f.message, quotes: current.quotes)),
        (quote) =>
            safeEmit(FinancialQuoteDetail(quote: quote, quotes: current.quotes)),
      );
    } catch (_) {
      safeEmit(FinancialError(
          message: 'Erreur lors de la signature.', quotes: current.quotes));
    }
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
    try {
      final result = await _initiateDeposit(
        quoteId: current.quote.id,
        idempotencyKey: event.idempotencyKey,
      );
      result.fold(
        (f) => safeEmit(
            FinancialError(message: f.message, quotes: current.quotes)),
        (_) => safeEmit(FinancialPaymentSuccess(
          quote: current.quote,
          quotes: current.quotes,
        )),
      );
    } catch (_) {
      safeEmit(FinancialError(
          message: 'Erreur lors du paiement.', quotes: current.quotes));
    }
  }

  Future<void> _onDownloadRequested(
    FinancialDownloadRequested event,
    Emitter<FinancialState> emit,
  ) async {
    final current = state;
    if (current is! FinancialQuoteDetail) return;
    final documentId = current.quote.documentId;
    if (documentId == null) return;
    try {
      final result = await _getDocumentSignedUrl(documentId);
      result.fold(
        (f) => safeEmit(
            FinancialError(message: f.message, quotes: current.quotes)),
        (url) => safeEmit(FinancialQuoteDetail(
          quote: current.quote,
          quotes: current.quotes,
          documentUrl: url,
        )),
      );
    } catch (_) {
      safeEmit(FinancialError(
          message: 'Erreur lors du téléchargement.', quotes: current.quotes));
    }
  }

  List<Quote> _extractQuotes(FinancialState s) => switch (s) {
        FinancialLoaded(:final quotes) => quotes,
        FinancialQuoteDetail(:final quotes) => quotes,
        FinancialPaymentInProgress(:final quotes) => quotes,
        FinancialPaymentSuccess(:final quotes) => quotes,
        FinancialError(:final quotes) => quotes,
        _ => const [],
      };
}
