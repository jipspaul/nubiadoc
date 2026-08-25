//! Tests widget : `CabinetTeamMessagesPage` (#4156) — chargement, empty
//! state, envoi d'un message et affichage, distinct de la messagerie
//! patient.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
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

final _messageWithPatientReference = CabinetTeamMessage(
  id: 'm2',
  senderId: 'u1',
  senderName: 'Dr Martin',
  body: 'Peux-tu reprogrammer le labo ?',
  createdAt: DateTime(2026, 1, 1, 10),
  reference: const CabinetTeamMessageReference(
    type: CabinetTeamMessageReferenceType.patient,
    targetId: 'p1',
    title: 'Couronne céramo-métallique · dent 26',
    subtitle: 'Labo Kléber · à programmer',
  ),
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

  Widget buildRoutedPage() {
    final router = GoRouter(
      initialLocation: '/team-messages',
      routes: [
        GoRoute(
          path: '/team-messages',
          builder: (_, __) => const CabinetTeamMessagesPage(),
        ),
        GoRoute(
          path: '/patients',
          builder: (_, state) => Scaffold(
            key: const Key('patients_page_stub'),
            body: Text('Patient ${state.extra}'),
          ),
        ),
        GoRoute(
          path: '/devis/:id',
          builder: (_, state) => Scaffold(
            key: const Key('devis_page_stub'),
            body: Text('Devis ${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
    return MaterialApp.router(
      theme: NubiaTheme.light,
      routerConfig: router,
    );
  }

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

  group('recherche dans le fil (#5132)', () {
    final message2 = CabinetTeamMessage(
      id: 'm2',
      senderId: 'u2',
      senderName: 'Claire Béranger',
      body: 'Qu\'est-ce qu\'on avait dit pour les congés ?',
      createdAt: DateTime(2026, 1, 2, 10),
    );

    testWidgets('barre de recherche visible avec le placeholder attendu',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_messages_search')), findsOneWidget);
      expect(find.text('Rechercher dans le fil…'), findsOneWidget);
    });

    testWidgets('taper un terme filtre le fil affiché', (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([_message1, message2]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_message_m1')), findsOneWidget);
      expect(find.byKey(const Key('team_message_m2')), findsOneWidget);

      final searchField = find.descendant(
        of: find.byKey(const Key('team_messages_search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(searchField, 'congés');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_message_m1')), findsNothing);
      expect(find.byKey(const Key('team_message_m2')), findsOneWidget);
    });

    testWidgets('vider la recherche restaure le fil complet', (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([_message1, message2]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final searchField = find.descendant(
        of: find.byKey(const Key('team_messages_search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(searchField, 'congés');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team_message_m1')), findsNothing);

      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_message_m1')), findsOneWidget);
      expect(find.byKey(const Key('team_message_m2')), findsOneWidget);
    });
  });

  group('rappel « aucune donnée clinique » (#5135)', () {
    testWidgets('affiché sous le composeur, à toute largeur', (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('team_message_no_clinical_data_hint')),
        findsOneWidget,
      );
      expect(find.text('Aucune donnée clinique dans ce fil'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('team_message_no_clinical_data_hint')),
          matching: find.byIcon(Icons.shield),
        ),
        findsOneWidget,
      );
    });

    // La note vit en bas du panneau « Équipe » (#5133), donc desktop
    // uniquement : sous 900 px de large la colonne latérale est masquée.
    testWidgets('desktop → note épinglée en bas du panneau « Équipe »',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_messages_aside_note')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('team_aside')),
          matching: find.byKey(const Key('team_messages_aside_note')),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Ce fil est interne au cabinet et distinct de la messagerie '
          'patient. Les échanges cliniques doivent rester dans le '
          'dossier médical.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('team_messages_aside_note')),
          matching: find.byIcon(Icons.shield),
        ),
        findsOneWidget,
      );
    });
  });

  group('référence à un objet du produit (#5131)', () {
    testWidgets(
        'message avec référence → carte affichée (icône, 2 lignes, Ouvrir)',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([_messageWithPatientReference]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final chip = find.byKey(const Key('team_message_reference_p1'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(
          of: chip,
          matching: find.byIcon(Icons.person_outline),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: chip,
          matching: find.text('Couronne céramo-métallique · dent 26'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: chip,
          matching: find.text('Labo Kléber · à programmer'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip, matching: find.text('Ouvrir')),
        findsOneWidget,
      );
    });

    testWidgets('message sans référence → pas de carte affichée',
        (tester) async {
      when(() => listMessages()).thenAnswer((_) async => Right([_message1]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_message_reference_p1')), findsNothing);
    });

    testWidgets('tap Ouvrir → navigue vers la route existante de l\'objet cité',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([_messageWithPatientReference]));

      await tester.pumpWidget(buildRoutedPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('team_message_reference_open_p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patients_page_stub')), findsOneWidget);
      expect(find.text('Patient p1'), findsOneWidget);
    });

    testWidgets(
        'composeur → bouton « Joindre un patient, un devis… » avec icône link',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('team_message_attach_reference_button'));
      expect(button, findsOneWidget);
      expect(find.text('Joindre un patient, un devis…'), findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.link)),
        findsOneWidget,
      );
    });

    testWidgets(
        'desktop → récap « Éléments cités aujourd\'hui » dans le panneau Équipe',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final recap = find.byKey(const Key('team_aside_cited_references'));
      expect(recap, findsOneWidget);
      expect(
        find.descendant(
          of: recap,
          matching: find.text('Éléments cités aujourd\'hui'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: recap, matching: find.text('Couronne · dent 26')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: recap, matching: find.text('Travaux labo')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: recap, matching: find.text('Demande de stock')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: recap,
          matching: find.text('Pharmacie du Théâtre'),
        ),
        findsOneWidget,
      );
    });
  });
}
