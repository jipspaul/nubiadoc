import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_state.dart';

class MockMessageRepository extends Mock implements MessageRepository {}

final _conversations = [
  const Conversation(
    id: 'conv-1',
    cabinetId: 'cab-1',
    cabinetName: 'Cabinet Dupont',
    unreadCount: 1,
  ),
];

final _messages = [
  Message(
    id: 'msg-1',
    conversationId: 'conv-1',
    sender: MessageSender.cabinet,
    text: 'Bonjour !',
    urgency: MessageUrgency.normal,
    sentAt: DateTime(2026, 6, 6, 9, 0),
  ),
];

void main() {
  late MockMessageRepository repository;

  setUpAll(() {
    registerFallbackValue(const OfflineFailure());
  });

  setUp(() {
    repository = MockMessageRepository();
  });

  group('MessagingBloc — conversations', () {
    blocTest<MessagingBloc, MessagingState>(
      'émet Loading puis Loaded quand le repo retourne des conversations',
      build: () {
        when(() => repository.getConversations())
            .thenAnswer((_) async => Right(_conversations));
        return MessagingBloc(repository);
      },
      act: (bloc) =>
          bloc.add(const MessagingConversationsLoadRequested()),
      expect: () => [
        const MessagingConversationsLoading(),
        MessagingConversationsLoaded(_conversations),
      ],
    );

    blocTest<MessagingBloc, MessagingState>(
      'émet Loading puis Error quand le repo retourne une failure',
      build: () {
        when(() => repository.getConversations())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return MessagingBloc(repository);
      },
      act: (bloc) =>
          bloc.add(const MessagingConversationsLoadRequested()),
      expect: () => [
        const MessagingConversationsLoading(),
        const MessagingConversationsError(
            'Erreur réseau. Vérifiez votre connexion.'),
      ],
    );
  });

  group('MessagingBloc — thread', () {
    blocTest<MessagingBloc, MessagingState>(
      'émet ThreadLoading puis ThreadLoaded et appelle markRead',
      build: () {
        when(() => repository.getMessages('conv-1'))
            .thenAnswer((_) async => Right(_messages));
        when(() => repository.markRead('conv-1'))
            .thenAnswer((_) async => const Right(null));
        return MessagingBloc(repository);
      },
      act: (bloc) => bloc.add(const MessagingThreadOpened('conv-1')),
      expect: () => [
        const MessagingThreadLoading('conv-1'),
        MessagingThreadLoaded(
          conversationId: 'conv-1',
          messages: _messages,
        ),
      ],
      verify: (_) {
        verify(() => repository.markRead('conv-1')).called(1);
      },
    );
  });

  group('MessagingBloc — send', () {
    final sentMessage = Message(
      id: 'msg-2',
      conversationId: 'conv-1',
      sender: MessageSender.patient,
      text: 'Bonjour !',
      urgency: MessageUrgency.normal,
      sentAt: DateTime(2026, 6, 6, 9, 1),
    );

    blocTest<MessagingBloc, MessagingState>(
      'ajoute le message à la liste après envoi réussi',
      build: () {
        when(() => repository.send(
              conversationId: 'conv-1',
              text: 'Bonjour !',
              attachmentIds: [],
            )).thenAnswer((_) async => Right(sentMessage));
        return MessagingBloc(repository);
      },
      seed: () => MessagingThreadLoaded(
        conversationId: 'conv-1',
        messages: _messages,
      ),
      act: (bloc) => bloc.add(
        const MessagingMessageSendRequested(
          conversationId: 'conv-1',
          text: 'Bonjour !',
        ),
      ),
      expect: () => [
        MessagingThreadLoaded(
          conversationId: 'conv-1',
          messages: _messages,
          sending: true,
        ),
        MessagingThreadLoaded(
          conversationId: 'conv-1',
          messages: [..._messages, sentMessage],
        ),
      ],
    );
  });
}
