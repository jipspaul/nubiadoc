import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
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

class _MockListBookableSlotsUseCase extends Mock
    implements ListBookableSlotsUseCase {}

final _slot = Slot(
  id: 'slot-1',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  startsAt: DateTime(2026, 8, 10, 9),
  endsAt: DateTime(2026, 8, 10, 9, 30),
  isAvailable: true,
);

/// Reproduit le formatage privé `AppointmentSlotPicker._slotLabel`.
String _expectedSlotLabel(DateTime d) {
  const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  const months = [
    'jan.', 'fév.', 'mar.', 'avr.', 'mai', 'juin', //
    'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.',
  ];
  final h = '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} – $h';
}

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
          convertToAppointment: ConvertConversationToAppointmentUseCase(repo),
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
          convertToAppointment: ConvertConversationToAppointmentUseCase(repo),
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
          convertToAppointment: ConvertConversationToAppointmentUseCase(repo),
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
          convertToAppointment: ConvertConversationToAppointmentUseCase(repo),
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

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'convertit la conversation en RDV (#4159/#4160)',
      build: () {
        when(() => repo.convertToAppointment(
              conversationId: 'conv1',
              slotId: 'slot-1',
            )).thenAnswer((_) async => const Right(
              ConversationAppointmentConversion(
                appointmentId: 'appt-1',
                status: 'requested',
              ),
            ));
        return CabinetMessagingBloc(
          listConversations: listConversations,
          getMessages: getMessages,
          sendMessage: sendMessage,
          convertToAppointment: ConvertConversationToAppointmentUseCase(repo),
        );
      },
      seed: () => const CabinetMessagingThreadLoaded(
        conversation: CabinetConversation(
          id: 'conv1',
          patientId: 'p1',
          patientName: 'Marie Curie',
          unreadCount: 0,
        ),
        messages: [],
      ),
      act: (bloc) =>
          bloc.add(const CabinetMessagingConvertToAppointmentRequested(
        conversationId: 'conv1',
        slotId: 'slot-1',
      )),
      expect: () => [
        const CabinetMessagingThreadLoaded(
          conversation: CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 0,
          ),
          messages: [],
          converting: true,
        ),
        const CabinetMessagingThreadLoaded(
          conversation: CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 0,
          ),
          messages: [],
        ),
      ],
    );
  });

  // --- CabinetMessagingPage widget tests ---------------------------------------
  group('CabinetMessagingPage', () {
    late _MockCabinetMessagingBloc bloc;

    setUp(() {
      bloc = _MockCabinetMessagingBloc();
    });

    Widget buildPage({String? openConversationId}) => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<CabinetMessagingBloc>.value(
            value: bloc,
            child: CabinetMessagingPage(
              openConversationId: openConversationId,
            ),
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

    testWidgets(
      '#6246 : openConversationId ouvre automatiquement le thread visé une '
      'fois les conversations chargées',
      (tester) async {
        const target = CabinetConversation(
          id: 'conv2',
          patientId: 'p2',
          patientName: 'Albert Einstein',
          unreadCount: 1,
        );
        const loaded = CabinetMessagingConversationsLoaded([
          CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 0,
          ),
          target,
        ]);

        whenListen(
          bloc,
          Stream<CabinetMessagingState>.fromIterable([
            const CabinetMessagingConversationsLoading(),
            loaded,
          ]),
          initialState: const CabinetMessagingConversationsLoading(),
        );

        await tester.pumpWidget(buildPage(openConversationId: 'conv2'));
        await tester.pumpAndSettle();

        verify(
          () => bloc.add(const CabinetMessagingThreadOpened(target)),
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

    testWidgets(
      'affiche le chargement en état ConversationsLoading',
      (tester) async {
        when(() => bloc.state).thenReturn(
          const CabinetMessagingConversationsLoading(),
        );
        await tester.pumpWidget(buildPage());
        expect(
          find.byKey(const Key('cabinet_messaging_loading')),
          findsOneWidget,
        );
      },
    );

    testWidgets('affiche le chargement du thread', (tester) async {
      when(() => bloc.state).thenReturn(
        const CabinetMessagingThreadLoading('conv1'),
      );
      await tester.pumpWidget(buildPage());
      expect(
        find.byKey(const Key('cabinet_messaging_thread_loading')),
        findsOneWidget,
      );
    });

    testWidgets('affiche le thread avec ses messages', (tester) async {
      when(() => bloc.state).thenReturn(
        CabinetMessagingThreadLoaded(
          conversation: const CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 0,
          ),
          messages: [
            Message(
              id: 'msg1',
              conversationId: 'conv1',
              sender: MessageSender.patient,
              text: 'Bonjour',
              urgency: MessageUrgency.normal,
              sentAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cabinet_messaging_thread_messages')),
        findsOneWidget,
      );
      expect(find.text('Bonjour'), findsOneWidget);
    });

    testWidgets('affiche le thread vide', (tester) async {
      when(() => bloc.state).thenReturn(
        CabinetMessagingThreadLoaded(
          conversation: const CabinetConversation(
            id: 'conv1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            unreadCount: 0,
          ),
          messages: const [],
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cabinet_messaging_thread_empty')),
        findsOneWidget,
      );
    });

    testWidgets('affiche l\'erreur de chargement du thread', (tester) async {
      when(() => bloc.state).thenReturn(
        const CabinetMessagingThreadError(
          conversationId: 'conv1',
          message: 'Erreur de chargement du thread',
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cabinet_messaging_thread_error')),
        findsOneWidget,
      );
      expect(find.text('Erreur de chargement du thread'), findsOneWidget);
    });

    group('Créer un RDV (#4159/#4160)', () {
      late _MockListBookableSlotsUseCase mockSlots;

      setUp(() {
        mockSlots = _MockListBookableSlotsUseCase();
        if (GetIt.instance.isRegistered<ListBookableSlotsUseCase>()) {
          GetIt.instance.unregister<ListBookableSlotsUseCase>();
        }
        GetIt.instance.registerFactory<ListBookableSlotsUseCase>(
          () => mockSlots,
        );
      });

      tearDown(() => GetIt.instance.reset());

      testWidgets(
        'thread → "Créer un RDV" → choix du créneau → dispatch '
        'CabinetMessagingConvertToAppointmentRequested',
        (tester) async {
          when(() => bloc.state).thenReturn(
            const CabinetMessagingThreadLoaded(
              conversation: CabinetConversation(
                id: 'conv1',
                patientId: 'p1',
                patientName: 'Marie Curie',
                unreadCount: 0,
              ),
              messages: [],
            ),
          );
          when(() => mockSlots()).thenAnswer((_) async => Right([_slot]));

          await tester.pumpWidget(buildPage());
          await tester.pump();

          expect(
            find.byKey(const Key('create_appointment_from_conversation')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('create_appointment_from_conversation')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('appointment_slot_picker')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('appointment_slot_dropdown')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(_expectedSlotLabel(_slot.startsAt)).last);
          await tester.pumpAndSettle();

          await tester
              .tap(find.byKey(const Key('appointment_slot_picker_confirm')));
          await tester.pumpAndSettle();

          verify(() => bloc.add(
                const CabinetMessagingConvertToAppointmentRequested(
                  conversationId: 'conv1',
                  slotId: 'slot-1',
                ),
              )).called(1);
        },
      );

      testWidgets(
        'converting: true — bouton remplacé par un indicateur de chargement',
        (tester) async {
          when(() => bloc.state).thenReturn(
            const CabinetMessagingThreadLoaded(
              conversation: CabinetConversation(
                id: 'conv1',
                patientId: 'p1',
                patientName: 'Marie Curie',
                unreadCount: 0,
              ),
              messages: [],
              converting: true,
            ),
          );
          await tester.pumpWidget(buildPage());
          await tester.pump();

          expect(
            find.byKey(const Key('create_appointment_from_conversation')),
            findsNothing,
          );
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        },
      );

      testWidgets('conversionError — bannière d\'erreur affichée',
          (tester) async {
        when(() => bloc.state).thenReturn(
          const CabinetMessagingThreadLoaded(
            conversation: CabinetConversation(
              id: 'conv1',
              patientId: 'p1',
              patientName: 'Marie Curie',
              unreadCount: 0,
            ),
            messages: [],
            conversionError:
                'Ce créneau vient d\'être réservé, choisissez-en un autre.',
          ),
        );
        await tester.pumpWidget(buildPage());
        await tester.pump();

        expect(
          find.byKey(const Key('conversion_error_banner')),
          findsOneWidget,
        );
        expect(
          find.text(
              'Ce créneau vient d\'être réservé, choisissez-en un autre.'),
          findsOneWidget,
        );
      });
    });
  });
}
