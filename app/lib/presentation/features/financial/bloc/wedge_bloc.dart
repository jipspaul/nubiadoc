import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_event.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_state.dart';

/// Bloc du flux wedge : Détail devis → Signature Yousign → Paiement acompte.
///
/// Un seul Bloc couvre les trois étapes pour partager l'objet [Quote] et
/// l'idempotency-key de paiement sans prop-drilling.
@injectable
class WedgeBloc extends Bloc<WedgeEvent, WedgeState> {
  WedgeBloc(this._billing) : super(const WedgeLoading()) {
    on<WedgeQuoteLoadRequested>(_onLoadRequested);
    on<WedgeSignatureRequested>(_onSignatureRequested);
    on<WedgeSignatureCallbackReceived>(_onSignatureCallback);
    on<WedgeDepositRequested>(_onDepositRequested);
    on<WedgeDepositRetryRequested>(_onDepositRetry);
  }

  final BillingRepository _billing;

  // Mémorise l'idempotency-key pour les retries de paiement.
  String? _depositIdempotencyKey;

  Future<void> _onLoadRequested(
    WedgeQuoteLoadRequested event,
    Emitter<WedgeState> emit,
  ) async {
    emit(const WedgeLoading());
    final result = await _billing.getQuoteById(event.quoteId);
    result.fold(
      (failure) => emit(WedgeError(message: failure.message)),
      (quote) {
        if (quote.isExpired) {
          emit(WedgeQuoteExpired(quote));
        } else {
          emit(WedgeQuoteLoaded(quote));
        }
      },
    );
  }

  Future<void> _onSignatureRequested(
    WedgeSignatureRequested event,
    Emitter<WedgeState> emit,
  ) async {
    final current = state;
    if (current is! WedgeQuoteLoaded) return;

    final quote = current.quote;
    if (quote.isExpired) {
      emit(WedgeQuoteExpired(quote));
      return;
    }

    final result = await _billing.initiateSignature(quote.id);
    result.fold(
      (failure) => emit(WedgeError(message: failure.message, quote: quote)),
      (url) => emit(WedgeSignatureInProgress(quote: quote, signatureUrl: url)),
    );
  }

  Future<void> _onSignatureCallback(
    WedgeSignatureCallbackReceived event,
    Emitter<WedgeState> emit,
  ) async {
    final current = state;
    if (current is! WedgeSignatureInProgress) return;

    final result = await _billing.confirmSignature(current.quote.id);
    result.fold(
      (failure) => emit(
          WedgeError(message: failure.message, quote: current.quote)),
      (updatedQuote) => emit(WedgeSignatureDone(updatedQuote)),
    );
  }

  Future<void> _onDepositRequested(
    WedgeDepositRequested event,
    Emitter<WedgeState> emit,
  ) async {
    final current = state;
    if (current is! WedgeSignatureDone) return;

    final quote = current.quote;

    // Acompte = 0 → skip directement vers le succès.
    if (quote.depositCents == 0) {
      emit(WedgePaymentSuccess(quote));
      return;
    }

    _depositIdempotencyKey = event.idempotencyKey;
    await _processDeposit(quote, event.idempotencyKey, emit);
  }

  Future<void> _onDepositRetry(
    WedgeDepositRetryRequested event,
    Emitter<WedgeState> emit,
  ) async {
    final current = state;
    Quote? quote;
    if (current is WedgeError) {
      quote = current.quote;
    }
    if (quote == null || _depositIdempotencyKey == null) return;

    await _processDeposit(quote, _depositIdempotencyKey!, emit);
  }

  Future<void> _processDeposit(
    Quote quote,
    String idempotencyKey,
    Emitter<WedgeState> emit,
  ) async {
    emit(WedgePaymentInProgress(quote: quote, idempotencyKey: idempotencyKey));

    final result = await _billing.initiateDeposit(
      quoteId: quote.id,
      idempotencyKey: idempotencyKey,
    );

    result.fold(
      (failure) =>
          emit(WedgeError(message: failure.message, quote: quote)),
      (_) => emit(WedgePaymentSuccess(quote)),
    );
  }
}
