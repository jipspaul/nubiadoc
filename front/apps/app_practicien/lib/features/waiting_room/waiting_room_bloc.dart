import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomBloc extends Bloc<WaitingRoomEvent, WaitingRoomState>
    with SafeEmitMixin<WaitingRoomState> {
  final ListWaitingRoomUseCase _listWaitingRoom;
  final CallNextUseCase _callNext;

  WaitingRoomBloc({
    required ListWaitingRoomUseCase listWaitingRoom,
    required CallNextUseCase callNext,
  })  : _listWaitingRoom = listWaitingRoom,
        _callNext = callNext,
        super(const WaitingRoomInitial()) {
    on<WaitingRoomLoadRequested>(_onLoad);
    on<WaitingRoomCallNextRequested>(_onCallNext);
  }

  Future<void> _onLoad(
    WaitingRoomLoadRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    final previous = state;
    emit(const WaitingRoomLoading());
    try {
      final result = await _listWaitingRoom();
      result.fold(
        (failure) => safeEmit(_onLoadFailure(previous, failure.message)),
        (entries) => safeEmit(WaitingRoomLoaded(entries: entries)),
      );
    } catch (_) {
      safeEmit(_onLoadFailure(previous, 'Erreur de chargement.'));
    }
  }

  /// Un échec de CHARGEMENT INITIAL (aucune liste encore affichée) est
  /// bloquant : `WaitingRoomError` plein écran. Un échec de RECHARGEMENT
  /// (une liste était déjà affichée) ne l'est jamais : la liste est
  /// conservée et l'erreur posée en `reloadError` (bandeau non bloquant).
  WaitingRoomState _onLoadFailure(WaitingRoomState previous, String message) {
    if (previous is WaitingRoomLoaded) {
      return previous.copyWith(actionInProgress: false, reloadError: message);
    }
    return WaitingRoomError(message);
  }

  Future<void> _onCallNext(
    WaitingRoomCallNextRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    final current = state;
    if (current is! WaitingRoomLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _callNext();
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) async => _onLoad(const WaitingRoomLoadRequested(), emit),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }
}
