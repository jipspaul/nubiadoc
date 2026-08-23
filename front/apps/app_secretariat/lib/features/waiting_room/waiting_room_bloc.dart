import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomBloc extends Bloc<WaitingRoomEvent, WaitingRoomState>
    with SafeEmitMixin<WaitingRoomState> {
  final ListWaitingRoomUseCase _list;
  final CallNextUseCase _callNext;

  WaitingRoomBloc({
    required ListWaitingRoomUseCase listWaitingRoom,
    required CallNextUseCase callNext,
  })  : _list = listWaitingRoom,
        _callNext = callNext,
        super(const WaitingRoomInitial()) {
    on<WaitingRoomLoadRequested>(_onLoad);
    on<WaitingRoomCallNextRequested>(_onCallNext);
    on<WaitingRoomCallRequested>(_onCallRequested);
  }

  Future<void> _onLoad(
    WaitingRoomLoadRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    // Une fois une première liste chargée, un rechargement (bouton manuel ou
    // rafraîchissement périodique, #5161) ne repasse plus par
    // WaitingRoomLoading — l'ancienne liste reste affichée pendant l'appel,
    // évitant le spinner plein écran qui clignoterait en boucle.
    if (state is! WaitingRoomLoaded) {
      emit(const WaitingRoomLoading());
    }
    try {
      final result = await _list();
      result.fold(
        (failure) => safeEmit(WaitingRoomError(failure.message)),
        (entries) => safeEmit(WaitingRoomLoaded(entries)),
      );
    } catch (_) {
      safeEmit(const WaitingRoomError('Erreur de chargement.'));
    }
  }

  Future<void> _onCallNext(
    WaitingRoomCallNextRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    try {
      final result = await _callNext();
      await result.fold(
        (failure) async => safeEmit(WaitingRoomError(failure.message)),
        (_) async => _onLoad(const WaitingRoomLoadRequested(), emit),
      );
    } catch (_) {
      safeEmit(const WaitingRoomError('Erreur inattendue.'));
    }
  }

  /// Appel d'une entrée précise (#5166 — bouton « Appeler » par ligne).
  /// La tête de file peut être appelée : c'est équivalent à « appeler le
  /// suivant ». Cibler une autre entrée nécessite un endpoint back dédié qui
  /// n'existe pas encore (`CallNextUseCase` n'appelle que la tête de file) :
  /// en attendant, la demande est ignorée sans réordonner ni appeler
  /// personne d'autre.
  Future<void> _onCallRequested(
    WaitingRoomCallRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    final current = state;
    if (current is! WaitingRoomLoaded || current.entries.isEmpty) return;
    if (current.entries.first.id != event.entryId) return;
    await _onCallNext(const WaitingRoomCallNextRequested(), emit);
  }
}
