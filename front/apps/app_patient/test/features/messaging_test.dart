import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

    // #5286 — le compteur non-lu doit se remettre à 0 localement dès la
    // lecture du fil, sans dépendre uniquement du rechargement serveur.
    blocTest<MessagingBloc, MessagingState>(
      'un retour après lecture du fil remet unreadCount à 0 localement, '
      'même si le serveur renvoie encore un compteur non nul',
      build: () {
        when(() => mockGetMessages(any()))
            .thenAnswer((_) async => Right([_msg]));
        when(() => mockMarkRead(any()))
            .thenAnswer((_) async => const Right(null));
        when(() => mockGetConversations())
            .thenAnswer((_) async => Right([_conv]));
        return _makeBloc(
          getConversations: mockGetConversations,
          getMessages: mockGetMessages,
          sendMessage: mockSendMessage,
          markRead: mockMarkRead,
        );
      },
      act: (bloc) async {
        bloc.add(MessagingThreadOpened(_conv));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const MessagingBackRequested());
      },
      skip: 2,
      expect: () => [
        const MessagingConversationsLoading(),
        isA<MessagingConversationsLoaded>().having(
          (s) => s.conversations.single.unreadCount,
          'unreadCount',
          0,
        ),
      ],
    );

    blocTest<MessagingBloc, MessagingState>(
      'un échec silencieux de markRead ne rallume pas la pastille au retour',
      build: () {
        when(() => mockGetMessages(any()))
            .thenAnswer((_) async => Right([_msg]));
        when(() => mockMarkRead(any())).thenAnswer(
            (_) async => const Left(NetworkFailure('Erreur réseau.')));
        when(() => mockGetConversations())
            .thenAnswer((_) async => Right([_conv]));
        return _makeBloc(
          getConversations: mockGetConversations,
          getMessages: mockGetMessages,
          sendMessage: mockSendMessage,
          markRead: mockMarkRead,
        );
      },
      act: (bloc) async {
        bloc.add(MessagingThreadOpened(_conv));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const MessagingBackRequested());
      },
      skip: 2,
      expect: () => [
        const MessagingConversationsLoading(),
        isA<MessagingConversationsLoaded>().having(
          (s) => s.conversations.single.unreadCount,
          'unreadCount',
          0,
        ),
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

  // #5283 — trois chips de réponse rapide au-dessus du composeur, pour
  // répondre sans ouvrir le clavier.
  group('MessagingPage — réponses rapides (#5283)', () {
    testWidgets('affiche les trois chips avec leurs libellés exacts',
        (tester) async {
      when(() => mockGetMessages(any())).thenAnswer((_) async => Right([_msg]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      expect(find.byKey(const Key('messaging_quick_reply_slot')),
          findsOneWidget);
      expect(find.byKey(const Key('messaging_quick_reply_thanks')),
          findsOneWidget);
      expect(find.byKey(const Key('messaging_quick_reply_callback')),
          findsOneWidget);
      expect(find.text('Proposer un créneau'), findsOneWidget);
      expect(find.text('Merci !'), findsOneWidget);
      expect(find.text('Je rappelle'), findsOneWidget);
    });

    testWidgets('taper une chip envoie directement la réponse',
        (tester) async {
      when(() => mockGetMessages(any())).thenAnswer((_) async => Right([_msg]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));
      final sent = Message(
        id: 'msg-quick',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: 'Merci !',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 12, 0),
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

      await tester.tap(find.byKey(const Key('messaging_quick_reply_thanks')));
      await tester.pumpAndSettle();

      verify(() => mockSendMessage(
            conversationId: 'conv-1',
            text: 'Merci !',
          )).called(1);
      expect(
        find.descendant(
          of: find.byKey(const Key('messaging_thread_messages')),
          matching: find.text('Merci !'),
        ),
        findsOneWidget,
      );
      // Le champ libre reste vide et disponible : la chip ne le remplace pas.
      expect(
        tester
            .widget<NubiaTextField>(find.byKey(const Key('messaging_input')))
            .controller!
            .text,
        isEmpty,
      );
    });
  });

  // #4545 — le thread s'ouvrait sur le tout premier message (historique),
  // sans scroll auto vers le plus récent : `reverse: true` sur la ListView
  // ancre systématiquement la vue sur le dernier message.
  group('MessagingPage — ordre d\'affichage du thread (#4545)', () {
    testWidgets(
        'le dernier message (le plus récent) est rendu en dernier dans '
        'l\'arbre — position visuelle du bas avec reverse:true',
        (tester) async {
      final older = Message(
        id: 'msg-old',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Message le plus ancien',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 1, 9, 0),
      );
      final newer = Message(
        id: 'msg-new',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: 'Message le plus récent',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 11, 0),
      );
      // Ordre ASC renvoyé par le back (created_at ASC) : ancien -> récent.
      when(() => mockGetMessages(any()))
          .thenAnswer((_) async => Right([older, newer]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      final list = tester
          .widget<ListView>(find.byKey(const Key('messaging_thread_messages')));
      expect(list.reverse, isTrue);

      final oldOffset =
          tester.getCenter(find.text('Message le plus ancien')).dy;
      final newOffset =
          tester.getCenter(find.text('Message le plus récent')).dy;
      expect(newOffset, greaterThan(oldOffset));
    });
  });

  group('MessagingPage — séparateurs de jour dans le fil (#5278)', () {
    testWidgets(
        'un séparateur apparaît avant chaque nouvelle journée, dont '
        '"Aujourd\'hui" pour le jour courant, sans casser reverse:true',
        (tester) async {
      // Surface agrandie : 4 bulles + 3 séparateurs dépassent la hauteur de
      // test par défaut une fois la ligne d'horodatage (#5277) ajoutée sous
      // chaque bulle — sans cela, le premier séparateur sort du viewport
      // construit par le `ListView.builder` (reverse:true).
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9, 0);
      final dayOne = Message(
        id: 'msg-day1',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Message du premier jour',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 7, 21, 9, 0),
      );
      final dayTwo = Message(
        id: 'msg-day2',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Message du deuxième jour',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 8, 4, 9, 0),
      );
      final dayTwoLater = Message(
        id: 'msg-day2-bis',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: 'Deuxième message du même jour',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 8, 4, 15, 0),
      );
      final todayMsg = Message(
        id: 'msg-today',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: "Message d'aujourd'hui",
        urgency: MessageUrgency.normal,
        sentAt: today,
      );
      when(() => mockGetMessages(any())).thenAnswer(
        (_) async => Right([dayOne, dayTwo, dayTwoLater, todayMsg]),
      );
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      expect(find.text('Mardi 21 juillet'), findsOneWidget);
      expect(find.text('Mardi 4 août'), findsOneWidget);
      expect(find.text("Aujourd'hui"), findsOneWidget);

      final list = tester
          .widget<ListView>(find.byKey(const Key('messaging_thread_messages')));
      expect(list.reverse, isTrue);

      final firstDaySeparatorOffset =
          tester.getCenter(find.text('Mardi 21 juillet')).dy;
      final todaySeparatorOffset =
          tester.getCenter(find.text("Aujourd'hui")).dy;
      expect(todaySeparatorOffset, greaterThan(firstDaySeparatorOffset));
    });
  });

  // #5279 — le fil s'ouvre désormais via une vraie route `/messaging/:id`
  // (au lieu d'un changement d'état du même bloc), pour que le retour
  // matériel Android ferme la conversation sans laisser l'onglet Messages
  // dans un état de fil ouvert.
  group('MessagingPage — vraie route pour le fil (#5279)', () {
    testWidgets(
        "taper une conversation navigue vers /messaging/:id ; le bouton "
        "retour dépile la route et l'onglet garde sa liste déjà chargée",
        (tester) async {
      when(() => mockGetConversations())
          .thenAnswer((_) async => Right([_conv]));
      when(() => mockGetMessages(any())).thenAnswer((_) async => Right([_msg]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

      final listBloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      )..add(const MessagingConversationsLoadRequested());

      String? threadPathId;
      final router = GoRouter(
        initialLocation: '/messaging',
        routes: [
          GoRoute(
            path: '/messaging',
            builder: (_, __) => BlocProvider.value(
              value: listBloc,
              child: const Scaffold(body: MessagingPage()),
            ),
          ),
          GoRoute(
            path: '/messaging/:id',
            builder: (_, state) {
              threadPathId = state.pathParameters['id'];
              return BlocProvider(
                create: (_) => _makeBloc(
                  getConversations: mockGetConversations,
                  getMessages: mockGetMessages,
                  sendMessage: mockSendMessage,
                  markRead: mockMarkRead,
                )..add(MessagingThreadOpened(state.extra as Conversation)),
                child: const Scaffold(body: MessagingPage()),
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('messaging_conversations_list')), findsOneWidget);

      await tester.tap(find.byKey(const Key('conv_conv-1')));
      await tester.pumpAndSettle();

      // Vraie navigation par route (paramètre `:id` reçu par la route), pas
      // un changement d'état dans le bloc de la liste.
      expect(threadPathId, 'conv-1');
      expect(find.byKey(const Key('messaging_thread_messages')), findsOneWidget);
      expect(
          find.byKey(const Key('messaging_conversations_list')), findsNothing);
      expect(listBloc.state, isA<MessagingConversationsLoaded>());

      await tester.tap(find.byKey(const Key('messaging_back_button')));
      await tester.pumpAndSettle();

      // Le pop de route révèle l'onglet Messages resté sur sa liste : pas de
      // fil resté ouvert au retour.
      expect(
          find.byKey(const Key('messaging_conversations_list')), findsOneWidget);
      expect(find.byKey(const Key('messaging_thread_messages')), findsNothing);
      expect(listBloc.state, isA<MessagingConversationsLoaded>());
    });
  });

  // #5282 — pièce jointe cliquable liée au coffre documentaire : une carte
  // (icône + titre + sous-ligne + chevron) sous le texte du message, qui
  // navigue vers la feature `documents` au tap.
  group('MessagingPage — pièce jointe cliquable (#5282)', () {
    testWidgets(
        'un message avec pièce jointe affiche la carte et le tap ouvre le '
        'coffre documentaire', (tester) async {
      final withAttachment = Message(
        id: 'msg-attach',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Voici le devis pour vos soins.',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 8, 4, 9, 0),
        attachments: const [
          MessageAttachment(
            documentId: 'doc-devis-1',
            title: 'Devis DEV-2041',
            subtitle: '435,92 € · reste à charge 148,50 €',
            category: DocumentCategory.quote,
          ),
        ],
      );
      when(() => mockGetMessages(any()))
          .thenAnswer((_) async => Right([withAttachment]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

      final bloc = _makeBloc(
        getConversations: mockGetConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
        markRead: mockMarkRead,
      )..add(MessagingThreadOpened(_conv));

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/messaging',
        routes: [
          GoRoute(
            path: '/messaging',
            builder: (_, __) => BlocProvider.value(
              value: bloc,
              child: const Scaffold(body: MessagingPage()),
            ),
          ),
          GoRoute(
            path: '/documents',
            builder: (_, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('documents'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.text('Devis DEV-2041'), findsOneWidget);
      expect(
        find.text('435,92 € · reste à charge 148,50 €'),
        findsOneWidget,
      );

      final card = find.byKey(const Key('messaging_attachment_doc-devis-1'));
      expect(card, findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(pushedLocation, '/documents?id=doc-devis-1');
    });

    testWidgets('un message sans pièce jointe n\'affiche aucune carte',
        (tester) async {
      when(() => mockGetMessages(any())).thenAnswer((_) async => Right([_msg]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });

  // #5277 — chaque bulle du fil affiche l'heure d'envoi sous le texte ; un
  // accusé de lecture (`done_all`) accompagne l'heure sur une bulle patient
  // lue, jamais sur une bulle reçue.
  group('MessagingPage — horodatage des bulles (#5277)', () {
    testWidgets('affiche l\'heure locale (HH:MM) sous chaque bulle',
        (tester) async {
      final received = Message(
        id: 'msg-received',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Bonjour, comment puis-je vous aider ?',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 9, 20),
      );
      final sentUnread = Message(
        id: 'msg-sent-unread',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: 'Une question sur mon traitement',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 11, 24),
      );
      final sentRead = Message(
        id: 'msg-sent-read',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: 'Merci docteur',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 18, 40),
        readAt: DateTime(2026, 6, 18, 18, 41),
      );
      when(() => mockGetMessages(any())).thenAnswer(
        (_) async => Right([received, sentUnread, sentRead]),
      );
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      expect(find.text('09:20'), findsOneWidget);
      expect(find.text('11:24'), findsOneWidget);
      expect(find.text('18:40'), findsOneWidget);

      // Bulle patient lue : accusé de lecture accolé à l'heure.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('18:40'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.done_all),
        ),
        findsOneWidget,
      );

      // Bulle patient non lue et bulle reçue : pas d'accusé de lecture.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('11:24'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.done_all),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('09:20'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.done_all),
        ),
        findsNothing,
      );
    });
  });

  // #5276 — l'urgence ne doit pas exister uniquement dans la liste
  // (`last?.urgency`) : ouvrir le fil ne doit pas faire disparaître le
  // signal, et un message urgent ancien dans l'historique doit rester signalé.
  group('MessagingPage — urgence portée par la bulle (#5276)', () {
    testWidgets(
        'une bulle urgente affiche le bandeau URGENT, une bulle normale non',
        (tester) async {
      final urgent = Message(
        id: 'msg-urgent',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Votre couronne est arrivée du laboratoire.',
        urgency: MessageUrgency.urgent,
        sentAt: DateTime(2026, 6, 18, 9, 0),
      );
      final normal = Message(
        id: 'msg-normal',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Merci pour votre visite.',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 9, 5),
      );
      when(() => mockGetMessages(any()))
          .thenAnswer((_) async => Right([urgent, normal]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      expect(find.text('URGENT'), findsOneWidget);

      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Merci pour votre visite.'),
            matching: find.byType(Container),
          ).first,
          matching: find.text('URGENT'),
        ),
        findsNothing,
      );
    });

    testWidgets(
        'un message urgent plus ancien reste signalé même si le dernier '
        "message du fil n'est pas urgent", (tester) async {
      final older = Message(
        id: 'msg-old-urgent',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Message urgent ancien',
        urgency: MessageUrgency.urgent,
        sentAt: DateTime(2026, 6, 18, 9, 0),
      );
      final newer = Message(
        id: 'msg-new-normal',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Message récent normal',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 10, 0),
      );
      when(() => mockGetMessages(any()))
          .thenAnswer((_) async => Right([older, newer]));
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      expect(find.text('Message urgent ancien'), findsOneWidget);
      expect(find.text('URGENT'), findsOneWidget);
    });
  });

  // #5275 — nom + rôle de l'émetteur en tête de bulle reçue, pour que le
  // patient sache s'il lit un avis clinique ou une relance administrative.
  group('MessagingPage — auteur en tête de bulle (#5275)', () {
    testWidgets(
        'une bulle reçue affiche le nom de l\'auteur, la bulle patient n\'en '
        'affiche aucun', (tester) async {
      final fromDoctor = Message(
        id: 'msg-doctor',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Gardez la zone au frais 48h.',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 9, 0),
        authorName: 'Dr Amélie Rousseau',
        authorRole: 'Praticien',
      );
      final fromSecretary = Message(
        id: 'msg-secretary',
        conversationId: 'conv-1',
        sender: MessageSender.cabinet,
        text: 'Votre devis DEV-2041 vous a été envoyé.',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 9, 5),
        authorRole: 'Secrétariat',
      );
      final fromPatient = Message(
        id: 'msg-patient',
        conversationId: 'conv-1',
        sender: MessageSender.patient,
        text: 'Merci docteur',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 6, 18, 9, 10),
      );
      when(() => mockGetMessages(any())).thenAnswer(
        (_) async => Right([fromDoctor, fromSecretary, fromPatient]),
      );
      when(() => mockMarkRead(any()))
          .thenAnswer((_) async => const Right(null));

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

      // Bulles reçues : nom si présent, sinon rôle.
      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.text('Secrétariat'), findsOneWidget);

      // La bulle patient ne porte aucune ligne d'auteur.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Merci docteur'),
            matching: find.byType(Column),
          ).first,
          matching: find.text('Dr Amélie Rousseau'),
        ),
        findsNothing,
      );
    });
  });
}
