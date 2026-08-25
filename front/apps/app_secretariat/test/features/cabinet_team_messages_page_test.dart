//! Tests widget : `CabinetTeamMessagesPage` (#4156) — chargement, empty
//! state, envoi d'un message et affichage, distinct de la messagerie
//! patient.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
      'chargement → skeleton affiché (pas de CircularProgressIndicator)',
      (tester) async {
    final completer = Completer<Either<Failure, List<CabinetTeamMessage>>>();
    when(() => listMessages()).thenAnswer((_) => completer.future);

    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.byKey(const Key('team_messages_loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    completer.complete(const Right(<CabinetTeamMessage>[]));
    await tester.pumpAndSettle();
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

  testWidgets(
      '⇧⏎ insère une nouvelle ligne sans envoyer, ⏎ seul envoie (#5136)',
      (tester) async {
    when(() => listMessages())
        .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));
    when(() => sendMessage(any())).thenAnswer((_) async => const Right('m1'));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('team_message_input')));
    await tester.enterText(
      find.byKey(const Key('team_message_input')),
      'Bonjour',
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    final field = tester.widget<TextField>(find.descendant(
      of: find.byKey(const Key('team_message_input')),
      matching: find.byType(TextField),
    ));
    expect(field.controller!.text, 'Bonjour\n');
    verifyNever(() => sendMessage(any()));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    verify(() => sendMessage('Bonjour')).called(1);
  });

  testWidgets('rappels clavier ⏎ envoyer / ⇧⏎ nouvelle ligne affichés',
      (tester) async {
    when(() => listMessages())
        .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('team_message_keyboard_hints')),
      findsOneWidget,
    );
    expect(find.text('⏎'), findsOneWidget);
    expect(find.text('envoyer'), findsOneWidget);
    expect(find.text('⇧⏎'), findsOneWidget);
    expect(find.text('nouvelle ligne'), findsOneWidget);
  });

  group('panneau « Équipe » (#5133)', () {
    testWidgets('desktop → liste les 4 membres avec pastille de présence',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_aside')), findsOneWidget);
      expect(find.text('Équipe'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('team_aside_count_badge')),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );

      expect(find.byKey(const Key('team_member_SL')), findsOneWidget);
      expect(find.text('Sarah Lemoine'), findsOneWidget);
      expect(find.text('Secrétaire · vous'), findsOneWidget);

      expect(find.byKey(const Key('team_member_AR')), findsOneWidget);
      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.text('Praticienne · en consultation'), findsOneWidget);

      expect(find.byKey(const Key('team_member_ML')), findsOneWidget);
      expect(find.text('Dr Marc Lefèvre'), findsOneWidget);
      expect(find.text('Praticien · absent'), findsOneWidget);

      expect(find.byKey(const Key('team_member_CB')), findsOneWidget);
      expect(find.text('Claire Béranger'), findsOneWidget);
      expect(find.text('Assistante'), findsOneWidget);

      final presentPastille = tester.widget<Container>(
        find.byKey(const Key('team_member_status_SL')),
      );
      final presentDecoration =
          presentPastille.decoration! as BoxDecoration;
      expect(presentDecoration.color, NubiaColors.successFg);

      final absentPastille = tester.widget<Container>(
        find.byKey(const Key('team_member_status_ML')),
      );
      final absentDecoration = absentPastille.decoration! as BoxDecoration;
      expect(absentDecoration.color, NubiaColors.n300);
    });

    testWidgets('étroit (mobile) → panneau « Équipe » masqué', (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_aside')), findsNothing);
    });
  });
}
