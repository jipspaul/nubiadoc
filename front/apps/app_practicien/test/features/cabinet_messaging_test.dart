import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/cabinet_messaging/cabinet_messaging_bloc.dart';
import 'package:app_practicien/features/cabinet_messaging/cabinet_messaging_event.dart';
import 'package:app_practicien/features/cabinet_messaging/cabinet_messaging_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListCabinetConversationsUseCase extends Mock
    implements ListCabinetConversationsUseCase {}

class MockGetCabinetConversationUseCase extends Mock
    implements GetCabinetConversationUseCase {}

class MockSendMessageCabinetUseCase extends Mock
    implements SendMessageCabinetUseCase {}

class MockConvertConversationToAppointmentUseCase extends Mock
    implements ConvertConversationToAppointmentUseCase {}

class MockCabinetMessagingBloc
    extends MockBloc<CabinetMessagingEvent, CabinetMessagingState>
    implements CabinetMessagingBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _conversation = CabinetConversation(
  id: 'conv-1',
  patientId: 'pat-1',
  patientName: 'Marie Dupont',
  unreadCount: 2,
);

final _message = Message(
  id: 'msg-1',
  conversationId: 'conv-1',
  sender: MessageSender.patient,
  text: 'Bonjour docteur',
  urgency: MessageUrgency.normal,
  sentAt: DateTime(2026, 6, 1, 10),
);

CabinetMessagingBloc _makeBloc({
  required MockListCabinetConversationsUseCase list,
  required MockGetCabinetConversationUseCase getMessages,
  required MockSendMessageCabinetUseCase send,
  MockConvertConversationToAppointmentUseCase? convertToAppointment,
}) =>
    CabinetMessagingBloc(
      listConversations: list,
      getMessages: getMessages,
      sendMessage: send,
      convertToAppointment:
          convertToAppointment ?? MockConvertConversationToAppointmentUseCase(),
    );

Widget _wrap(CabinetMessagingBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _Body()),
      ),
    );

Widget _wrapMock(MockCabinetMessagingBloc bloc) => MaterialApp(
      home: BlocProvider<CabinetMessagingBloc>.value(
        value: bloc,
        child: const Scaffold(body: _Body()),
      ),
    );

