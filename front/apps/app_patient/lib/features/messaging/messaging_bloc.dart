import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'messaging_event.dart';
import 'messaging_state.dart';

class MessagingBloc extends Bloc<MessagingEvent, MessagingState> {
  final GetConversationsUseCase _getConversations;
  final GetConversationMessagesUseCase _getMessages;
  final SendMessageUseCase _sendMessage;
  final MarkConversationReadUseCase _markRead;

  MessagingBloc({
    required GetConversationsUseCase getConversations,
    required GetConversationMessagesUseCase getMessages,
    required SendMessageUseCase sendMessage,
    required MarkConversationReadUseCase markRead,
  })  : _getConversations = getConversations,
        _getMessages = getMessages,
        _sendMessage = sendMessage,
        _markRead = markRead,
        super(const MessagingInitial()) {
    on<MessagingConversationsLoadRequested>(_onConversationsLoad);
    on<MessagingThreadOpened>(_onThreadOpened);
    on<MessagingSendRequested>(_onSend);
    on<MessagingBackRequested>(_onBack);
  }

  Future<void> _onConversationsLoad(
    MessagingConversationsLoadRequested event,
    Emitter<MessagingState> emit,
  ) async {
    emit(const MessagingConversationsLoading());
    try {
      final result = await _getConversations();
      result.fold(
        (failure) => emit(MessagingConversationsError(failure.message)),
        (conversations) => emit(MessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      emit(const MessagingConversationsError('Erreur de chargement.'));
    }
  }

  Future<void> _onThreadOpened(
    MessagingThreadOpened event,
    Emitter<MessagingState> emit,
  ) async {
    emit(MessagingThreadLoading(event.conversation.id));
    try {
      final result = await _getMessages(event.conversation.id);
      result.fold(
        (failure) => emit(MessagingThreadError(
          conversationId: event.conversation.id,
          message: failure.message,
        )),
        (messages) => emit(MessagingThreadLoaded(
          conversation: event.conversation,
          messages: messages,
        )),
      );
    } catch (_) {
      emit(MessagingThreadError(
          conversationId: event.conversation.id,
          message: 'Erreur de chargement.'));
    }
    // Fire-and-forget: ignore mark-read failure (best effort)
    await _markRead(event.conversation.id);
  }

  Future<void> _onSend(
    MessagingSendRequested event,
    Emitter<MessagingState> emit,
  ) async {
    final current = state;
    if (current is! MessagingThreadLoaded) return;

    emit(current.copyWith(sending: true));
    try {
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
    } catch (_) {
      emit(current.copyWith(sending: false));
    }
  }

  Future<void> _onBack(
    MessagingBackRequested event,
    Emitter<MessagingState> emit,
  ) async {
    emit(const MessagingConversationsLoading());
    try {
      final result = await _getConversations();
      result.fold(
        (failure) => emit(MessagingConversationsError(failure.message)),
        (conversations) => emit(MessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      emit(const MessagingConversationsError('Erreur de chargement.'));
    }
  }
}
