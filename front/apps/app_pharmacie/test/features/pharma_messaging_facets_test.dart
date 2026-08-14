import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_bloc.dart';
import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_page.dart';

class _MockListConversations extends Mock
    implements ListCabinetConversationsUseCase {}

class _MockGetMessages extends Mock implements GetCabinetConversationUseCase {}

class _MockSendMessage extends Mock implements SendMessageCabinetUseCase {}

CabinetConversation _conversation(
  String id,
  String patientName, {
  int unread = 0,
  MessageUrgency triageFlag = MessageUrgency.normal,
}) =>
    CabinetConversation(
      id: id,
      patientId: 'pat_$id',
      patientName: patientName,
      unreadCount: unread,
      triageFlag: triageFlag,
    );

void main() {
  late _MockListConversations mockListConversations;
  late _MockGetMessages mockGetMessages;
  late _MockSendMessage mockSendMessage;

  setUp(() async {
    mockListConversations = _MockListConversations();
    mockGetMessages = _MockGetMessages();
    mockSendMessage = _MockSendMessage();

    await GetIt.instance.reset();
    GetIt.instance.registerFactory<PharmaMessagingBloc>(
      () => PharmaMessagingBloc(
        listConversations: mockListConversations,
        getMessages: mockGetMessages,
        sendMessage: mockSendMessage,
      ),
    );
  });

  tearDown(() async => GetIt.instance.reset());

  Future<void> pumpPage(
    WidgetTester tester,
    List<CabinetConversation> conversations, {
    Size size = const Size(1200, 800),
  }) async {
    when(() => mockListConversations()).thenAnswer(
      (_) async => Right(conversations),
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: PharmaMessagingPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PharmaMessagingPage — facettes Toutes / Non lues / Urgentes (#4932)',
      () {
    final conversations = [
      _conversation('c1', 'Jean Dupont', unread: 2),
      _conversation('c2', 'Marie Curie', triageFlag: MessageUrgency.urgent),
      _conversation('c3', 'Ahmed Belkacem'),
    ];

    testWidgets('affiche les trois facettes avec leurs compteurs',
        (tester) async {
      await pumpPage(tester, conversations);

      final all =
          find.byKey(const Key('pharma_messaging_facet_all'));
      final unread =
          find.byKey(const Key('pharma_messaging_facet_unread'));
      final urgent =
          find.byKey(const Key('pharma_messaging_facet_urgent'));

      expect(all, findsOneWidget);
      expect(unread, findsOneWidget);
      expect(urgent, findsOneWidget);

      expect(tester.widget<NubiaChip>(all).count, 3);
      expect(tester.widget<NubiaChip>(unread).count, 1);
      expect(tester.widget<NubiaChip>(urgent).count, 1);
      expect(tester.widget<NubiaChip>(all).selected, isTrue);
    });

    testWidgets('« Non lues » ne montre que unreadCount > 0',
        (tester) async {
      await pumpPage(tester, conversations);

      await tester.tap(
        find.byKey(const Key('pharma_messaging_facet_unread')),
      );
      await tester.pump();

      expect(find.byKey(const Key('conv_c1')), findsOneWidget);
      expect(find.byKey(const Key('conv_c2')), findsNothing);
      expect(find.byKey(const Key('conv_c3')), findsNothing);
      expect(
        tester
            .widget<NubiaChip>(
                find.byKey(const Key('pharma_messaging_facet_unread')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<NubiaChip>(
                find.byKey(const Key('pharma_messaging_facet_all')))
            .selected,
        isFalse,
      );
    });

    testWidgets('« Urgentes » ne montre que les conversations triageFlag',
        (tester) async {
      await pumpPage(tester, conversations);

      await tester.tap(
        find.byKey(const Key('pharma_messaging_facet_urgent')),
      );
      await tester.pump();

      expect(find.byKey(const Key('conv_c1')), findsNothing);
      expect(find.byKey(const Key('conv_c2')), findsOneWidget);
      expect(find.byKey(const Key('conv_c3')), findsNothing);
    });

    testWidgets('revenir sur « Toutes » réaffiche la liste complète',
        (tester) async {
      await pumpPage(tester, conversations);

      await tester.tap(
        find.byKey(const Key('pharma_messaging_facet_urgent')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('pharma_messaging_facet_all')));
      await tester.pump();

      expect(find.byKey(const Key('conv_c1')), findsOneWidget);
      expect(find.byKey(const Key('conv_c2')), findsOneWidget);
      expect(find.byKey(const Key('conv_c3')), findsOneWidget);
    });
  });
}
