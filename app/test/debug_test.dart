import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/domain/repositories/message_repository.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_state.dart';

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
    bloc = MessagingBloc(repository);
  });

  tearDown(() => bloc.close());

  testWidgets('test with more pumps', (tester) async {
    final completer = Completer<Either<Failure, List<Message>>>();
    when(() => repository.getMessages('conv-1'))
        .thenAnswer((_) => completer.future);
    when(() => repository.markRead('conv-1'))
        .thenAnswer((_) async => const Right(null));
    
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<MessagingBloc>.value(
          value: bloc,
          child: BlocBuilder<MessagingBloc, MessagingState>(
            builder: (context, state) {
              print('REBUILD: $state');
              if (state is MessagingThreadLoaded) {
                return Column(
                  children: state.messages.map((m) => Text(m.text ?? 'no text')).toList(),
                );
              }
              return const Text('not loaded');
            },
          ),
        ),
      ),
    );

    bloc.add(const MessagingThreadOpened('conv-1'));
    await tester.pump();
    
    completer.complete(Right(_initialMessages));
    for (int i = 0; i < 5; i++) {
      await tester.pump();
      print('pump $i - state: ${bloc.state}');
      print('pump $i - Bonjour: ${find.text("Bonjour !").evaluate().length}');
    }
  });
}
