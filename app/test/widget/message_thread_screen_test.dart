import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_state.dart';
import 'package:nubia_patient/presentation/features/messaging/pages/message_thread_screen.dart';

class MockMessagingBloc extends MockBloc<MessagingEvent, MessagingState>
    implements MessagingBloc {}

final _messages = [
  Message(
    id: 'msg-1',
    conversationId: 'conv-1',
    sender: MessageSender.cabinet,
    text: 'Bonjour !',
    urgency: MessageUrgency.normal,
    sentAt: DateTime(2026, 6, 6, 9, 0),
  ),
  Message(
    id: 'msg-2',
    conversationId: 'conv-1',
    sender: MessageSender.patient,
    text: 'Bonjour, j\'ai une question.',
    urgency: MessageUrgency.normal,
    sentAt: DateTime(2026, 6, 6, 9, 5),
  ),
];

Widget _wrap(MessagingBloc bloc) {
  return MaterialApp(
    home: BlocProvider<MessagingBloc>.value(
      value: bloc,
      child: const MessageThreadScreen(
        conversationId: 'conv-1',
        cabinetName: 'Cabinet Dupont',
      ),
    ),
  );
}

void main() {
  late MockMessagingBloc bloc;

  setUpAll(() {
    registerFallbackValue(
      const MessagingMessageSendRequested(
        conversationId: 'conv-1',
        text: 'test',
      ),
    );
  });

  setUp(() {
    bloc = MockMessagingBloc();
  });

  tearDown(() => bloc.close());

  testWidgets('MessageThreadScreen — affiche les messages chargés',
      (tester) async {
    when(() => bloc.state).thenReturn(
      MessagingThreadLoaded(
        conversationId: 'conv-1',
        messages: _messages,
      ),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Bonjour !'), findsOneWidget);
    expect(find.text('Bonjour, j\'ai une question.'), findsOneWidget);
  });

  testWidgets('MessageThreadScreen — envoi d\'un message dispatche l\'event',
      (tester) async {
    when(() => bloc.state).thenReturn(
      MessagingThreadLoaded(
        conversationId: 'conv-1',
        messages: _messages,
      ),
    );

    await tester.pumpWidget(_wrap(bloc));

    await tester.enterText(find.byType(TextField), 'Nouveau message');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pump();

    verify(
      () => bloc.add(
        const MessagingMessageSendRequested(
          conversationId: 'conv-1',
          text: 'Nouveau message',
        ),
      ),
    ).called(1);
  });
}
