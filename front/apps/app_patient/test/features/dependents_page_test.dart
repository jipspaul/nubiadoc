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
}
