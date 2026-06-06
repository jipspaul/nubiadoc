import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/message.dart';

sealed class MessagingState extends Equatable {
  const MessagingState();

  @override
  List<Object?> get props => [];
}

final class MessagingInitial extends MessagingState {
  const MessagingInitial();
}

final class MessagingConversationsLoading extends MessagingState {
  const MessagingConversationsLoading();
}

final class MessagingConversationsLoaded extends MessagingState {
  final List<Conversation> conversations;

  const MessagingConversationsLoaded(this.conversations);

  @override
  List<Object?> get props => [conversations];
}

final class MessagingConversationsError extends MessagingState {
  final String message;

  const MessagingConversationsError(this.message);

  @override
  List<Object?> get props => [message];
}

final class MessagingThreadLoading extends MessagingState {
  final String conversationId;

  const MessagingThreadLoading(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

final class MessagingThreadLoaded extends MessagingState {
  final String conversationId;
  final List<Message> messages;
  final bool sending;
  final bool uploadingAttachment;
  final List<String> pendingAttachmentIds;

  const MessagingThreadLoaded({
    required this.conversationId,
    required this.messages,
    this.sending = false,
    this.uploadingAttachment = false,
    this.pendingAttachmentIds = const [],
  });

  MessagingThreadLoaded copyWith({
    List<Message>? messages,
    bool? sending,
    bool? uploadingAttachment,
    List<String>? pendingAttachmentIds,
  }) {
    return MessagingThreadLoaded(
      conversationId: conversationId,
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
      uploadingAttachment: uploadingAttachment ?? this.uploadingAttachment,
      pendingAttachmentIds: pendingAttachmentIds ?? this.pendingAttachmentIds,
    );
  }

  @override
  List<Object?> get props =>
      [conversationId, messages, sending, uploadingAttachment, pendingAttachmentIds];
}

final class MessagingThreadError extends MessagingState {
  final String conversationId;
  final String message;

  const MessagingThreadError({
    required this.conversationId,
    required this.message,
  });

  @override
  List<Object?> get props => [conversationId, message];
}
