//! #6311 : la recherche globale (⌘K/Ctrl+K) doit interroger les patients et
//! filtrer les destinations de nav sur le même terme.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/shell/widgets/global_search_dialog.dart';

class _MockListCabinetPatients extends Mock
    implements ListCabinetPatientsUseCase {}

final _patient = CabinetPatient(
  id: 'pat-marc',
  cabinetId: 'cab-1',
  firstName: 'Marc',
  lastName: 'Dubois',
  createdAt: DateTime(2026, 1, 1),
);

const _testDestinations = [
  ProNavDestination(
    label: 'Tableau de bord',
    icon: Icons.dashboard_outlined,
    route: '/',
  ),
  ProNavDestination(
    label: 'Agenda',
    icon: Icons.calendar_month_outlined,
    route: '/agenda',
  ),
];

Widget _harness(GoRouter router) =>
    MaterialApp.router(theme: NubiaTheme.light, routerConfig: router);

GoRouter _buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open_global_search'),
                onPressed: () => openGlobalSearchDialog(
                  context,
                  destinations: _testDestinations,
                ),
                child: const Text('Rechercher (⌘K)'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/agenda',
          builder: (_, __) => const Scaffold(body: Text('agenda page')),
        ),
        GoRoute(
          path: '/patients',
          builder: (_, state) =>
              Scaffold(body: Text('patients page ${state.extra ?? ''}')),
        ),
      ],
    );

void main() {
  late _MockListCabinetPatients listPatients;

  setUp(() {
    listPatients = _MockListCabinetPatients();
    GetIt.instance
        .registerFactory<ListCabinetPatientsUseCase>(() => listPatients);
    addTearDown(GetIt.instance.reset);
  });

  testWidgets(
    'un terme qui matche un patient affiche son résultat, étiqueté « Patient »',
    (tester) async {
      when(() => listPatients(q: 'Marc'))
          .thenAnswer((_) async => Right([_patient]));

      await tester.pumpWidget(_harness(_buildRouter()));
      await tester.tap(find.byKey(const Key('open_global_search')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Marc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final resultsList = find.byKey(const Key('global_search_results'));
      expect(resultsList, findsOneWidget);
      expect(
        find.descendant(
          of: resultsList,
          matching: find.widgetWithText(ListTile, 'Marc Dubois'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: resultsList, matching: find.text('Patient')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'taper sur un résultat patient ferme le dialogue et navigue vers sa fiche',
    (tester) async {
      when(() => listPatients(q: 'Marc'))
          .thenAnswer((_) async => Right([_patient]));

      await tester.pumpWidget(_harness(_buildRouter()));
      await tester.tap(find.byKey(const Key('open_global_search')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Marc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Marc Dubois'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_dialog')), findsNothing);
      expect(find.text('patients page pat-marc'), findsOneWidget);
    },
  );

  testWidgets(
    'la palette liste les destinations de nav et taper les filtre par libellé',
    (tester) async {
      when(() => listPatients(q: 'Agenda'))
          .thenAnswer((_) async => Right([]));

      await tester.pumpWidget(_harness(_buildRouter()));
      await tester.tap(find.byKey(const Key('open_global_search')));
      await tester.pumpAndSettle();

      final destinationsList =
          find.byKey(const Key('global_search_destinations'));
      expect(
        find.descendant(
          of: destinationsList,
          matching: find.text('Tableau de bord'),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'Agenda');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: destinationsList,
          matching: find.text('Tableau de bord'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: destinationsList, matching: find.text('Agenda')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ListTile, 'Agenda'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_dialog')), findsNothing);
      expect(find.text('agenda page'), findsOneWidget);
    },
  );
}
