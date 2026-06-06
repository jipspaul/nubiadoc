import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_state.dart';

@injectable
class MessagingBloc extends Bloc<MessagingEvent, MessagingState> {
  final MessageRepository _repository;

  MessagingBloc(this._repository) : super(const MessagingInitial()) {
    on<MessagingConversationsLoadRequested>(_onConversationsLoadRequested);
    on<MessagingThreadOpened>(_onThreadOpened);
    on<MessagingMessageSendRequested>(_onMessageSendRequested);
    on<MessagingMarkReadRequested>(_onMarkReadRequested);
  }

  Future<void> _onConversationsLoadRequested(
    MessagingConversationsLoadRequested event,
    Emitter<MessagingState> emit,
  ) async {
    emit(const MessagingConversationsLoading());
    final result = await _repository.getConversations();
    result.fold(
      (failure) => emit(MessagingConversationsError(failure.message)),
      (conversations) => emit(MessagingConversationsLoaded(conversations)),
    );
  }

  Future<void> _onThreadOpened(
    MessagingThreadOpened event,
    Emitter<MessagingState> emit,
  ) async {
    emit(MessagingThreadLoading(event.conversationId));
    final result = await _repository.getMessages(event.conversationId);
    result.fold(
      (failure) => emit(MessagingThreadError(
        conversationId: event.conversationId,
        message: failure.message,
      )),
      (messages) => emit(MessagingThreadLoaded(
        conversationId: event.conversationId,
        messages: messages,
      )),
    );
    // Fire-and-forget mark-read; ignore failure (best effort)
    await _repository.markRead(event.conversationId);
  }

  Future<void> _onMessageSendRequested(
    MessagingMessageSendRequested event,
    Emitter<MessagingState> emit,
  ) async {
    final current = state;
    if (current is! MessagingThreadLoaded) return;

    emit(current.copyWith(sending: true));
    final result = await _repository.send(
      conversationId: event.conversationId,
      text: event.text,
      attachmentIds: event.attachmentIds,
    );
    result.fold(
      (failure) => emit(current.copyWith(sending: false)),
      (message) => emit(current.copyWith(
        sending: false,
        messages: [...current.messages, message],
      )),
    );
  }

  Future<void> _onMarkReadRequested(
    MessagingMarkReadRequested event,
    Emitter<MessagingState> emit,
  ) async {
    await _repository.markRead(event.conversationId);
  }
}
