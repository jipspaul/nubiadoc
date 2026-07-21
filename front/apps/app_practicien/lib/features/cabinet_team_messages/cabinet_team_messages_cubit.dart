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
    this.sending = false,
    this.sendError,
  });

  final List<CabinetTeamMessage> messages;
  final bool sending;
  final String? sendError;

  CabinetTeamMessagesLoaded copyWith({
    List<CabinetTeamMessage>? messages,
    bool? sending,
    String? sendError,
    bool clearSendError = false,
  }) =>
      CabinetTeamMessagesLoaded(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        sendError: clearSendError ? null : (sendError ?? this.sendError),
      );

  @override
  List<Object?> get props => [messages, sending, sendError];
}

class CabinetTeamMessagesCubit extends Cubit<CabinetTeamMessagesState> {
  CabinetTeamMessagesCubit({
    required ListCabinetTeamMessagesUseCase listMessages,
    required SendCabinetTeamMessageUseCase sendMessage,
  })  : _list = listMessages,
        _send = sendMessage,
        super(const CabinetTeamMessagesLoading()) {
    load();
  }

  final ListCabinetTeamMessagesUseCase _list;
  final SendCabinetTeamMessageUseCase _send;

  Future<void> load() async {
    emit(const CabinetTeamMessagesLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(CabinetTeamMessagesError(failure.message)),
      (messages) => emit(CabinetTeamMessagesLoaded(messages: messages)),
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
