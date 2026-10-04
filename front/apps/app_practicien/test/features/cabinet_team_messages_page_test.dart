//! Tests widget : `CabinetTeamMessagesPage` (#4156, #6934 parité design-v2)
//! — chargement, empty state, envoi d'un message et affichage, distinct de
//! la messagerie patient.

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

import 'package:app_practicien/features/cabinet_team_messages/cabinet_team_messages_page.dart';

class _MockListMessages extends Mock
    implements ListCabinetTeamMessagesUseCase {}

class _MockSendMessage extends Mock implements SendCabinetTeamMessageUseCase {}

class _MockListPractitioners extends Mock
    implements ListCabinetPractitionersUseCase {}

class _MockGetAgenda extends Mock implements GetCabinetAgendaUseCase {}

final _message1 = CabinetTeamMessage(
  id: 'm1',
  senderId: 'u1',
  senderName: 'Dr Martin',
  body: 'Réunion à 12h30.',
  createdAt: DateTime(2026, 1, 1, 9, 30),
);

final _messageFromPractitioner = CabinetTeamMessage(
  id: 'm7',
  senderId: 'u2',
  senderName: 'Dr Amélie Rousseau',
  senderRole: 'Praticienne',
  body: 'Je passe au cabinet à 14h.',
  createdAt: DateTime(2026, 1, 1, 11),
);

