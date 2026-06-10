// Integration flow: messaging end-to-end widget test.
//
// Exercises the real [MessagingBloc] (with a mock repository) to verify:
//   1. Envoi d'un message → apparaît côté patient dans le fil.
//   2. Badge messages (unreadCount) mis à jour après ouverture du fil.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/pages/message_thread_screen.dart';

class MockMessageRepository extends Mock implements MessageRepository {}

final _initialMessages = <Message>[
  Message(
    id: 'msg-1',
    conversationId: 'conv-1',
    sender: MessageSender.cabinet,
    text: 'Bonjour !',
    urgency: MessageUrgency.normal,
    sentAt: DateTime(2026, 6, 6, 9, 0),
  ),
];

final _sentMessage = Message(
  id: 'msg-2',
  conversationId: 'conv-1',
  sender: MessageSender.patient,
  text: 'Merci pour votre réponse.',
  urgency: MessageUrgency.normal,
  sentAt: DateTime(2026, 6, 6, 9, 5),
);

final _conversation = Conversation(
  id: 'conv-1',
  cabinetId: 'cab-1',
  cabinetName: 'Cabinet Dupont',
  unreadCount: 1,
  lastMessage: _initialMessages.first,
);

void main() {
  late MockMessageRepository repository;
  late MessagingBloc bloc;

  setUpAll(() {
    registerFallbackValue(const MessagingMessageSendRequested(
      conversationId: 'conv-1',
      text: '',
    ));
  });

  setUp(() {
    repository = MockMessageRepository();
    when(() => repository.getConversations())
        .thenAnswer((_) async => Right([_conversation]));
    when(() => repository.getMessages('conv-1'))
        .thenAnswer((_) async => Right(_initialMessages));
    when(() => repository.markRead('conv-1'))
        .thenAnswer((_) async => const Right(null));
    when(() => repository.send(
          conversationId: 'conv-1',
          text: 'Merci pour votre réponse.',
          attachmentIds: const [],
        )).thenAnswer((_) async => Right(_sentMessage));
    bloc = MessagingBloc(repository);
  });

  tearDown(() => bloc.close());

  testWidgets(
      'Messaging flow — message envoyé apparaît côté patient dans le fil',
      (tester) async {
    bloc.add(const MessagingThreadOpened('conv-1'));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<MessagingBloc>.value(
          value: bloc,
          child: const MessageThreadScreen(
            conversationId: 'conv-1',
            cabinetName: 'Cabinet Dupont',
          ),
        ),
      ),
    );

    // Wait for the thread to load.
    await tester.pump();
    await tester.pump();

    expect(find.text('Bonjour !'), findsOneWidget);

    // Type and send a message.
    await tester.enterText(find.byType(TextField), 'Merci pour votre réponse.');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pump();
    await tester.pump();

    // The sent message should now appear in the thread.
    expect(find.text('Merci pour votre réponse.'), findsOneWidget);
  });

  testWidgets(
      'Messaging flow — badge unread mis à 0 après ouverture du fil (markRead)',
      (tester) async {
    // Start: conversation has unreadCount = 1.
    // After MessagingThreadOpened, the bloc calls markRead — verify it's called.
    bloc.add(const MessagingThreadOpened('conv-1'));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<MessagingBloc>.value(
          value: bloc,
          child: const MessageThreadScreen(
            conversationId: 'conv-1',
            cabinetName: 'Cabinet Dupont',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    verify(() => repository.markRead('conv-1')).called(1);
  });
}
