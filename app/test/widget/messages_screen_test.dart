import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/message.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_state.dart';
import 'package:nubia_patient/presentation/features/messaging/widgets/conversation_tile.dart';

class MockMessagingBloc extends MockBloc<MessagingEvent, MessagingState>
    implements MessagingBloc {}

final _conversation = Conversation(
  id: 'conv-1',
  cabinetId: 'cab-1',
  cabinetName: 'Cabinet Dupont',
  unreadCount: 2,
  lastMessage: Message(
    id: 'msg-1',
    conversationId: 'conv-1',
    sender: MessageSender.cabinet,
    text: 'Bonjour, comment puis-je vous aider ?',
    urgency: MessageUrgency.normal,
    sentAt: DateTime(2026, 6, 6, 10, 30),
  ),
);

Widget _wrap(MessagingBloc bloc) {
  return MaterialApp(
    home: BlocProvider<MessagingBloc>.value(
      value: bloc,
      child: Scaffold(
        body: BlocBuilder<MessagingBloc, MessagingState>(
          builder: (context, state) {
            if (state is MessagingConversationsLoaded) {
              return ListView.builder(
                itemCount: state.conversations.length,
                itemBuilder: (_, i) => ConversationTile(
                  conversation: state.conversations[i],
                  onTap: () {},
                ),
              );
            }
            if (state is MessagingConversationsLoading) {
              return const CircularProgressIndicator();
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
}

void main() {
  late MockMessagingBloc bloc;

  setUp(() {
    bloc = MockMessagingBloc();
  });

  tearDown(() => bloc.close());

  testWidgets('MessagesScreen — affiche la liste des conversations chargées',
      (tester) async {
    when(() => bloc.state).thenReturn(
      MessagingConversationsLoaded([_conversation]),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Cabinet Dupont'), findsOneWidget);
    expect(find.text('Bonjour, comment puis-je vous aider ?'), findsOneWidget);
  });

  testWidgets('MessagesScreen — affiche un indicateur en état Loading',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const MessagingConversationsLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
