import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomBloc extends Bloc<WaitingRoomEvent, WaitingRoomState>
    with SafeEmitMixin<WaitingRoomState> {
  final ListWaitingRoomUseCase _list;
  final CallNextUseCase _callNext;
  final NotifyWaitingRoomPractitionerUseCase _notifyPractitioner;

  WaitingRoomBloc({
    required ListWaitingRoomUseCase listWaitingRoom,
    required CallNextUseCase callNext,
    required NotifyWaitingRoomPractitionerUseCase notifyPractitioner,
  })  : _list = listWaitingRoom,
        _callNext = callNext,
        _notifyPractitioner = notifyPractitioner,
        super(const WaitingRoomInitial()) {
    on<WaitingRoomLoadRequested>(_onLoad);
    on<WaitingRoomCallNextRequested>(_onCallNext);
    on<WaitingRoomCallRequested>(_onCallRequested);
    // droppable() : un 2e WaitingRoomNotifyPractitionerRequested arrivant
    // pendant que le précédent est en cours est ignoré — évite le double
    // POST .../notify-practitioner (= doublon de notification/push côté
    // praticien) sur double-clic du CTA « Prévenir le praticien » (#8449).
    on<WaitingRoomNotifyPractitionerRequested>(_onNotifyPractitioner,
        transformer: droppable());
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
    final current = state;
    // Échec d'action signalé en ligne, sans jamais masquer une liste déjà
    // chargée (#5159) — WaitingRoomError reste réservé à l'échec du
    // chargement initial (état non-Loaded).
    if (current is! WaitingRoomLoaded) {
      try {
        final result = await _callNext();
        await result.fold(
          (failure) async => safeEmit(WaitingRoomError(failure.message)),
          (_) async => _onLoad(const WaitingRoomLoadRequested(), emit),
        );
      } catch (_) {
        safeEmit(const WaitingRoomError('Erreur inattendue.'));
      }
      return;
    }
    safeEmit(current.copyWith(actionInProgress: true, clearActionError: true));
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

  /// Appel d'une entrée précise (#5166 — bouton « Appeler » par ligne).
  /// La tête de file peut être appelée : c'est équivalent à « appeler le
  /// suivant ». Cibler une autre entrée nécessite un endpoint back dédié qui
  /// n'existe pas encore (`CallNextUseCase` n'appelle que la tête de file) :
  /// en attendant, la demande est refusée avec un `actionError` explicite
  /// (#6629 — le bouton reste actif sur chaque ligne comme dans la maquette,
  /// mais ne doit plus jamais rester muet : la même bannière que pour un
  /// échec réseau prévient l'utilisateur plutôt que d'ignorer le clic en
  /// silence).
  ///
  /// La tête de file est le premier `isWaiting` de la liste, pas
  /// `entries.first` (#7570) : une entrée `in_consultation` en tête de liste
  /// n'attend plus, elle ne doit ni être appelable, ni bloquer l'appel du
  /// vrai suivant.
  Future<void> _onCallRequested(
    WaitingRoomCallRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    final current = state;
    if (current is! WaitingRoomLoaded || current.entries.isEmpty) return;
    WaitingRoomEntry? nextToCall;
    for (final entry in current.entries) {
      if (entry.isWaiting) {
        nextToCall = entry;
        break;
      }
    }
    if (nextToCall == null || nextToCall.id != event.entryId) {
      safeEmit(current.copyWith(
        actionError:
            "Seul le patient en tête de file peut être appelé pour l'instant.",
      ));
      return;
    }
    await _onCallNext(const WaitingRoomCallNextRequested(), emit);
  }

  /// CTA « Prévenir le praticien » du bandeau d'escalade (#5170/#6696).
  /// Sans effet sur [WaitingRoomLoaded.entries] : le retour utilisateur passe
  /// par [WaitingRoomLoaded.actionNotice]/[WaitingRoomLoaded.actionError],
  /// pas par un rechargement de la liste.
  Future<void> _onNotifyPractitioner(
    WaitingRoomNotifyPractitionerRequested event,
    Emitter<WaitingRoomState> emit,
  ) async {
    final current = state;
    if (current is! WaitingRoomLoaded) return;
    safeEmit(current.copyWith(
      actionInProgress: true,
      clearActionError: true,
      clearActionNotice: true,
    ));
    try {
      final result = await _notifyPractitioner(event.entryId);
      result.fold(
        (failure) => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) => safeEmit(current.copyWith(
          actionInProgress: false,
          actionNotice: 'Praticien prévenu.',
        )),
      );
    } catch (_) {
      safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: 'Erreur inattendue.',
      ));
    }
  }
}
