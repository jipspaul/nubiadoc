import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_messaging_event.dart';
import 'cabinet_messaging_state.dart';

class CabinetMessagingBloc
    extends Bloc<CabinetMessagingEvent, CabinetMessagingState> {
  final ListCabinetConversationsUseCase _listConversations;
  final GetCabinetConversationUseCase _getMessages;
  final SendMessageCabinetUseCase _sendMessage;

  CabinetMessagingBloc({
    required ListCabinetConversationsUseCase listConversations,
    required GetCabinetConversationUseCase getMessages,
    required SendMessageCabinetUseCase sendMessage,
  })  : _listConversations = listConversations,
        _getMessages = getMessages,
        _sendMessage = sendMessage,
        super(const CabinetMessagingInitial()) {
    on<CabinetMessagingConversationsLoadRequested>(_onConversationsLoad);
    on<CabinetMessagingThreadOpened>(_onThreadOpened);
    on<CabinetMessagingSendRequested>(_onSend);
    on<CabinetMessagingBackRequested>(_onBack);
  }

  Future<void> _onConversationsLoad(
    CabinetMessagingConversationsLoadRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    emit(const CabinetMessagingConversationsLoading());
    final result = await _listConversations();
    result.fold(
      (failure) => emit(CabinetMessagingConversationsError(failure.message)),
      (conversations) =>
          emit(CabinetMessagingConversationsLoaded(conversations)),
    );
  }

  Future<void> _onThreadOpened(
    CabinetMessagingThreadOpened event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    emit(CabinetMessagingThreadLoading(event.conversation.id));
    final result = await _getMessages(event.conversation.id);
    result.fold(
      (failure) => emit(CabinetMessagingThreadError(
        conversationId: event.conversation.id,
        message: failure.message,
      )),
      (messages) => emit(CabinetMessagingThreadLoaded(
        conversation: event.conversation,
        messages: messages,
      )),
    );
  }

  Future<void> _onSend(
    CabinetMessagingSendRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    final current = state;
    if (current is! CabinetMessagingThreadLoaded) return;

    emit(current.copyWith(sending: true));
    final result = await _sendMessage(
      conversationId: event.conversationId,
      text: event.text,
    );
    result.fold(
      (failure) => emit(current.copyWith(sending: false)),
      (message) => emit(current.copyWith(
        sending: false,
        messages: [...current.messages, message],
      )),
    );
  }

  Future<void> _onBack(
    CabinetMessagingBackRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    emit(const CabinetMessagingConversationsLoading());
    final result = await _listConversations();
    result.fold(
      (failure) => emit(CabinetMessagingConversationsError(failure.message)),
      (conversations) =>
          emit(CabinetMessagingConversationsLoaded(conversations)),
    );
  }
}
