import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/messaging/messaging_bloc.dart';
import 'package:app_patient/features/messaging/messaging_event.dart';
import 'package:app_patient/features/messaging/messaging_page.dart';
import 'package:app_patient/features/messaging/messaging_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetConversationsUseCase extends Mock
    implements GetConversationsUseCase {}

class MockGetConversationMessagesUseCase extends Mock
    implements GetConversationMessagesUseCase {}

class MockSendMessageUseCase extends Mock implements SendMessageUseCase {}

class MockMarkConversationReadUseCase extends Mock
    implements MarkConversationReadUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _conv = Conversation(
  id: 'conv-1',
  cabinetId: 'cab-1',
  cabinetName: 'Cabinet Lyon',
  unreadCount: 2,
);

final _msg = Message(
  id: 'msg-1',
  conversationId: 'conv-1',
  sender: MessageSender.cabinet,
  text: 'Bonjour, comment puis-je vous aider ?',
  urgency: MessageUrgency.normal,
  sentAt: DateTime(2026, 6, 18, 10, 0),
);

MessagingBloc _makeBloc({
  required MockGetConversationsUseCase getConversations,
  required MockGetConversationMessagesUseCase getMessages,
  required MockSendMessageUseCase sendMessage,
  required MockMarkConversationReadUseCase markRead,
}) =>
    MessagingBloc(
      getConversations: getConversations,
      getMessages: getMessages,
      sendMessage: sendMessage,
      markRead: markRead,
    );

