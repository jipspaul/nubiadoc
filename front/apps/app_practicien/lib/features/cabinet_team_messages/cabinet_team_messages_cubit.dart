//! Cubit de l'écran de messagerie interne d'équipe (#4156) — distinct de la
//! messagerie patient (`cabinet_messaging`). Fil unique par cabinet : charge
//! les messages (`GET .../messages`), permet d'en envoyer un (`POST`), puis
//! recharge le fil pour rester la source de vérité serveur (pas de merge
//! optimiste local — le fil est court/peu fréquent, un aller-retour est
//! largement assez rapide pour l'UX).

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetTeamMessagesState extends Equatable {
  const CabinetTeamMessagesState();

  @override
  List<Object?> get props => [];
}

class CabinetTeamMessagesLoading extends CabinetTeamMessagesState {
  const CabinetTeamMessagesLoading();
}

class CabinetTeamMessagesError extends CabinetTeamMessagesState {
  const CabinetTeamMessagesError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class CabinetTeamMessagesLoaded extends CabinetTeamMessagesState {
  const CabinetTeamMessagesLoaded({
    required this.messages,
    this.pinnedMessages = const [],
    this.practitioners = const [],
    this.practitionersInConsultation = const {},
    this.sending = false,
    this.sendError,
  });

  final List<CabinetTeamMessage> messages;

  /// Roster réel du cabinet (#6245) : remplace les identités de maquette
  /// figées du panneau « Équipe » — même source que l'agenda, déjà
  /// accessible sans restriction admin.
  final List<CabinetPractitioner> practitioners;

  /// Ids des praticiens ayant un RDV en cours à l'instant du chargement
  /// (#7668) : même dérivation que `PractitionerToday.isInConsultation` du
  /// tableau de bord, à partir de l'agenda du jour — aucun champ de
  /// présence dédié en base.
  final Set<String> practitionersInConsultation;
  final bool sending;
  final String? sendError;

  /// Consigne(s) épinglée(s) (#5130/#8205) : chargée(s) via un appel dédié
  /// (`GET .../pinned`), pas dérivée de `messages` — ce dernier ne porte que
  /// les messages les plus récents (défaut 100), donc un pin plus ancien que
  /// cette fenêtre disparaissait silencieusement du bloc « ÉPINGLÉ ».
  final List<CabinetTeamMessage> pinnedMessages;

  CabinetTeamMessagesLoaded copyWith({
    List<CabinetTeamMessage>? messages,
    List<CabinetTeamMessage>? pinnedMessages,
    List<CabinetPractitioner>? practitioners,
    Set<String>? practitionersInConsultation,
    bool? sending,
    String? sendError,
    bool clearSendError = false,
  }) =>
      CabinetTeamMessagesLoaded(
        messages: messages ?? this.messages,
        pinnedMessages: pinnedMessages ?? this.pinnedMessages,
        practitioners: practitioners ?? this.practitioners,
        practitionersInConsultation:
            practitionersInConsultation ?? this.practitionersInConsultation,
        sending: sending ?? this.sending,
        sendError: clearSendError ? null : (sendError ?? this.sendError),
      );

  @override
  List<Object?> get props => [
        messages,
        pinnedMessages,
        practitioners,
        practitionersInConsultation,
        sending,
        sendError,
      ];
}

class CabinetTeamMessagesCubit extends Cubit<CabinetTeamMessagesState> {
  CabinetTeamMessagesCubit({
    required ListCabinetTeamMessagesUseCase listMessages,
    required ListPinnedCabinetTeamMessagesUseCase listPinnedMessages,
    required SendCabinetTeamMessageUseCase sendMessage,
    required PinCabinetTeamMessageUseCase pinMessage,
    required UnpinCabinetTeamMessageUseCase unpinMessage,
    required ListCabinetPractitionersUseCase listPractitioners,
    required GetCabinetAgendaUseCase getAgenda,
  })  : _list = listMessages,
        _listPinned = listPinnedMessages,
        _send = sendMessage,
        _pin = pinMessage,
        _unpin = unpinMessage,
        _listPractitioners = listPractitioners,
        _getAgenda = getAgenda,
        super(const CabinetTeamMessagesLoading()) {
    load();
  }

  final ListCabinetTeamMessagesUseCase _list;
  final ListPinnedCabinetTeamMessagesUseCase _listPinned;
  final SendCabinetTeamMessageUseCase _send;
  final PinCabinetTeamMessageUseCase _pin;
  final UnpinCabinetTeamMessageUseCase _unpin;
  final ListCabinetPractitionersUseCase _listPractitioners;
  final GetCabinetAgendaUseCase _getAgenda;

  Future<void> load() async {
    emit(const CabinetTeamMessagesLoading());
    final messagesFuture = _list();
    final pinnedMessagesFuture = _listPinned();
    final practitionersFuture = _listPractitioners();
    final agendaFuture = _agendaToday();
    final result = await messagesFuture;
    final pinnedMessages = (await pinnedMessagesFuture).fold(
      (_) => const <CabinetTeamMessage>[],
      (p) => p,
    );
    final practitioners = (await practitionersFuture).fold(
      (_) => const <CabinetPractitioner>[],
      (p) => p,
    );
    final practitionersInConsultation = await agendaFuture;
    result.fold(
      (failure) => emit(CabinetTeamMessagesError(failure.message)),
      (messages) => emit(CabinetTeamMessagesLoaded(
        messages: messages,
        pinnedMessages: pinnedMessages,
        practitioners: practitioners,
        practitionersInConsultation: practitionersInConsultation,
      )),
    );
  }

  /// Ids des praticiens ayant un RDV en cours à l'instant présent (#7668) —
  /// best-effort : un échec de l'agenda laisse juste l'état de présence
  /// vide plutôt que de casser l'écran (même logique que le roster
  /// praticiens ci-dessus).
  Future<Set<String>> _agendaToday() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final result = await _getAgenda(weekStartDate);
    return result.fold(
      (_) => const <String>{},
      (entries) => {
        for (final entry in entries)
          if (!entry.isFree &&
              !entry.isCancelled &&
              !now.isBefore(entry.startsAt) &&
              now.isBefore(entry.endsAt))
            entry.practitionerId,
      },
    );
  }

  /// `pin` (#5130/#8181) : épingle le message juste après son envoi — le
  /// composeur n'a pas de notion de message sélectionné, seulement du
  /// prochain message à expédier (toggle « Épingler » du composeur).
  Future<void> send(String body, {bool pin = false}) async {
    final current = state;
    if (current is! CabinetTeamMessagesLoaded) return;
    emit(current.copyWith(sending: true, clearSendError: true));
    final result = await _send(body);
    await result.fold(
      (failure) async =>
          emit(current.copyWith(sending: false, sendError: failure.message)),
      (messageId) async {
        if (pin) {
          await _pin(messageId);
        }
        await load();
      },
    );
  }

  /// `unpin` (#8204) : désépingle un message, pendant de [pin] ci-dessus —
  /// avant ça, `pinned` n'avait aucun sens inverse (ni route, ni contrôle).
  Future<void> unpin(String messageId) async {
    await _unpin(messageId);
    await load();
  }
}
