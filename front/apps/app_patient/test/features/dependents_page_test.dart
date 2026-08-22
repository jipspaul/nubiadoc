import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/dependents/dependents_cubit.dart';
import 'package:app_patient/features/dependents/dependents_page.dart';

class MockDependentsCubit extends MockCubit<DependentsState>
    implements DependentsCubit {}

final _lucas = Dependent(
  id: 'dep-1',
  firstName: 'Lucas',
  lastName: 'Marchand',
  dateOfBirth: DateTime(2015, 3, 10),
  relationship: DependentRelationship.enfant,
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
      home: const DependentsPage(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockDependentsCubit cubit;

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
}
