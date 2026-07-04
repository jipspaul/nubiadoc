import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class StockEvent extends Equatable {
  const StockEvent();

  @override
  List<Object?> get props => [];
}

class StockLoadRequested extends StockEvent {
  const StockLoadRequested();
}

class StockRespondRequested extends StockEvent {
  const StockRespondRequested(this.requestId, this.response, {this.note});

  final String requestId;
  final StockRequestResponse response;
  final String? note;

  @override
  List<Object?> get props => [requestId, response, note];
}

// ── States ────────────────────────────────────────────────────────────────────

sealed class StockState extends Equatable {
  const StockState();

  @override
  List<Object?> get props => [];
}

class StockLoading extends StockState {
  const StockLoading();
}

class StockLoaded extends StockState {
  const StockLoaded(this.requests, {this.respondingId});

  final List<StockRequest> requests;

  /// Demande dont la réponse est en cours (bouton en loading).
  final String? respondingId;

  @override
  List<Object?> get props => [requests, respondingId];
}

class StockError extends StockState {
  const StockError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Demandes de stock reçues par la pharmacie : accepter, refuser (note
/// optionnelle) puis honorer.
class StockBloc extends Bloc<StockEvent, StockState> {
  StockBloc({
    required ListStockRequestsUseCase list,
    required RespondStockRequestUseCase respond,
  })  : _list = list,
        _respond = respond,
        super(const StockLoading()) {
    on<StockLoadRequested>(_onLoad);
    on<StockRespondRequested>(_onRespond);
  }

  final ListStockRequestsUseCase _list;
  final RespondStockRequestUseCase _respond;

  Future<void> _onLoad(
      StockLoadRequested event, Emitter<StockState> emit) async {
    emit(const StockLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(StockError(failure.message)),
      (requests) => emit(StockLoaded(requests)),
    );
  }

  Future<void> _onRespond(
    StockRespondRequested event,
    Emitter<StockState> emit,
  ) async {
    final current = state;
    if (current is! StockLoaded || current.respondingId != null) return;

    emit(StockLoaded(current.requests, respondingId: event.requestId));
    final result =
        await _respond(event.requestId, event.response, note: event.note);
    result.fold(
      (failure) => emit(StockError(failure.message)),
      (updated) => emit(StockLoaded([
        for (final request in current.requests)
          if (request.id == updated.id) updated else request,
      ])),
    );
  }
}
