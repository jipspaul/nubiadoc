import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_list_event.dart';
import 'waiting_list_state.dart';

class WaitingListBloc extends Bloc<WaitingListEvent, WaitingListState>
    with SafeEmitMixin<WaitingListState> {
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
    try {
      final result = await _list();
      result.fold(
        (failure) => safeEmit(WaitingListError(failure.message)),
        (entries) => safeEmit(WaitingListLoaded(entries)),
      );
    } catch (_) {
      safeEmit(const WaitingListError('Erreur de chargement.'));
    }
  }

  Future<void> _onOfferSlot(
    WaitingListOfferSlotRequested event,
    Emitter<WaitingListState> emit,
  ) async {
    // #4536 : un échec de « Combler » ne doit jamais remplacer toute la
    // liste par l'état d'erreur plein écran (réservé à l'échec du
    // CHARGEMENT) — on garde les entrées déjà affichées.
    final currentEntries =
        state is WaitingListLoaded ? (state as WaitingListLoaded).entries : const <WaitingListEntry>[];
    try {
      final result = await _offerSlot(event.id);
      await result.fold(
        (failure) async =>
            safeEmit(WaitingListOfferError(failure.message, currentEntries)),
        (_) async {
          safeEmit(const WaitingListOfferSuccess());
          await _onLoad(const WaitingListLoadRequested(), emit);
        },
      );
    } catch (_) {
      safeEmit(WaitingListOfferError('Erreur inattendue.', currentEntries));
    }
  }
}
