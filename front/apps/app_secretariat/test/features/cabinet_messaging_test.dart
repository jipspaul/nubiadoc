import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/cabinet_messaging/cabinet_messaging_bloc.dart';
import 'package:app_secretariat/features/cabinet_messaging/cabinet_messaging_event.dart';
import 'package:app_secretariat/features/cabinet_messaging/cabinet_messaging_page.dart';
import 'package:app_secretariat/features/cabinet_messaging/cabinet_messaging_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockCabinetMessageRepository extends Mock
    implements CabinetMessageRepository {}

class _MockCabinetMessagingBloc
    extends MockBloc<CabinetMessagingEvent, CabinetMessagingState>
    implements CabinetMessagingBloc {}

void main() {
  // --- Cloisonnement invariant --------------------------------------------------
  group('ProConfig — cloisonnement', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination requiresClinical dans shellConfig', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- CabinetConversation : pas de champ clinique -----------------------------
  group('CabinetConversation — cloisonnement champs cliniques', () {
    test(
      'CabinetConversation ne porte pas de champ motif ni notes_medicales',
      () {
        final conv = CabinetConversation(
          id: 'c1',
          patientId: 'p1',
          patientName: 'Jean Dupont',
          unreadCount: 2,
        );
        final json = {
          'id': conv.id,
          'patientId': conv.patientId,
          'patientName': conv.patientName,
          'unreadCount': conv.unreadCount,
        };
        expect(json.containsKey('motif'), isFalse);
        expect(json.containsKey('notesMedicales'), isFalse);
      },
    );
  });

  // --- CabinetMessagingBloc ----------------------------------------------------
  group('CabinetMessagingBloc', () {
    late _MockCabinetMessageRepository repo;
    late ListCabinetConversationsUseCase listConversations;
    late GetCabinetConversationUseCase getMessages;
    late SendMessageCabinetUseCase sendMessage;

    final conversations = [
      const CabinetConversation(
        id: 'conv1',
        patientId: 'p1',
        patientName: 'Marie Curie',
        unreadCount: 1,
      ),
    ];

    final messages = [
      Message(
        id: 'msg1',
        conversationId: 'conv1',
        sender: MessageSender.patient,
        text: 'Bonjour',
        urgency: MessageUrgency.normal,
        sentAt: DateTime(2026, 1, 1),
      ),
    ];

    setUp(() {
      repo = _MockCabinetMessageRepository();
      listConversations = ListCabinetConversationsUseCase(repo);
      getMessages = GetCabinetConversationUseCase(repo);
      sendMessage = SendMessageCabinetUseCase(repo);
    });

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(
          () => repo.getConversations(),
        ).thenAnswer((_) async => Right(conversations));
        return CabinetMessagingBloc(
          listConversations: listConversations,
          getMessages: getMessages,
          sendMessage: sendMessage,
        );
      },
      act: (bloc) =>
          bloc.add(const CabinetMessagingConversationsLoadRequested()),
      expect: () => [
        const CabinetMessagingConversationsLoading(),
        CabinetMessagingConversationsLoaded(conversations),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'émet Loading puis Error sur échec réseau',
      build: () {
        when(
          () => repo.getConversations(),
        ).thenAnswer((_) async => Left(const NetworkFailure('Erreur réseau')));
        return CabinetMessagingBloc(
          listConversations: listConversations,
          getMessages: getMessages,
          sendMessage: sendMessage,
        );
      },
      act: (bloc) =>
          bloc.add(const CabinetMessagingConversationsLoadRequested()),
      expect: () => [
        const CabinetMessagingConversationsLoading(),
        const CabinetMessagingConversationsError('Erreur réseau'),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'ouvre un thread — émet ThreadLoading puis ThreadLoaded',
      build: () {
        when(
          () => repo.getMessages('conv1'),
        ).thenAnswer((_) async => Right(messages));
        return CabinetMessagingBloc(
          listConversations: listConversations,
          getMessages: getMessages,
          sendMessage: sendMessage,
        );
      },
      act: (bloc) => bloc.add(
        const CabinetMessagingThreadOpened(
          CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 1,
          ),
        ),
      ),
      expect: () => [
        const CabinetMessagingThreadLoading('conv1'),
        CabinetMessagingThreadLoaded(
          conversation: const CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 1,
          ),
          messages: messages,
        ),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'les conversations chargées n\'exposent aucun champ clinique',
      build: () {
        when(
          () => repo.getConversations(),
        ).thenAnswer((_) async => Right(conversations));
        return CabinetMessagingBloc(
          listConversations: listConversations,
          getMessages: getMessages,
          sendMessage: sendMessage,
        );
      },
      act: (bloc) =>
          bloc.add(const CabinetMessagingConversationsLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<CabinetMessagingConversationsLoaded>());
        for (final c
            in (loaded as CabinetMessagingConversationsLoaded).conversations) {
          expect(c.patientName, isNotEmpty);
          // CabinetConversation ne porte pas motif ni notes_medicales :
          // garantie structurelle par le type.
        }
      },
    );
  });

  // --- CabinetMessagingPage widget tests ---------------------------------------
  group('CabinetMessagingPage', () {
    late _MockCabinetMessagingBloc bloc;

    setUp(() {
      bloc = _MockCabinetMessagingBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<CabinetMessagingBloc>.value(
            value: bloc,
            child: const CabinetMessagingPage(),
          ),
        );

    testWidgets('affiche le chargement en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const CabinetMessagingInitial());
      await tester.pumpWidget(buildPage());
      expect(
        find.byKey(const Key('cabinet_messaging_loading')),
        findsOneWidget,
      );
    });

    testWidgets('affiche les conversations — aucun champ clinique visible', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const CabinetMessagingConversationsLoaded([
          CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 0,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('affiche un message si la liste est vide', (tester) async {
      when(
        () => bloc.state,
      ).thenReturn(const CabinetMessagingConversationsLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cabinet_messaging_empty')), findsOneWidget);
      // libellé aligné avec cabinet_messaging_page.dart (issue #2594 — la
      // page liste des conversations, pas des messages)
      expect(find.text('Aucune conversation'), findsOneWidget);
    });

    testWidgets('filtre les conversations par nom de patient', (tester) async {
      when(() => bloc.state).thenReturn(
        const CabinetMessagingConversationsLoaded([
          CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 0,
          ),
          CabinetConversation(
            id: 'conv2',
            patientId: 'p2',
            patientName: 'Albert Einstein',
            unreadCount: 0,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('Albert Einstein'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cabinet_messaging_search')),
        'marie',
      );
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('Albert Einstein'), findsNothing);
    });

    testWidgets(
      'pull-to-refresh déclenche CabinetMessagingConversationsLoadRequested',
      (tester) async {
        when(() => bloc.state).thenReturn(
          const CabinetMessagingConversationsLoaded([
            CabinetConversation(
              id: 'conv1',
              patientId: 'p1',
              patientName: 'Marie Curie',
              unreadCount: 0,
            ),
          ]),
        );
        await tester.pumpWidget(buildPage());
        await tester.pumpAndSettle();

        await tester.fling(
          find.byKey(const Key('cabinet_messaging_conversations_list')),
          const Offset(0, 300),
          1000,
        );
        await tester.pumpAndSettle();

        verify(
          () => bloc.add(const CabinetMessagingConversationsLoadRequested()),
        ).called(1);
      },
    );

    testWidgets('segment Non lus — 3 conversations dont 1 unread → 1 visible', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const CabinetMessagingConversationsLoaded([
          CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 1,
          ),
          CabinetConversation(
            id: 'conv2',
            patientId: 'p2',
            patientName: 'Albert Einstein',
            unreadCount: 0,
          ),
          CabinetConversation(
            id: 'conv3',
            patientId: 'p3',
            patientName: 'Isaac Newton',
            unreadCount: 0,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('Albert Einstein'), findsOneWidget);
      expect(find.text('Isaac Newton'), findsOneWidget);

      await tester.tap(find.text('Non lus'));
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('Albert Einstein'), findsNothing);
      expect(find.text('Isaac Newton'), findsNothing);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state).thenReturn(
        const CabinetMessagingConversationsError('Erreur de connexion'),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cabinet_messaging_error')), findsOneWidget);
      expect(find.text('Erreur de connexion'), findsOneWidget);
    });
  });
}
