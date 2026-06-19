import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetMessagingEvent extends Equatable {
  const CabinetMessagingEvent();

  @override
  List<Object?> get props => [];
}

final class CabinetMessagingConversationsLoadRequested
    extends CabinetMessagingEvent {
  const CabinetMessagingConversationsLoadRequested();
}

final class CabinetMessagingThreadOpened extends CabinetMessagingEvent {
  final CabinetConversation conversation;

  const CabinetMessagingThreadOpened(this.conversation);

  @override
  List<Object?> get props => [conversation];
}

final class CabinetMessagingSendRequested extends CabinetMessagingEvent {
  final String conversationId;
  final String text;

  const CabinetMessagingSendRequested({
    required this.conversationId,
    required this.text,
  });

  @override
  List<Object?> get props => [conversationId, text];
}

final class CabinetMessagingBackRequested extends CabinetMessagingEvent {
  const CabinetMessagingBackRequested();
}
