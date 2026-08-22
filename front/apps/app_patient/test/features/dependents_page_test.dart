import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/dependents/dependents_cubit.dart';
import 'package:app_patient/features/dependents/dependents_page.dart';
import 'package:app_patient/router/app_router.dart';

class MockDependentsCubit extends MockCubit<DependentsState>
    implements DependentsCubit {}

final _lucas = Dependent(
  id: 'dep-1',
  firstName: 'Lucas',
  lastName: 'Marchand',
  dateOfBirth: DateTime(2015, 3, 10),
  relationship: DependentRelationship.enfant,
);

// Enfant ayant dépassé la majorité — DOB fixée loin dans le passé pour que
// le test reste vrai indépendamment de la date d'exécution.
final _majeur = Dependent(
  id: 'dep-3',
  firstName: 'Alan',
  lastName: 'Roussel',
  dateOfBirth: DateTime(2000, 1, 1),
  relationship: DependentRelationship.enfant,
);

final _julie = PatientAccount(
  id: 'acc-1',
  firstName: 'Julie',
  lastName: 'Martin',
  email: 'julie.martin@email.fr',
  dateOfBirth: DateTime(1985, 3, 10),
);

final _pendingRequest = AccessRequest(
  id: 'ar-1',
  firstName: 'Émile',
  lastName: 'Martin',
  relationship: DependentRelationship.conjoint,
  status: AccessRequestStatus.envoyee,
  channel: AccessRequestChannel.email,
  sentAt: DateTime.now().subtract(const Duration(days: 1)),
);

