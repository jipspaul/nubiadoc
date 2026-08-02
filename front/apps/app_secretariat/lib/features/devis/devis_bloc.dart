import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_event.dart';
import 'devis_state.dart';

class DevisBloc extends Bloc<DevisEvent, DevisState>
    with SafeEmitMixin<DevisState> {
  final ListCabinetQuotesUseCase _list;
  final GetCabinetQuoteUseCase _getById;
  final SendCabinetQuoteUseCase _send;

  DevisBloc({
    required ListCabinetQuotesUseCase listQuotes,
    required GetCabinetQuoteUseCase getQuote,
    required SendCabinetQuoteUseCase sendQuote,
  })  : _list = listQuotes,
        _getById = getQuote,
        _send = sendQuote,
        super(const DevisInitial()) {
    on<DevisLoadRequested>(_onLoad);
    on<DevisDetailLoadRequested>(_onDetailLoad);
    on<DevisSendRequested>(_onSendRequested);
  }

  Future<void> _onLoad(
    DevisLoadRequested event,
    Emitter<DevisState> emit,
  ) async {
    emit(const DevisLoading());
    try {
      final result = await _list();
      result.fold(
        (failure) => safeEmit(DevisError(failure.message)),
        (quotes) => safeEmit(DevisLoaded(quotes)),
      );
    } catch (_) {
      safeEmit(const DevisError('Erreur de chargement.'));
    }
  }

  Future<void> _onDetailLoad(
    DevisDetailLoadRequested event,
    Emitter<DevisState> emit,
  ) async {
    emit(const DevisLoading());
    try {
      final result = await _getById(event.id);
      result.fold(
        (failure) => safeEmit(DevisDetailError(failure.message)),
        (quote) => safeEmit(DevisDetailLoaded(quote)),
      );
    } catch (_) {
      safeEmit(const DevisDetailError('Erreur de chargement.'));
    }
  }

  /// #4537 : envoie un devis brouillon au patient. Le back autorise déjà
  /// `secretary+` (`ProSecretaryPlusClaims`) — mêmes états que la version
  /// praticien (`DevisSendInProgress`/`DevisSent`/`DevisSendFailure`).
  Future<void> _onSendRequested(
    DevisSendRequested event,
    Emitter<DevisState> emit,
  ) async {
    final current = state;
    if (current is! DevisDetailLoaded) return;

    final quote = current.quote;
    emit(DevisSendInProgress(quote));
    try {
      final result = await _send(quote.id);
      result.fold(
        (failure) => safeEmit(
          DevisSendFailure(quote: quote, message: failure.message),
        ),
        (status) => safeEmit(DevisSent(_withStatus(quote, status))),
      );
    } catch (_) {
      safeEmit(DevisSendFailure(quote: quote, message: 'Envoi impossible.'));
    }
  }

  /// Copie le devis avec le statut confirmé par le serveur (le domaine
  /// n'expose pas de `copyWith`).
  CabinetQuote _withStatus(CabinetQuote quote, CabinetQuoteStatus status) =>
      CabinetQuote(
        id: quote.id,
        cabinetId: quote.cabinetId,
        patientId: quote.patientId,
        patientName: quote.patientName,
        totalCents: quote.totalCents,
        patientShareCents: quote.patientShareCents,
        status: status,
        createdAt: quote.createdAt,
        signedAt: quote.signedAt,
        expiresAt: quote.expiresAt,
        items: quote.items,
      );
}
