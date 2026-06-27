import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'messaging_event.dart';
import 'messaging_state.dart';

class MessagingBloc extends Bloc<MessagingEvent, MessagingState>
    with SafeEmitMixin<MessagingState> {
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
        (failure) => safeEmit(MessagingConversationsError(failure.message)),
        (conversations) => safeEmit(MessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      safeEmit(const MessagingConversationsError('Erreur de chargement.'));
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
        (failure) => safeEmit(MessagingThreadError(
          conversationId: event.conversation.id,
          message: failure.message,
        )),
        (messages) => safeEmit(MessagingThreadLoaded(
          conversation: event.conversation,
          messages: messages,
        )),
      );
    } catch (_) {
      safeEmit(MessagingThreadError(
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
        (failure) => safeEmit(current.copyWith(sending: false)),
        (message) => safeEmit(current.copyWith(
          sending: false,
          messages: [...current.messages, message],
        )),
      );
    } catch (_) {
      safeEmit(current.copyWith(sending: false));
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
        (failure) => safeEmit(MessagingConversationsError(failure.message)),
        (conversations) => safeEmit(MessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      safeEmit(const MessagingConversationsError('Erreur de chargement.'));
    }
  }
}