/// Minimal widget that renders based on bloc state (avoids GetIt dependency).
class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CabinetMessagingBloc, CabinetMessagingState>(
      builder: (context, state) {
        if (state is CabinetMessagingInitial ||
            state is CabinetMessagingConversationsLoading) {
          return const Center(
              key: Key('cabinet_messaging_loading'),
              child: CircularProgressIndicator());
        }
        if (state is CabinetMessagingConversationsError) {
          return Center(
              key: const Key('cabinet_messaging_error'),
              child: Text(state.message));
        }
        if (state is CabinetMessagingConversationsLoaded) {
          if (state.conversations.isEmpty) {
            return const NubiaEmptyState(
              key: Key('cabinet_messaging_empty'),
              icon: Icons.chat_bubble_outline,
              title: 'Aucun message',
              subtitle: 'Vos conversations cabinet apparaîtront ici',
            );
          }
          return ListView(
            key: const Key('cabinet_messaging_conversations_list'),
            children: [
              for (final c in state.conversations)
                ListTile(
                  key: Key('conv_${c.id}'),
                  title: Text(c.patientName),
                  onTap: () => context
                      .read<CabinetMessagingBloc>()
                      .add(CabinetMessagingThreadOpened(c)),
                ),
            ],
          );
        }
        if (state is CabinetMessagingThreadLoaded) {
          return Column(
            key: const Key('cabinet_messaging_thread'),
            children: [
              Text(state.conversation.patientName),
              for (final m in state.messages)
                Text(key: Key('msg_${m.id}'), m.text ?? ''),
            ],
          );
        }
        if (state is CabinetMessagingThreadError) {
          return Center(
              key: const Key('cabinet_messaging_thread_error'),
              child: Text(state.message));
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc tests
// ---------------------------------------------------------------------------

void main() {
  late MockListCabinetConversationsUseCase mockList;
  late MockGetCabinetConversationUseCase mockGetMessages;
  late MockSendMessageCabinetUseCase mockSend;

  setUp(() {
    mockList = MockListCabinetConversationsUseCase();
    mockGetMessages = MockGetCabinetConversationUseCase();
    mockSend = MockSendMessageCabinetUseCase();
  });

  group('CabinetMessagingBloc', () {
    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'émet Loading puis Loaded avec les conversations',
      build: () {
        when(() => mockList()).thenAnswer((_) async => Right([_conversation]));
        return _makeBloc(
            list: mockList, getMessages: mockGetMessages, send: mockSend);
      },
      act: (bloc) =>
          bloc.add(const CabinetMessagingConversationsLoadRequested()),
      expect: () => [
        const CabinetMessagingConversationsLoading(),
        CabinetMessagingConversationsLoaded([_conversation]),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'émet Loading puis Loaded vide quand aucune conversation',
      build: () {
        when(() => mockList()).thenAnswer((_) async => const Right([]));
        return _makeBloc(
            list: mockList, getMessages: mockGetMessages, send: mockSend);
      },
      act: (bloc) =>
          bloc.add(const CabinetMessagingConversationsLoadRequested()),
      expect: () => [
        const CabinetMessagingConversationsLoading(),
        const CabinetMessagingConversationsLoaded([]),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'émet Error quand le chargement échoue',
      build: () {
        when(() => mockList()).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return _makeBloc(
            list: mockList, getMessages: mockGetMessages, send: mockSend);
      },
      act: (bloc) =>
          bloc.add(const CabinetMessagingConversationsLoadRequested()),
      expect: () => [
        const CabinetMessagingConversationsLoading(),
        const CabinetMessagingConversationsError('Réseau indisponible'),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'ouvre le thread et charge les messages',
      build: () {
        when(() => mockGetMessages(_conversation.id))
            .thenAnswer((_) async => Right([_message]));
        return _makeBloc(
            list: mockList, getMessages: mockGetMessages, send: mockSend);
      },
      act: (bloc) => bloc.add(CabinetMessagingThreadOpened(_conversation)),
      expect: () => [
        CabinetMessagingThreadLoading(_conversation.id),
        CabinetMessagingThreadLoaded(
          conversation: _conversation,
          messages: [_message],
        ),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'envoie un message et l\'ajoute à la liste',
      build: () {
        when(() => mockSend(
              conversationId: _conversation.id,
              text: 'Bonjour patient',
              attachmentIds: any(named: 'attachmentIds'),
            )).thenAnswer((_) async => Right(_message));
        return _makeBloc(
            list: mockList, getMessages: mockGetMessages, send: mockSend);
      },
      seed: () => CabinetMessagingThreadLoaded(
        conversation: _conversation,
        messages: const [],
      ),
      act: (bloc) => bloc.add(CabinetMessagingSendRequested(
        conversationId: _conversation.id,
        text: 'Bonjour patient',
      )),
      expect: () => [
        CabinetMessagingThreadLoaded(
          conversation: _conversation,
          messages: const [],
          sending: true,
        ),
        CabinetMessagingThreadLoaded(
          conversation: _conversation,
          messages: [_message],
        ),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'convertit la conversation en RDV (#4159/#4160)',
      build: () {
        final mockConvert = MockConvertConversationToAppointmentUseCase();
        when(() => mockConvert(
              conversationId: _conversation.id,
              slotId: 'slot-1',
            )).thenAnswer((_) async => const Right(
              ConversationAppointmentConversion(
                appointmentId: 'appt-1',
                status: 'requested',
              ),
            ));
        return _makeBloc(
          list: mockList,
          getMessages: mockGetMessages,
          send: mockSend,
          convertToAppointment: mockConvert,
        );
      },
      seed: () => CabinetMessagingThreadLoaded(
        conversation: _conversation,
        messages: const [],
      ),
      act: (bloc) => bloc.add(const CabinetMessagingConvertToAppointmentRequested(
        conversationId: 'conv-1',
        slotId: 'slot-1',
      )),
      expect: () => [
        CabinetMessagingThreadLoaded(
          conversation: _conversation,
          messages: const [],
          converting: true,
        ),
        CabinetMessagingThreadLoaded(
          conversation: _conversation,
          messages: const [],
        ),
      ],
    );

    blocTest<CabinetMessagingBloc, CabinetMessagingState>(
      'conversion en RDV échouée — reste dans le thread avec une erreur',
      build: () {
        final mockConvert = MockConvertConversationToAppointmentUseCase();
        when(() => mockConvert(
              conversationId: _conversation.id,
              slotId: 'slot-1',
            )).thenAnswer(
          (_) async =>
              const Left(ValidationFailure(message: 'Ce créneau vient d\'être réservé, choisissez-en un autre.')),
        );
        return _makeBloc(
          list: mockList,
          getMessages: mockGetMessages,
          send: mockSend,
          convertToAppointment: mockConvert,
        );
      },
      seed: () => CabinetMessagingThreadLoaded(
        conversation: _conversation,
        messages: const [],
      ),
      act: (bloc) => bloc.add(const CabinetMessagingConvertToAppointmentRequested(
        conversationId: 'conv-1',
        slotId: 'slot-1',
      )),
      expect: () => [
        CabinetMessagingThreadLoaded(
          conversation: _conversation,
          messages: const [],
          converting: true,
        ),
        CabinetMessagingThreadLoaded(
          conversation: _conversation,
          messages: const [],
          conversionError: 'Ce créneau vient d\'être réservé, choisissez-en un autre.',
        ),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('CabinetMessagingPage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_conversation]));
      final bloc = _makeBloc(
          list: mockList, getMessages: mockGetMessages, send: mockSend);
      await tester.pumpWidget(_wrap(bloc));
      expect(
          find.byKey(const Key('cabinet_messaging_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste après chargement', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_conversation]));
      final bloc = _makeBloc(
          list: mockList, getMessages: mockGetMessages, send: mockSend)
        ..add(const CabinetMessagingConversationsLoadRequested());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('conv_conv-1')), findsOneWidget);
    });

    testWidgets('affiche l\'état vide quand aucune conversation',
        (tester) async {
      when(() => mockList()).thenAnswer((_) async => const Right([]));
      final bloc = _makeBloc(
          list: mockList, getMessages: mockGetMessages, send: mockSend)
        ..add(const CabinetMessagingConversationsLoadRequested());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('cabinet_messaging_empty')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec', (tester) async {
      when(() => mockList()).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = _makeBloc(
          list: mockList, getMessages: mockGetMessages, send: mockSend)
        ..add(const CabinetMessagingConversationsLoadRequested());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('cabinet_messaging_error')), findsOneWidget);
    });

    testWidgets('affiche le thread après ouverture d\'une conversation',
        (tester) async {
      when(() => mockGetMessages(_conversation.id))
          .thenAnswer((_) async => Right([_message]));
      final bloc = _makeBloc(
          list: mockList, getMessages: mockGetMessages, send: mockSend)
        ..add(CabinetMessagingThreadOpened(_conversation));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('cabinet_messaging_thread')), findsOneWidget);
      expect(find.byKey(const Key('msg_msg-1')), findsOneWidget);
    });

    // ---- Tests requis FR2.13 ------------------------------------------------

    testWidgets('état Initial — skeleton de chargement visible',
        (tester) async {
      final mockBloc = MockCabinetMessagingBloc();
      when(() => mockBloc.state).thenReturn(const CabinetMessagingInitial());
      await tester.pumpWidget(_wrapMock(mockBloc));
      expect(
        find.byKey(const Key('cabinet_messaging_loading')),
        findsOneWidget,
      );
    });

    testWidgets(
        'état Loaded avec 2 conversations — 2 tiles visibles avec patientName',
        (tester) async {
      final conv2 = CabinetConversation(
        id: 'conv-2',
        patientId: 'pat-2',
        patientName: 'Pierre Martin',
        unreadCount: 0,
      );
      final mockBloc = MockCabinetMessagingBloc();
      when(() => mockBloc.state).thenReturn(
        CabinetMessagingConversationsLoaded([_conversation, conv2]),
      );
      await tester.pumpWidget(_wrapMock(mockBloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('conv_conv-1')), findsOneWidget);
      expect(find.byKey(const Key('conv_conv-2')), findsOneWidget);
      expect(find.text('Marie Dupont'), findsOneWidget);
      expect(find.text('Pierre Martin'), findsOneWidget);
    });

    testWidgets('Loaded([]) — NubiaEmptyState visible', (tester) async {
      final mockBloc = MockCabinetMessagingBloc();
      when(() => mockBloc.state)
          .thenReturn(const CabinetMessagingConversationsLoaded([]));
      await tester.pumpWidget(_wrapMock(mockBloc));
      await tester.pump();
      expect(find.byType(NubiaEmptyState), findsOneWidget);
      expect(find.byKey(const Key('cabinet_messaging_empty')), findsOneWidget);
    });

    testWidgets('tap sur une tile — dispatch CabinetMessagingThreadOpened',
        (tester) async {
      final mockBloc = MockCabinetMessagingBloc();
      when(() => mockBloc.state).thenReturn(
        CabinetMessagingConversationsLoaded([_conversation]),
      );
      await tester.pumpWidget(_wrapMock(mockBloc));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('conv_conv-1')));
      await tester.pump();

      verify(
        () => mockBloc.add(CabinetMessagingThreadOpened(_conversation)),
      ).called(1);
    });
  });
}