Future<void> _pump(WidgetTester tester, DependentsCubit cubit) async {
  GetIt.instance.registerFactory<DependentsCubit>(() => cubit);
  addTearDown(() => GetIt.instance.reset());

  await tester.pumpWidget(
    MaterialApp(
      theme: NubiaTheme.light,
      // Requis par le DatePickerDialog du champ date de naissance (#5230).
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr')],
      home: const DependentsPage(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockDependentsCubit cubit;

  setUpAll(() {
    registerFallbackValue(DependentRelationship.enfant);
  });

  setUp(() {
    cubit = MockDependentsCubit();
    when(() => cubit.load()).thenAnswer((_) async {});
  });

  testWidgets(
      'carte compte géré : initiales, nom, lien+âge, actions et clé conservés',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas]),
    );

    await _pump(tester, cubit);

    expect(find.byKey(const Key('dependent_dep-1')), findsOneWidget);
    expect(find.text('LM'), findsOneWidget);
    expect(find.text('Lucas Marchand'), findsOneWidget);
    expect(find.text('Enfant · 11 ans'), findsOneWidget);
    expect(find.text('Prendre RDV'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.byIcon(Icons.event_available), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);

    // Aucune donnée RDV → la ligne "Prochain RDV" reste masquée.
    expect(find.textContaining('Prochain RDV'), findsNothing);
  });

  testWidgets(
      '« Prendre RDV » et « Documents » ouvrent bien les routes booking et '
      'documents (#5227)', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas]),
    );
    GetIt.instance.registerFactory<DependentsCubit>(() => cubit);
    addTearDown(() => GetIt.instance.reset());

    final router = GoRouter(
      initialLocation: AppRouter.profileDependents,
      routes: [
        GoRoute(
          path: AppRouter.profileDependents,
          builder: (_, __) => const DependentsPage(),
        ),
        GoRoute(
          path: AppRouter.book,
          builder: (_, __) => const Scaffold(key: Key('book_stub')),
        ),
        GoRoute(
          path: AppRouter.documents,
          builder: (_, __) => const Scaffold(key: Key('documents_stub')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('fr')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Prendre RDV'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book_stub')), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documents_stub')), findsOneWidget);
  });

  testWidgets('carte compte géré : ligne "Prochain RDV" si une donnée existe',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded(
        [_lucas],
        nextAppointmentByDependentId: {
          'dep-1': DateTime(2026, 8, 13, 16, 30), // jeudi
        },
      ),
    );

    await _pump(tester, cubit);

    expect(
      find.text('Prochain RDV jeudi 13 août, 16:30'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.event), findsOneWidget);
    expect(find.text('Voir'), findsOneWidget);
  });

  testWidgets(
      'carte compte géré : sans RDV à venir, affiche "Aucun rendez-vous à '
      'venir" avec un lien Planifier', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas]),
    );

    await _pump(tester, cubit);

    expect(find.text('Aucun rendez-vous à venir'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    expect(find.text('Planifier'), findsOneWidget);
  });

  testWidgets('carte compte géré : le lien Voir ouvre bien Mes RDV',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded(
        [_lucas],
        nextAppointmentByDependentId: {
          'dep-1': DateTime(2026, 8, 13, 16, 30), // jeudi
        },
      ),
    );
    GetIt.instance.registerFactory<DependentsCubit>(() => cubit);
    addTearDown(() => GetIt.instance.reset());

    final router = GoRouter(
      initialLocation: AppRouter.profileDependents,
      routes: [
        GoRoute(
          path: AppRouter.profileDependents,
          builder: (_, __) => const DependentsPage(),
        ),
        GoRoute(
          path: AppRouter.mesRdv,
          builder: (_, __) => const Scaffold(key: Key('mes_rdv_stub')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('fr')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Voir'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mes_rdv_stub')), findsOneWidget);
  });

  testWidgets('carte compte géré : le lien Planifier ouvre bien la prise de RDV',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas]),
    );
    GetIt.instance.registerFactory<DependentsCubit>(() => cubit);
    addTearDown(() => GetIt.instance.reset());

    final router = GoRouter(
      initialLocation: AppRouter.profileDependents,
      routes: [
        GoRoute(
          path: AppRouter.profileDependents,
          builder: (_, __) => const DependentsPage(),
        ),
        GoRoute(
          path: AppRouter.book,
          builder: (_, __) => const Scaffold(key: Key('book_stub')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('fr')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Planifier'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_stub')), findsOneWidget);
  });

  testWidgets(
      'suppression : dialogue de confirmation conserve le nom et la clé',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas]),
    );
    when(() => cubit.remove(any())).thenAnswer((_) async {});

    await _pump(tester, cubit);

    expect(find.byKey(const Key('delete_dependent_dep-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete_dependent_dep-1')));
    await tester.pumpAndSettle();

    expect(
      find.text('Lucas Marchand ne sera plus rattaché à votre compte.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retirer'));
    await tester.pumpAndSettle();

    verify(() => cubit.remove('dep-1')).called(1);
  });

  testWidgets(
      'carte titulaire : initiales, nom, sous-ligne et pastille en tête de '
      "liste, avant l'en-tête « Comptes que vous gérez »", (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas], account: _julie),
    );

    await _pump(tester, cubit);

    expect(find.byKey(const Key('self_account_card')), findsOneWidget);
    expect(find.text('JM'), findsOneWidget);
    expect(find.text('Julie Martin'), findsOneWidget);
    expect(find.text('Vous · 41 ans'), findsOneWidget);
    expect(find.text('Titulaire'), findsOneWidget);

    final cardTop =
        tester.getTopLeft(find.byKey(const Key('self_account_card'))).dy;
    final headerTop =
        tester.getTopLeft(find.text('COMPTES QUE VOUS GÉREZ')).dy;
    expect(cardTop, lessThan(headerTop));
  });

  testWidgets(
      "carte titulaire : absente si le titulaire n'est pas fourni par le "
      'cubit', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas]),
    );

    await _pump(tester, cubit);

    expect(find.byKey(const Key('self_account_card')), findsNothing);
  });

  testWidgets(
      'carte demande en attente : badge, canal/horodatage et actions',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded(
        const [],
        pendingAccessRequests: [_pendingRequest],
      ),
    );

    await _pump(tester, cubit);

    expect(find.byKey(const Key('pending_request_ar-1')), findsOneWidget);
    expect(find.text('Émile Martin'), findsOneWidget);
    expect(find.text('Conjoint'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('pending_request_ar-1')),
        matching: find.byIcon(Icons.schedule),
      ),
      findsOneWidget,
    );
    expect(find.text('Envoyée hier par email'), findsOneWidget);
    expect(find.byIcon(Icons.mail), findsOneWidget);
    expect(find.text('Relancer'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
  });

  testWidgets('carte demande en attente : Relancer appelle cubit.resend',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded(
        const [],
        pendingAccessRequests: [_pendingRequest],
      ),
    );
    when(() => cubit.resend(any())).thenAnswer((_) async {});

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('resend_access_request_ar-1')));
    await tester.pumpAndSettle();

    verify(() => cubit.resend('ar-1')).called(1);
  });

  testWidgets('carte demande en attente : Annuler appelle cubit.cancel',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded(
        const [],
        pendingAccessRequests: [_pendingRequest],
      ),
    );
    when(() => cubit.cancel(any())).thenAnswer((_) async {});

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('cancel_access_request_ar-1')));
    await tester.pumpAndSettle();

    verify(() => cubit.cancel('ar-1')).called(1);
  });

  testWidgets(
      "ajout proche : régime enfant n'affiche pas l'encart de réassurance",
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('invitation_reassurance_notice')),
      findsNothing,
    );
  });

  testWidgets(
      "ajout proche : régime enfant n'affiche pas l'encart "
      '"Pourquoi une demande ?"', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('why_request_notice')), findsNothing);
  });

  testWidgets(
      'ajout proche : régime invitation (conjoint/autre) affiche l\'encart '
      '"Pourquoi une demande ?" avec le texte exact', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conjoint').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('why_request_notice')), findsOneWidget);
    expect(find.text('Pourquoi une demande ?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('why_request_notice')),
        matching: find.byIcon(Icons.handshake),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Vous gérez un enfant mineur de plein droit. Pour un adulte, '
        'la loi exige ',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('son accord'), findsOneWidget);
    expect(
      find.textContaining(
        " : nous lui envoyons une demande qu'il peut accepter ou refuser.",
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'ajout proche : régime invitation (conjoint/autre) affiche l\'encart '
      'de réassurance avec le prénom saisi', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conjoint').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('invitation_reassurance_notice')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.shield), findsOneWidget);
    expect(
      find.textContaining(
        "choisira ce qu'il vous autorise, et pourra retirer cet accès "
        'à tout moment depuis son profil. Vous en serez informé.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Votre proche choisira'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('dependent_first_name')),
      'Émile',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Émile choisira'), findsOneWidget);
  });

  testWidgets(
      'ajout proche : régime enfant garde le libellé Ajouter, sans sous-titre',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('save_dependent_button')),
        matching: find.text('Ajouter'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Un adulte doit accepter votre demande'),
      findsNothing,
    );
  });

  testWidgets(
      'ajout proche : régime invitation affiche le CTA "Envoyer la demande" '
      'et le sous-titre, désactivé tant que l\'e-mail est invalide',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conjoint').last);
    await tester.pumpAndSettle();

    expect(find.text('Envoyer la demande'), findsOneWidget);
    expect(
      find.text('Un adulte doit accepter votre demande'),
      findsOneWidget,
    );

    final buttonNoEmail = tester
        .widget<NubiaButton>(find.byKey(const Key('save_dependent_button')));
    expect(buttonNoEmail.icon, Icons.send);
    expect(buttonNoEmail.onPressed, isNull);

    await tester.enterText(
        find.byKey(const Key('dependent_first_name')), 'Émile');
    await tester.enterText(
        find.byKey(const Key('dependent_last_name')), 'Martin');
    await tester.enterText(
        find.byKey(const Key('dependent_email')), 'pas-un-email');
    await tester.pumpAndSettle();

    final buttonInvalidEmail = tester
        .widget<NubiaButton>(find.byKey(const Key('save_dependent_button')));
    expect(buttonInvalidEmail.onPressed, isNull);

    await tester.enterText(
        find.byKey(const Key('dependent_email')), 'emile.martin@email.fr');
    await tester.pumpAndSettle();

    final buttonValid = tester
        .widget<NubiaButton>(find.byKey(const Key('save_dependent_button')));
    expect(buttonValid.onPressed, isNotNull);
  });

  testWidgets(
      "ajout proche : régime enfant n'affiche pas le bloc de périmètre "
      'proposé', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('proposed_scope_card')), findsNothing);
  });

  testWidgets(
      'ajout proche : régime invitation affiche le bloc de périmètre '
      'proposé avec les états initiaux attendus', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conjoint').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('proposed_scope_card')), findsOneWidget);
    expect(find.text('CE QUE VOUS POURREZ FAIRE'), findsOneWidget);

    expect(find.text('Ses rendez-vous'), findsOneWidget);
    expect(find.text('Voir, prendre, annuler'), findsOneWidget);
    expect(find.byIcon(Icons.event_available), findsOneWidget);

    expect(find.text('Ses documents'), findsOneWidget);
    expect(find.text('Ordonnances, devis, factures'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);

    expect(find.text('Ses messages avec le cabinet'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble), findsOneWidget);

    expect(
      tester
          .widget<NubiaToggle>(
            find.byKey(const Key('proposed_scope_toggle_appointments')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<NubiaToggle>(
            find.byKey(const Key('proposed_scope_toggle_documents')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<NubiaToggle>(
            find.byKey(const Key('proposed_scope_toggle_messages')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets(
      'ajout proche : changer de lien conserve le Prénom/Nom déjà saisis',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('dependent_first_name')), 'Lucas');
    await tester.enterText(
        find.byKey(const Key('dependent_last_name')), 'Marchand');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conjoint').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<NubiaTextField>(find.byKey(const Key('dependent_first_name')))
          .controller
          ?.text,
      'Lucas',
    );
    expect(
      tester
          .widget<NubiaTextField>(find.byKey(const Key('dependent_last_name')))
          .controller
          ?.text,
      'Marchand',
    );

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enfant').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<NubiaTextField>(find.byKey(const Key('dependent_first_name')))
          .controller
          ?.text,
      'Lucas',
    );
    expect(
      tester
          .widget<NubiaTextField>(find.byKey(const Key('dependent_last_name')))
          .controller
          ?.text,
      'Marchand',
    );
  });

  testWidgets('ajout proche : bascule un toggle du périmètre proposé',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conjoint').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('proposed_scope_toggle_messages')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('proposed_scope_toggle_messages')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<NubiaToggle>(
            find.byKey(const Key('proposed_scope_toggle_messages')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets(
      'carte compte géré : bandeau majorité visible si au moins un enfant',
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_lucas]),
    );

    await _pump(tester, cubit);

    expect(find.byKey(const Key('majority_notice')), findsOneWidget);
    expect(
      find.textContaining(
        "À sa majorité, votre enfant reprendra son propre accès",
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      "carte compte géré : pas de bandeau majorité sans proche « enfant »",
      (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    expect(find.byKey(const Key('majority_notice')), findsNothing);
  });

  testWidgets(
      'carte compte géré : un enfant devenu majeur perd les actions '
      'RDV/Documents au profit du message de fin d\'accès', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: DependentsLoaded([_majeur]),
    );

    await _pump(tester, cubit);

    expect(find.byKey(const Key('parental_access_expired_pill')),
        findsOneWidget);
    expect(find.text('Majorité atteinte'), findsOneWidget);
    expect(find.byKey(const Key('parental_access_expired_notice')),
        findsOneWidget);
    expect(
      find.textContaining("Alan a atteint sa majorité"),
      findsOneWidget,
    );
    expect(find.text('Prendre RDV'), findsNothing);
    expect(find.text('Documents'), findsNothing);
    // Le retrait du compte reste possible (nettoyage de la liste côté front).
    expect(find.byKey(const Key('delete_dependent_dep-3')), findsOneWidget);
  });

  testWidgets(
      'ajout proche : régime enfant affiche un champ date de naissance, '
      'requis pour activer le bouton et transmis à cubit.add', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );
    when(() => cubit.add(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          birthDate: any(named: 'birthDate'),
          relationship: any(named: 'relationship'),
        )).thenAnswer((_) async {});

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dependent_date_of_birth')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('dependent_first_name')), 'Lucas');
    await tester.enterText(
        find.byKey(const Key('dependent_last_name')), 'Marchand');
    await tester.pumpAndSettle();

    // Prénom/nom seuls, sans date de naissance : le bouton reste désactivé.
    expect(
      tester
          .widget<NubiaButton>(find.byKey(const Key('save_dependent_button')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('dependent_date_of_birth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<NubiaButton>(find.byKey(const Key('save_dependent_button')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('save_dependent_button')));
    await tester.pumpAndSettle();

    final captured = verify(() => cubit.add(
          firstName: 'Lucas',
          lastName: 'Marchand',
          birthDate: captureAny(named: 'birthDate'),
          relationship: DependentRelationship.enfant,
        )).captured;
    expect(captured.single, isNotNull);
  });

  testWidgets(
      "ajout proche : le champ date de naissance disparaît en régime "
      'invitation (conjoint/autre)', (tester) async {
    whenListen(
      cubit,
      const Stream<DependentsState>.empty(),
      initialState: const DependentsLoaded([]),
    );

    await _pump(tester, cubit);

    await tester.tap(find.byKey(const Key('add_dependent_fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dependent_relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conjoint').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dependent_date_of_birth')), findsNothing);
  });
}
