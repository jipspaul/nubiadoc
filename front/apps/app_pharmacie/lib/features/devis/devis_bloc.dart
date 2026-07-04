import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class PharmacyDevisEvent extends Equatable {
  const PharmacyDevisEvent();

  @override
  List<Object?> get props => [];
}

class PharmacyDevisLoadRequested extends PharmacyDevisEvent {
  const PharmacyDevisLoadRequested();
}

class PharmacyDevisSendRequested extends PharmacyDevisEvent {
  const PharmacyDevisSendRequested(this.quoteId);

  final String quoteId;

  @override
  List<Object?> get props => [quoteId];
}

// ── States ────────────────────────────────────────────────────────────────────

sealed class PharmacyDevisState extends Equatable {
  const PharmacyDevisState();

  @override
  List<Object?> get props => [];
}

class PharmacyDevisLoading extends PharmacyDevisState {
  const PharmacyDevisLoading();
}

class PharmacyDevisLoaded extends PharmacyDevisState {
  const PharmacyDevisLoaded(this.quotes, {this.sendingId});

  final List<PharmacyQuote> quotes;
  final String? sendingId;

  @override
  List<Object?> get props => [quotes, sendingId];
}

class PharmacyDevisError extends PharmacyDevisState {
  const PharmacyDevisError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Devis d'officine : liste + envoi des brouillons (la création se fait
/// depuis le détail d'une commande).
class PharmacyDevisBloc extends Bloc<PharmacyDevisEvent, PharmacyDevisState> {
  PharmacyDevisBloc({
    required ListPharmacyQuotesUseCase list,
    required SendPharmacyQuoteUseCase send,
  })  : _list = list,
        _send = send,
        super(const PharmacyDevisLoading()) {
    on<PharmacyDevisLoadRequested>(_onLoad);
    on<PharmacyDevisSendRequested>(_onSend);
  }

  final ListPharmacyQuotesUseCase _list;
  final SendPharmacyQuoteUseCase _send;

  Future<void> _onLoad(
    PharmacyDevisLoadRequested event,
    Emitter<PharmacyDevisState> emit,
  ) async {
    emit(const PharmacyDevisLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(PharmacyDevisError(failure.message)),
      (quotes) => emit(PharmacyDevisLoaded(quotes)),
    );
  }

  Future<void> _onSend(
    PharmacyDevisSendRequested event,
    Emitter<PharmacyDevisState> emit,
  ) async {
    final current = state;
    if (current is! PharmacyDevisLoaded || current.sendingId != null) return;

    emit(PharmacyDevisLoaded(current.quotes, sendingId: event.quoteId));
    final result = await _send(event.quoteId);
    result.fold(
      (failure) => emit(PharmacyDevisError(failure.message)),
      (updated) => emit(PharmacyDevisLoaded([
        for (final quote in current.quotes)
          if (quote.id == updated.id) updated else quote,
      ])),
    );
  }
}
