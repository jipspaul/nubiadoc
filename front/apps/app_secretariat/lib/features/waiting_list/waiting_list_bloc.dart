import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_list_event.dart';
import 'waiting_list_state.dart';

class WaitingListBloc extends Bloc<WaitingListEvent, WaitingListState> {
  final ListWaitingListUseCase _list;
  final OfferSlotToWaitingPatientUseCase _offerSlot;

  WaitingListBloc({
    required ListWaitingListUseCase listWaitingList,
    required OfferSlotToWaitingPatientUseCase offerSlot,
  })  : _list = listWaitingList,
        _offerSlot = offerSlot,
        super(const WaitingListInitial()) {
    on<WaitingListLoadRequested>(_onLoad);
    on<WaitingListOfferSlotRequested>(_onOfferSlot);
  }

  Future<void> _onLoad(
    WaitingListLoadRequested event,
    Emitter<WaitingListState> emit,
  ) async {
    emit(const WaitingListLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(WaitingListError(failure.message)),
      (entries) => emit(WaitingListLoaded(entries)),
    );
  }

  Future<void> _onOfferSlot(
    WaitingListOfferSlotRequested event,
    Emitter<WaitingListState> emit,
  ) async {
    final result = await _offerSlot(event.id);
    await result.fold(
      (failure) async => emit(WaitingListError(failure.message)),
      (_) async {
        emit(const WaitingListOfferSuccess());
        await _onLoad(const WaitingListLoadRequested(), emit);
      },
    );
  }
}
