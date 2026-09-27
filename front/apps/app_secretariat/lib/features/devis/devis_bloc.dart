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
  final RemindCabinetQuoteUseCase _remind;

  DevisBloc({
    required ListCabinetQuotesUseCase listQuotes,
    required GetCabinetQuoteUseCase getQuote,
    required SendCabinetQuoteUseCase sendQuote,
    required RemindCabinetQuoteUseCase remindQuote,
  })  : _list = listQuotes,
        _getById = getQuote,
        _send = sendQuote,
        _remind = remindQuote,
        super(const DevisInitial()) {
    on<DevisLoadRequested>(_onLoad);
    on<DevisDetailLoadRequested>(_onDetailLoad);
    on<DevisSendRequested>(_onSendRequested);
    on<DevisRemindRequested>(_onRemindRequested);
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
  ///
  /// #5087 : l'action est aussi déclenchable ligne par ligne depuis la liste
  /// (`state is DevisLoaded`) — le devis ciblé est alors retrouvé dans
  /// `quotes` par id plutôt que lu depuis un détail déjà chargé.
  Future<void> _onSendRequested(
    DevisSendRequested event,
    Emitter<DevisState> emit,
  ) async {
    final current = state;
    final CabinetQuote? maybeQuote;
    if (current is DevisDetailLoaded) {
      maybeQuote = current.quote;
    } else if (current is DevisLoaded) {
      maybeQuote = _findQuote(current.quotes, event.id);
    } else {
      maybeQuote = null;
    }
    if (maybeQuote == null) return;
    final quote = maybeQuote;

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

  /// #6970 : relance un devis déjà `sent` — même résolution du devis ciblé
  /// que [_onSendRequested] (détail déjà chargé ou retrouvé par id dans la
  /// liste), mais sans réécrire le statut : la relance ne fait pas
  /// transiter le devis, elle ne fait que renotifier le patient.
  Future<void> _onRemindRequested(
    DevisRemindRequested event,
    Emitter<DevisState> emit,
  ) async {
    final current = state;
    final CabinetQuote? maybeQuote;
    if (current is DevisDetailLoaded) {
      maybeQuote = current.quote;
    } else if (current is DevisLoaded) {
      maybeQuote = _findQuote(current.quotes, event.id);
    } else {
      maybeQuote = null;
    }
    if (maybeQuote == null) return;
    final quote = maybeQuote;

    emit(DevisRemindInProgress(quote));
    try {
      final result = await _remind(quote.id);
      result.fold(
        (failure) => safeEmit(
          DevisRemindFailure(quote: quote, message: failure.message),
        ),
        (_) => safeEmit(DevisReminded(quote)),
      );
    } catch (_) {
      safeEmit(
        DevisRemindFailure(quote: quote, message: 'Relance impossible.'),
      );
    }
  }

  CabinetQuote? _findQuote(List<CabinetQuote> quotes, String id) {
    for (final quote in quotes) {
      if (quote.id == id) return quote;
    }
    return null;
  }

  /// Copie le devis avec le statut confirmé par le serveur (le domaine
  /// n'expose pas de `copyWith`).
  CabinetQuote _withStatus(CabinetQuote quote, CabinetQuoteStatus status) =>
      CabinetQuote(
        id: quote.id,
        quoteRef: quote.quoteRef,
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
        isOverdue: quote.isOverdue,
      );
}
