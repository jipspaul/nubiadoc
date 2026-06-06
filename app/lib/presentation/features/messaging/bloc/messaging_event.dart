import 'package:equatable/equatable.dart';

sealed class MessagingEvent extends Equatable {
  const MessagingEvent();

  @override
  List<Object?> get props => [];
}

final class MessagingConversationsLoadRequested extends MessagingEvent {
  const MessagingConversationsLoadRequested();
}

final class MessagingThreadOpened extends MessagingEvent {
  final String conversationId;

  const MessagingThreadOpened(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

final class MessagingMessageSendRequested extends MessagingEvent {
  final String conversationId;
  final String text;
  final List<String> attachmentIds;

  const MessagingMessageSendRequested({
    required this.conversationId,
    required this.text,
    this.attachmentIds = const [],
  });

  @override
  List<Object?> get props => [conversationId, text, attachmentIds];
}

final class MessagingMarkReadRequested extends MessagingEvent {
  final String conversationId;

  const MessagingMarkReadRequested(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

final class MessagingPhotoAttachRequested extends MessagingEvent {
  final String conversationId;
  final String filePath;
  final String filename;
  final String mimeType;

  const MessagingPhotoAttachRequested({
    required this.conversationId,
    required this.filePath,
    required this.filename,
    required this.mimeType,
  });

  @override
  List<Object?> get props => [conversationId, filePath, filename, mimeType];
}