final _messageFromStaff = CabinetTeamMessage(
  id: 'm8',
  senderId: 'u3',
  senderName: 'Claire Béranger',
  senderRole: 'Assistante',
  body: 'Le colis est arrivé.',
  createdAt: DateTime(2026, 1, 1, 11, 5),
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
  late _MockListPractitioners listPractitioners;
  late _MockGetAgenda getAgenda;

  setUp(() {
    listMessages = _MockListMessages();
    sendMessage = _MockSendMessage();
    listPractitioners = _MockListPractitioners();
    getAgenda = _MockGetAgenda();
    when(() => listPractitioners())
        .thenAnswer((_) async => const Right(<CabinetPractitioner>[]));
    when(() => getAgenda(any()))
        .thenAnswer((_) async => const Right(<AgendaEntry>[]));
    GetIt.instance
        .registerFactory<ListCabinetTeamMessagesUseCase>(() => listMessages);
    GetIt.instance
        .registerFactory<SendCabinetTeamMessageUseCase>(() => sendMessage);
    GetIt.instance.registerFactory<ListCabinetPractitionersUseCase>(
        () => listPractitioners);
    GetIt.instance.registerFactory<GetCabinetAgendaUseCase>(() => getAgenda);
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
          path: '/patients/:id',
          builder: (_, state) => Scaffold(
            key: const Key('patients_page_stub'),
            body: Text('Patient ${state.pathParameters['id']}'),
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

  group('badge rôle de l\'auteur (#5125)', () {
    testWidgets('message d\'un praticien → badge violet avec le libellé',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([_messageFromPractitioner]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Praticienne'), findsOneWidget);
      final pill = tester.widget<StatusPill>(find.byType(StatusPill));
      expect(pill.variant, StatusPillVariant.practitioner);
    });

    testWidgets('message du staff → badge neutre avec le libellé',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([_messageFromStaff]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Assistante'), findsOneWidget);
      final pill = tester.widget<StatusPill>(find.byType(StatusPill));
      expect(pill.variant, StatusPillVariant.neutral);
    });

    testWidgets('message sans rôle → pas de badge affiché', (tester) async {
      when(() => listMessages()).thenAnswer((_) async => Right([_message1]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byType(StatusPill), findsNothing);
    });
  });

  group('panneau « Équipe » (#5133, #6245)', () {
    testWidgets('desktop → liste le vrai roster praticiens du cabinet',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));
      when(() => listPractitioners()).thenAnswer((_) async => const Right([
            CabinetPractitioner(
              id: 'prac-lefevre',
              displayName: 'Dr Claire Lefèvre',
              specialite: 'Praticienne',
            ),
            CabinetPractitioner(
              id: 'prac-marin',
              displayName: 'Dr Hugo Marin',
            ),
          ]));

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
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      expect(find.byKey(const Key('team_member_prac-lefevre')), findsOneWidget);
      expect(find.text('Dr Claire Lefèvre'), findsOneWidget);
      expect(find.text('Praticienne'), findsOneWidget);

      expect(find.byKey(const Key('team_member_prac-marin')), findsOneWidget);
      expect(find.text('Dr Hugo Marin'), findsOneWidget);
      expect(find.text('Praticien'), findsOneWidget);
    });

    testWidgets(
        'desktop → présence dérivée de l\'agenda du jour (#7668)',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));
      when(() => listPractitioners()).thenAnswer((_) async => const Right([
            CabinetPractitioner(
              id: 'prac-lefevre',
              displayName: 'Dr Claire Lefèvre',
              specialite: 'Praticienne',
            ),
            CabinetPractitioner(
              id: 'prac-marin',
              displayName: 'Dr Hugo Marin',
            ),
          ]));
      final now = DateTime.now();
      when(() => getAgenda(any())).thenAnswer((_) async => Right([
            AgendaEntry(
              id: 'a1',
              cabinetId: 'c1',
              practitionerId: 'prac-lefevre',
              practitionerName: 'Dr Claire Lefèvre',
              startsAt: now.subtract(const Duration(minutes: 10)),
              endsAt: now.add(const Duration(minutes: 10)),
              isFree: false,
              status: 'confirmed',
            ),
          ]));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final lefevreRow = find.byKey(const Key('team_member_prac-lefevre'));
      expect(
        find.descendant(of: lefevreRow, matching: find.text('En consultation')),
        findsOneWidget,
      );

      final marinRow = find.byKey(const Key('team_member_prac-marin'));
      expect(
        find.descendant(of: marinRow, matching: find.text('Disponible')),
        findsOneWidget,
      );
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

  group('bloc épinglé (#5130)', () {
    final pinnedMessage = CabinetTeamMessage(
      id: 'm3',
      senderId: 'u1',
      senderName: 'Dr A. Rousseau',
      body: 'Fermeture exceptionnelle le vendredi 15 août. '
          'Ne pas placer de rendez-vous.',
      createdAt: DateTime(2026, 8, 2),
      pinned: true,
      pinnedBy: 'u1',
      pinnedAt: DateTime(2026, 8, 2),
    );

    testWidgets(
        'desktop → message épinglé affiché avec libellé, auteur et date',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([_message1, pinnedMessage]));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final notice = find.byKey(const Key('team_messages_pinned_notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.text('ÉPINGLÉ')),
        findsOneWidget,
      );
    });

    testWidgets('aucun message épinglé → pas de bloc affiché', (tester) async {
      when(() => listMessages()).thenAnswer((_) async => Right([_message1]));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('team_messages_pinned_notice')),
        findsNothing,
      );
    });
  });

  group('en-tête (#7668)', () {
    testWidgets('sous-titre « Fil du cabinet · réservé à l\'équipe » affiché',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.text("Fil du cabinet · réservé à l'équipe"),
        findsOneWidget,
      );
    });

    testWidgets('desktop → résumé du roster (avatars + « N membres »)',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));
      when(() => listPractitioners()).thenAnswer((_) async => const Right([
            CabinetPractitioner(
              id: 'prac-lefevre',
              displayName: 'Dr Claire Lefèvre',
              specialite: 'Praticienne',
            ),
            CabinetPractitioner(
              id: 'prac-marin',
              displayName: 'Dr Hugo Marin',
            ),
          ]));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('team_messages_roster_summary')),
        findsOneWidget,
      );
      expect(find.text('2 membres'), findsOneWidget);
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
  });

  group('mention d\'un membre (#5129)', () {
    final messageWithMention = CabinetTeamMessage(
      id: 'm5',
      senderId: 'u1',
      senderName: 'Dr Martin',
      body: '@Sarah tu peux la contacter ?',
      createdAt: DateTime(2026, 1, 1, 9, 30),
      mentions: const ['Sarah'],
    );

    testWidgets('mention @Nom dans le corps → stylée en pilule émeraude',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right([messageWithMention]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final mentionText = find.text('@Sarah');
      expect(mentionText, findsOneWidget);

      final mentionWidget = tester.widget<Text>(mentionText);
      expect(mentionWidget.style?.color, NubiaColors.brand800);
      expect(mentionWidget.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('composeur → bouton « Mentionner » avec icône alternate_email',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('team_message_mention_button'));
      expect(button, findsOneWidget);
      expect(find.text('Mentionner'), findsOneWidget);
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(Icons.alternate_email),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tap « Mentionner » → insère @ dans le composeur',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('team_message_mention_button')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key('team_message_input')),
        matching: find.byType(TextField),
      ));
      expect(field.controller!.text, '@');
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets(
        '« Mentionner » puis « Envoyer » sans destinataire → aucun envoi '
        '(#7738)', (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('team_message_mention_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('team_message_send_button')));
      await tester.pumpAndSettle();

      verifyNever(() => sendMessage(any()));
      final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key('team_message_input')),
        matching: find.byType(TextField),
      ));
      expect(field.controller!.text, '@');
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
    });

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
    });
  });

  group('séparateurs de jour (#5127)', () {
    testWidgets(
        'messages de jours différents → séparateur "Hier"/"Aujourd\'hui" '
        'devant le premier message de chaque jour', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageYesterday = CabinetTeamMessage(
        id: 'y1',
        senderId: 'u1',
        senderName: 'Dr Martin',
        body: 'Message d\'hier.',
        createdAt: yesterday,
      );
      final messageToday = CabinetTeamMessage(
        id: 't1',
        senderId: 'u1',
        senderName: 'Dr Martin',
        body: 'Message d\'aujourd\'hui.',
        createdAt: today,
      );
      when(() => listMessages())
          .thenAnswer((_) async => Right([messageYesterday, messageToday]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Hier'), findsOneWidget);
      expect(find.text("Aujourd'hui"), findsOneWidget);
      expect(find.byKey(const Key('team_message_y1')), findsOneWidget);
      expect(find.byKey(const Key('team_message_t1')), findsOneWidget);
    });
  });

  group('regroupement des messages consécutifs (#5126)', () {
    testWidgets(
        'même auteur, même jour → le second message n\'affiche ni nom ni '
        'heure, avatar masqué', (tester) async {
      final first = CabinetTeamMessage(
        id: 'g1',
        senderId: 'u1',
        senderName: 'Dr Amélie Rousseau',
        body: 'Parfait.',
        createdAt: DateTime(2026, 1, 1, 8, 20),
      );
      final continuation = CabinetTeamMessage(
        id: 'g2',
        senderId: 'u1',
        senderName: 'Dr Amélie Rousseau',
        body: 'Idéalement jeudi ou vendredi matin.',
        createdAt: DateTime(2026, 1, 1, 8, 21),
      );
      when(() => listMessages())
          .thenAnswer((_) async => Right([first, continuation]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.text('Idéalement jeudi ou vendredi matin.'), findsOneWidget);

      final continuationItem = find.byKey(const Key('team_message_g2'));
      expect(
        find.descendant(
          of: continuationItem,
          matching: find.text('Dr Amélie Rousseau'),
        ),
        findsNothing,
      );

      final avatarOpacity = tester.widget<Opacity>(find.descendant(
        of: continuationItem,
        matching: find.byType(Opacity),
      ));
      expect(avatarOpacity.opacity, 0);
    });

    testWidgets('auteur différent → en-tête complet réaffiché',
        (tester) async {
      final first = CabinetTeamMessage(
        id: 'g3',
        senderId: 'u1',
        senderName: 'Dr Amélie Rousseau',
        body: 'Parfait.',
        createdAt: DateTime(2026, 1, 1, 8, 20),
      );
      final other = CabinetTeamMessage(
        id: 'g4',
        senderId: 'u2',
        senderName: 'Sarah Lemoine',
        body: 'Message envoyé via la messagerie patient.',
        createdAt: DateTime(2026, 1, 1, 9, 4),
      );
      when(() => listMessages())
          .thenAnswer((_) async => Right([first, other]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.text('Sarah Lemoine'), findsOneWidget);
    });
  });

  group('ouverture sur le dernier message (#6922)', () {
    List<CabinetTeamMessage> longThread() => [
          for (var i = 0; i < 30; i++)
            CabinetTeamMessage(
              id: 'long$i',
              senderId: 'u1',
              senderName: 'Dr Martin',
              body: 'Message numéro $i du fil, assez long pour occuper '
                  'plusieurs lignes à l\'écran et forcer le défilement.',
              createdAt: DateTime(2026, 1, 1 + i, 9),
            ),
        ];

    testWidgets(
        'fil long → ouvert scrollé sur le dernier message, pas le plus ancien',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => Right(longThread()));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_message_long29')), findsOneWidget);
      expect(find.byKey(const Key('team_message_long0')), findsNothing);
    });

    testWidgets(
        'envoi d\'un message dans un fil long → visible sans défiler',
        (tester) async {
      final thread = longThread();
      var callCount = 0;
      when(() => listMessages()).thenAnswer((_) async {
        callCount++;
        return Right(callCount == 1
            ? thread
            : [
                ...thread,
                CabinetTeamMessage(
                  id: 'new-msg',
                  senderId: 'u1',
                  senderName: 'Dr Martin',
                  body: 'Dernier message qui vient d\'être envoyé.',
                  createdAt: DateTime(2026, 2, 1, 9),
                ),
              ]);
      });
      when(() => sendMessage(any()))
          .thenAnswer((_) async => const Right('new-msg'));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('team_message_input')),
        'Dernier message qui vient d\'être envoyé.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('team_message_send_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('team_message_new-msg')), findsOneWidget);
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

    testWidgets(
        'tap Ouvrir sur une référence patient → navigue vers la fiche patient',
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
        'composeur → bouton « Épingler » avec icône push_pin',
        (tester) async {
      when(() => listMessages())
          .thenAnswer((_) async => const Right(<CabinetTeamMessage>[]));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('team_message_pin_button'));
      expect(button, findsOneWidget);
      expect(find.text('Épingler'), findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.push_pin)),
        findsOneWidget,
      );
    });
  });
}
