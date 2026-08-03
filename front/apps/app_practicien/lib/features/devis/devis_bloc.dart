import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_event.dart';
import 'devis_state.dart';

/// Bloc du parcours devis / plan de traitement (vue praticien).
///
/// S'appuie sur les use cases cabinet ([ListCabinetQuotesUseCase],
/// [GetCabinetQuoteUseCase], [SendCabinetQuoteUseCase]). L'envoi déclenche un
/// appel réseau réel (`POST /v1/cabinet/quotes/:id/send`) : le devis passe à
/// `sent` côté serveur et devient visible pour le patient.
class DevisBloc extends Bloc<DevisEvent, DevisState> {
  final ListCabinetQuotesUseCase _list;
  final GetCabinetQuoteUseCase _getById;
  final SendCabinetQuoteUseCase _send;

  DevisBloc({
    required ListCabinetQuotesUseCase list,
    required GetCabinetQuoteUseCase getById,
    required SendCabinetQuoteUseCase send,
  })  : _list = list,
        _getById = getById,
        _send = send,
        super(const DevisInitial()) {
    on<DevisListRequested>(_onListRequested);
    on<DevisQuoteSelected>(_onQuoteSelected);
    on<DevisBackToList>(_onBackToList);
    on<DevisSendRequested>(_onSendRequested);
  }

  Future<void> _onListRequested(
    DevisListRequested event,
    Emitter<DevisState> emit,
  ) async {
    emit(const DevisLoading());
    try {
      final result = await _list();
      result.fold(
        (failure) => emit(DevisError(failure.message)),
        (quotes) => emit(DevisListLoaded(quotes)),
      );
    } catch (_) {
      emit(const DevisError('Impossible de charger les devis.'));
    }
  }

  Future<void> _onQuoteSelected(
    DevisQuoteSelected event,
    Emitter<DevisState> emit,
  ) async {
    emit(const DevisLoading());
    try {
      final result = await _getById(event.id);
      result.fold(
        (failure) => emit(DevisError(failure.message)),
        (quote) => emit(DevisDetailLoaded(quote)),
      );
    } catch (_) {
      emit(const DevisError('Impossible de charger le devis.'));
    }
  }

  Future<void> _onBackToList(
    DevisBackToList event,
    Emitter<DevisState> emit,
  ) async {
    add(const DevisListRequested());
  }

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
        (failure) =>
            emit(DevisSendFailure(quote: quote, message: failure.message)),
        (status) => emit(DevisSent(_withStatus(quote, status))),
      );
    } catch (_) {
      emit(DevisSendFailure(quote: quote, message: 'Envoi impossible.'));
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