/// Widget de test — utilise BlocBuilder directement (sans GetIt).
class _MessagingBodyDirect extends StatelessWidget {
  const _MessagingBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MessagingBloc, MessagingState>(
      builder: (context, state) {
        if (state is MessagingInitial ||
            state is MessagingConversationsLoading) {
          return const Center(
            key: Key('messaging_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is MessagingConversationsError) {
          return Center(
            key: const Key('messaging_error'),
            child: Text(state.message),
          );
        }
        if (state is MessagingConversationsLoaded) {
          if (state.conversations.isEmpty) {
            return const Center(
              key: Key('messaging_empty'),
              child: Text('Aucun message'),
            );
          }
          return ListView(
            key: const Key('messaging_conversations_list'),
            children: [
              for (final c in state.conversations)
                Text(key: Key('conv_${c.id}'), c.cabinetName),
            ],
          );
        }
        if (state is MessagingThreadLoaded) {
          return Center(
            key: const Key('messaging_thread_loaded'),
            child: Text(state.conversation.cabinetName),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

Widget _wrap(MessagingBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _MessagingBodyDirect()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetConversationsUseCase mockGetConversations;
  late MockGetConversationMessagesUseCase mockGetMessages;
  late MockSendMessageUseCase mockSendMessage;
  late MockMarkConversationReadUseCase mockMarkRead;

  setUpAll(() {
    registerFallbackValue(_conv);
  });

  setUp(() {
    mockGetConversations = MockGetConversationsUseCase();
    mockGetMessages = MockGetConversationMessagesUseCase();
    mockSendMessage = MockSendMessageUseCase();
    mockMarkRead = MockMarkConversationReadUseCase();
  });

  group('MessagingPage widget', () {
    testWidgets('affiche le spinner en état Initial', (tester) async {
      final bloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('messaging_loading')), findsOneWidget);
    });

    testWidgets('affiche "Aucun message" quand la liste est vide',
        (tester) async {
      when(() => mockGetConversations())
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      );
      bloc.add(const MessagingConversationsLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('messaging_empty')), findsOneWidget);
    });

    testWidgets(
        'affiche le nom du cabinet quand les conversations sont chargées',
        (tester) async {
      when(() => mockGetConversations())
          .thenAnswer((_) async => Right([_conv]));

      final bloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      );
      bloc.add(const MessagingConversationsLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('conv_conv-1')), findsOneWidget);
      expect(find.text('Cabinet Lyon'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur en état erreur', (tester) async {
      when(() => mockGetConversations()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')));

      final bloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      );
      bloc.add(const MessagingConversationsLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('messaging_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
    });
  });

  group('MessagingPage — aperçu conversation (#3348)', () {
    testWidgets('affiche horodatage (HH:mm) + sous-titre non-lu via ListRow',
        (tester) async {
      final now = DateTime.now();
      final conv = Conversation(
        id: 'conv-9',
        cabinetId: 'cab-9',
        cabinetName: 'Cabinet Lyon',
        unreadCount: 2,
        lastMessageAt: DateTime(now.year, now.month, now.day, 14, 5),
      );
      when(() => mockGetConversations()).thenAnswer((_) async => Right([conv]));

      final bloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      )..add(const MessagingConversationsLoadRequested());

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider.value(
            value: bloc,
            child: const Scaffold(body: MessagingPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cabinet Lyon'), findsOneWidget);
      expect(find.text('14:05'), findsOneWidget);
      expect(find.text('2 nouveaux messages'), findsOneWidget);
    });
  });

  group('MessagingBloc', () {
    blocTest<MessagingBloc, MessagingState>(
      'émet [Loading, Loaded(vide)] quand la liste de conversations est vide',
      build: () {
        when(() => mockGetConversations())
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          getConversations: mockGetConversations,
          getMessages: mockGetMessages,
          sendMessage: mockSendMessage,
          markRead: mockMarkRead,
        );
      },
      act: (bloc) => bloc.add(const MessagingConversationsLoadRequested()),
      expect: () => [
        const MessagingConversationsLoading(),
        isA<MessagingConversationsLoaded>()
            .having((s) => s.conversations, 'conversations', isEmpty),
      ],
    );

    blocTest<MessagingBloc, MessagingState>(
      'émet [Loading, Error] quand getConversations échoue',
      build: () {
        when(() => mockGetConversations()).thenAnswer(
            (_) async => const Left(NetworkFailure('Erreur réseau.')));
        return _makeBloc(
          getConversations: mockGetConversations,
          getMessages: mockGetMessages,
          sendMessage: mockSendMessage,
          markRead: mockMarkRead,
        );
      },
      act: (bloc) => bloc.add(const MessagingConversationsLoadRequested()),
      expect: () => [
        const MessagingConversationsLoading(),
        isA<MessagingConversationsError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );

    blocTest<MessagingBloc, MessagingState>(
      'émet [ThreadLoading, ThreadLoaded] quand un thread est ouvert',
      build: () {
        when(() => mockGetMessages(any()))
            .thenAnswer((_) async => Right([_msg]));
        when(() => mockMarkRead(any()))
            .thenAnswer((_) async => const Right(null));
        return _makeBloc(
          getConversations: mockGetConversations,
          getMessages: mockGetMessages,
          sendMessage: mockSendMessage,
          markRead: mockMarkRead,
        );
      },
      act: (bloc) => bloc.add(MessagingThreadOpened(_conv)),
      expect: () => [
        isA<MessagingThreadLoading>()
            .having((s) => s.conversationId, 'id', 'conv-1'),
        isA<MessagingThreadLoaded>()
            .having((s) => s.messages, 'messages', [_msg]).having(
                (s) => s.conversation.cabinetName, 'cabinet', 'Cabinet Lyon'),
      ],
    );
  });

  // #3416 — après un envoi réussi, la bulle du message envoyé doit apparaître
  // immédiatement dans le fil ouvert (sans quitter/rouvrir la conversation).
  group('MessagingPage — envoi (#3416)', () {
    testWidgets('la bulle du message envoyé apparaît tout de suite',
        (tester) async {
      when(() => mockGetMessages(any())).thenAnswer((_) async => Right([_msg]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));
      final sent = Message(
        id: 'msg-2',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: 'Bonjour docteur, une question',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 11, 0),
      );
      when(() => mockSendMessage(
            conversationId: any(named: 'conversationId'),
            text: any(named: 'text'),
          )).thenAnswer((_) async => Right(sent));

      final bloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      )..add(MessagingThreadOpened(_conv));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider.value(
            value: bloc,
            child: const Scaffold(body: MessagingPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Le message n'existe pas encore avant l'envoi.
      expect(find.text('Bonjour docteur, une question'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('messaging_input')),
        'Bonjour docteur, une question',
      );
      await tester.tap(find.byKey(const Key('messaging_send_button')));
      await tester.pumpAndSettle();

      // La bulle est affichée immédiatement, sans recharger la conversation.
      expect(find.text('Bonjour docteur, une question'), findsOneWidget);
    });
  });
}
