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
    this.practitioners = const [],
    this.sending = false,
    this.sendError,
  });

  final List<CabinetTeamMessage> messages;

  /// Roster réel du cabinet (#6245) : remplace les identités de maquette
  /// figées du panneau « Équipe » — même source que l'agenda secrétariat,
  /// déjà accessible sans restriction admin.
  final List<CabinetPractitioner> practitioners;
  final bool sending;
  final String? sendError;

  /// Consigne(s) épinglée(s) (#5130), dérivée(s) du fil — pas de champ dédié
  /// côté cubit, `messages` reste la source de vérité serveur.
  List<CabinetTeamMessage> get pinnedMessages =>
      messages.where((m) => m.pinned).toList();

  CabinetTeamMessagesLoaded copyWith({
    List<CabinetTeamMessage>? messages,
    List<CabinetPractitioner>? practitioners,
    bool? sending,
    String? sendError,
    bool clearSendError = false,
  }) =>
      CabinetTeamMessagesLoaded(
        messages: messages ?? this.messages,
        practitioners: practitioners ?? this.practitioners,
        sending: sending ?? this.sending,
        sendError: clearSendError ? null : (sendError ?? this.sendError),
      );

  @override
  List<Object?> get props => [messages, practitioners, sending, sendError];
}

class CabinetTeamMessagesCubit extends Cubit<CabinetTeamMessagesState> {
  CabinetTeamMessagesCubit({
    required ListCabinetTeamMessagesUseCase listMessages,
    required SendCabinetTeamMessageUseCase sendMessage,
    required ListCabinetPractitionersUseCase listPractitioners,
  })  : _list = listMessages,
        _send = sendMessage,
        _listPractitioners = listPractitioners,
        super(const CabinetTeamMessagesLoading()) {
    load();
  }

  final ListCabinetTeamMessagesUseCase _list;
  final SendCabinetTeamMessageUseCase _send;
  final ListCabinetPractitionersUseCase _listPractitioners;

  Future<void> load() async {
    emit(const CabinetTeamMessagesLoading());
    final messagesFuture = _list();
    final practitionersFuture = _listPractitioners();
    final result = await messagesFuture;
    final practitioners = (await practitionersFuture).fold(
      (_) => const <CabinetPractitioner>[],
      (p) => p,
    );
    result.fold(
      (failure) => emit(CabinetTeamMessagesError(failure.message)),
      (messages) => emit(CabinetTeamMessagesLoaded(
        messages: messages,
        practitioners: practitioners,
      )),
    );
  }

  Future<void> send(String body) async {
    final current = state;
    if (current is! CabinetTeamMessagesLoaded) return;
    emit(current.copyWith(sending: true, clearSendError: true));
    final result = await _send(body);
    await result.fold(
      (failure) async =>
          emit(current.copyWith(sending: false, sendError: failure.message)),
      (_) => load(),
    );
  }
}
