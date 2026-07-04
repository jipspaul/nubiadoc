import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_event.dart';
import 'devis_state.dart';

/// Bloc du parcours devis / plan de traitement (vue praticien).
///
/// S'appuie sur les use cases cabinet déjà branchés côté data
/// ([ListCabinetQuotesUseCase], [GetCabinetQuoteUseCase]). L'envoi au patient
/// est traité comme un placeholder optimiste tant que l'endpoint dédié n'est
/// pas exposé (cf. signature eIDAS du WEDGE patient).
class DevisBloc extends Bloc<DevisEvent, DevisState> {
  final ListCabinetQuotesUseCase _list;
  final GetCabinetQuoteUseCase _getById;

  DevisBloc({
    required ListCabinetQuotesUseCase list,
    required GetCabinetQuoteUseCase getById,
  })  : _list = list,
        _getById = getById,
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
    if (state is DevisSendInProgress) return;

    final quote = current.quote;
    emit(DevisSendInProgress(quote));
    // Placeholder : l'envoi réel (POST /v1/cabinet/quotes/:id/send) sera branché
    // ultérieurement. On confirme la transition brouillon → envoyé côté UI.
    emit(DevisSent(_asSent(quote)));
  }

  /// Copie le devis avec un statut « envoyé » (le domaine n'expose pas de
  /// `copyWith`).
  CabinetQuote _asSent(CabinetQuote quote) => CabinetQuote(
        id: quote.id,
        cabinetId: quote.cabinetId,
        patientId: quote.patientId,
        patientName: quote.patientName,
        totalCents: quote.totalCents,
        patientShareCents: quote.patientShareCents,
        status: CabinetQuoteStatus.sent,
        createdAt: quote.createdAt,
        signedAt: quote.signedAt,
        expiresAt: quote.expiresAt,
        items: quote.items,
      );
}
