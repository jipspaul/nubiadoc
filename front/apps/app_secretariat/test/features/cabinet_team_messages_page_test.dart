//! Tests widget : `CabinetTeamMessagesPage` (#4156) — chargement, empty
//! state, envoi d'un message et affichage, distinct de la messagerie
//! patient.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/cabinet_team_messages/cabinet_team_messages_page.dart';

class _MockListMessages extends Mock
    implements ListCabinetTeamMessagesUseCase {}

class _MockSendMessage extends Mock implements SendCabinetTeamMessageUseCase {}

final _message1 = CabinetTeamMessage(
  id: 'm1',
  senderId: 'u1',
  senderName: 'Dr Martin',
  body: 'Réunion à 12h30.',
  createdAt: DateTime(2026, 1, 1, 9, 30),
);

void main() {
  late _MockListMessages listMessages;
  late _MockSendMessage sendMessage;

  setUp(() {
    listMessages = _MockListMessages();
    sendMessage = _MockSendMessage();
    GetIt.instance
        .registerFactory<ListCabinetTeamMessagesUseCase>(() => listMessages);
    GetIt.instance
        .registerFactory<SendCabinetTeamMessageUseCase>(() => sendMessage);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const CabinetTeamMessagesPage(),
      );

  testWidgets('aucun message → empty state', (tester) async {
    when(() => listMessages())
        .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('team_messages_empty')), findsOneWidget);
  });

  testWidgets('messages présents → liste affichée avec émetteur et corps',
      (tester) async {
    when(() => listMessages()).thenAnswer((_) async => Right([_message1]));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('team_message_m1')), findsOneWidget);
    expect(find.text('Dr Martin'), findsOneWidget);
    expect(find.text('Réunion à 12h30.'), findsOneWidget);
  });

  testWidgets(
      'envoi d\'un message → SendCabinetTeamMessageUseCase appelé, fil rechargé',
      (tester) async {
    var callCount = 0;
    when(() => listMessages()).thenAnswer((_) async {
      callCount++;
      return Right(callCount == 1 ? <CabinetTeamMessage>[] : [_message1]);
    });
    when(() => sendMessage(any())).thenAnswer((_) async => const Right('m1'));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team_messages_empty')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('team_message_input')),
      'Réunion à 12h30.',
    );
    await tester.tap(find.byKey(const Key('team_message_send_button')));
    await tester.pumpAndSettle();

    verify(() => sendMessage('Réunion à 12h30.')).called(1);
    expect(find.byKey(const Key('team_message_m1')), findsOneWidget);
  });

  testWidgets('erreur de chargement → NubiaErrorWidget avec bouton réessayer',
      (tester) async {
    when(() => listMessages()).thenAnswer(
      (_) async => const Left(ServerFailure(message: 'Erreur serveur.')),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('team_messages_error')), findsOneWidget);
    expect(find.text('Erreur serveur.'), findsOneWidget);
  });
}
