import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PharmaMessagingEvent extends Equatable {
  const PharmaMessagingEvent();

  @override
  List<Object?> get props => [];
}

final class PharmaMessagingConversationsLoadRequested
    extends PharmaMessagingEvent {
  const PharmaMessagingConversationsLoadRequested();
}

final class PharmaMessagingThreadOpened extends PharmaMessagingEvent {
  final CabinetConversation conversation;

  const PharmaMessagingThreadOpened(this.conversation);

  @override
  List<Object?> get props => [conversation];
}

final class PharmaMessagingSendRequested extends PharmaMessagingEvent {
  final String conversationId;
  final String text;

  const PharmaMessagingSendRequested({
    required this.conversationId,
    required this.text,
  });

  @override
  List<Object?> get props => [conversationId, text];
}

final class PharmaMessagingBackRequested extends PharmaMessagingEvent {
  const PharmaMessagingBackRequested();
}
