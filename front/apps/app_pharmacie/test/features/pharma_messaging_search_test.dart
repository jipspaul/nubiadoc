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
  String? orderRef,
}) =>
    CabinetConversation(
      id: id,
      patientId: 'pat_$id',
      patientName: patientName,
      unreadCount: unread,
      orderRef: orderRef,
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

  group('PharmaMessagingPage — recherche des conversations (#4931)', () {
    testWidgets('champ de recherche avec le placeholder de la maquette',
        (tester) async {
      await pumpPage(tester, [_conversation('c1', 'Jean Dupont')]);

      final searchField = find.byKey(const Key('pharma_messaging_search'));
      expect(searchField, findsOneWidget);
      final field = tester.widget<TextField>(searchField);
      expect(field.decoration?.hintText, 'Patient, n° de commande…');
    });

    testWidgets('filtre sur le nom du patient, insensible à la casse',
        (tester) async {
      await pumpPage(tester, [
        _conversation('c1', 'Jean Dupont'),
        _conversation('c2', 'Marie Curie'),
      ]);

      expect(find.byKey(const Key('conv_c1')), findsOneWidget);
      expect(find.byKey(const Key('conv_c2')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('pharma_messaging_search')),
        'marie',
      );
      await tester.pump();

      expect(find.byKey(const Key('conv_c1')), findsNothing);
      expect(find.byKey(const Key('conv_c2')), findsOneWidget);
    });

    testWidgets('filtre sur la référence commande', (tester) async {
      await pumpPage(tester, [
        _conversation('c1', 'Jean Dupont', orderRef: 'CMD-4821'),
        _conversation('c2', 'Marie Curie'),
      ]);

      await tester.enterText(
        find.byKey(const Key('pharma_messaging_search')),
        'cmd-4821',
      );
      await tester.pump();

      expect(find.byKey(const Key('conv_c1')), findsOneWidget);
      expect(find.byKey(const Key('conv_c2')), findsNothing);
    });

    testWidgets('champ vide → liste complète', (tester) async {
      await pumpPage(tester, [
        _conversation('c1', 'Jean Dupont'),
        _conversation('c2', 'Marie Curie'),
      ]);

      final search = find.byKey(const Key('pharma_messaging_search'));
      await tester.enterText(search, 'marie');
      await tester.pump();
      expect(find.byKey(const Key('conv_c1')), findsNothing);

      await tester.enterText(search, '');
      await tester.pump();
      expect(find.byKey(const Key('conv_c1')), findsOneWidget);
      expect(find.byKey(const Key('conv_c2')), findsOneWidget);
    });

    testWidgets(
        "l'en-tête X conversations · Y non lues reste basé sur la liste complète",
        (tester) async {
      await pumpPage(tester, [
        _conversation('c1', 'Jean Dupont', unread: 2),
        _conversation('c2', 'Marie Curie'),
      ]);

      await tester.enterText(
        find.byKey(const Key('pharma_messaging_search')),
        'marie',
      );
      await tester.pump();

      expect(find.textContaining('2 conversations'), findsOneWidget);
      expect(find.textContaining('1 non lue'), findsOneWidget);
    });
  });
}
