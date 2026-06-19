import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomBloc extends Bloc<WaitingRoomEvent, WaitingRoomState> {
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
  }

  Future<void> _onLoad(
    WaitingRoomLoadRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    emit(const WaitingRoomLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(WaitingRoomError(failure.message)),
      (entries) => emit(WaitingRoomLoaded(entries)),
    );
  }

  Future<void> _onCallNext(
    WaitingRoomCallNextRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    final result = await _callNext();
    await result.fold(
      (failure) async => emit(WaitingRoomError(failure.message)),
      (_) async => _onLoad(const WaitingRoomLoadRequested(), emit),
    );
  }
}
