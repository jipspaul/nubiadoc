//! #5580 : la recherche globale (⌘K, #5389) doit interroger patients ET
//! devis sur le même terme, fusionner les deux dans une liste unique
//! étiquetée par type, et permettre de naviguer vers le devis correspondant.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/widgets/global_search_dialog.dart';

class _MockListCabinetPatients extends Mock
    implements ListCabinetPatientsUseCase {}

class _MockListCabinetQuotes extends Mock implements ListCabinetQuotesUseCase {}

final _patient = CabinetPatient(
  id: 'pat-marc',
  cabinetId: 'cab-1',
  firstName: 'Marc',
  lastName: 'Dubois',
  createdAt: DateTime(2026, 1, 1),
);

final _quote = CabinetQuote(
  id: 'quote-marc',
  cabinetId: 'cab-1',
  patientId: 'pat-marc',
  patientName: 'Marc Dubois',
  totalCents: 12000,
  patientShareCents: 4000,
  status: CabinetQuoteStatus.sent,
  createdAt: DateTime(2026, 2, 1),
);

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
                onPressed: () => openGlobalSearchDialog(context),
                child: const Text('Rechercher'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/patients',
          builder: (_, state) =>
              Scaffold(body: Text('patients page ${state.extra ?? ''}')),
        ),
        GoRoute(
          path: '/devis/:id',
          builder: (context, state) => Scaffold(
            body: Text('devis page ${state.pathParameters['id']}'),
          ),
        ),
      ],
    );

void main() {
  late _MockListCabinetPatients listPatients;
  late _MockListCabinetQuotes listQuotes;

  setUp(() {
    listPatients = _MockListCabinetPatients();
    listQuotes = _MockListCabinetQuotes();
    GetIt.instance
        .registerFactory<ListCabinetPatientsUseCase>(() => listPatients);
    GetIt.instance.registerFactory<ListCabinetQuotesUseCase>(() => listQuotes);
    addTearDown(GetIt.instance.reset);
  });

  Future<void> openDialogAndSearch(WidgetTester tester, String term) async {
    await tester.pumpWidget(_harness(_buildRouter()));
    await tester.tap(find.byKey(const Key('open_global_search')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), term);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets(
    '#5580 : un terme qui matche un patient ET un devis affiche les deux, '
    'étiquetés par type',
    (tester) async {
      when(() => listPatients(q: 'Marc'))
          .thenAnswer((_) async => Right([_patient]));
      when(() => listQuotes()).thenAnswer((_) async => Right([_quote]));

      await openDialogAndSearch(tester, 'Marc');

      final resultsList = find.byKey(const Key('global_search_results'));
      expect(resultsList, findsOneWidget);
      expect(
        find.descendant(
          of: resultsList,
          matching: find.widgetWithText(ListTile, 'Marc Dubois'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: resultsList, matching: find.text('Patient')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: resultsList, matching: find.text('Devis')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '#5580 : taper sur un résultat devis ferme le dialogue et navigue vers '
    'sa fiche détail',
    (tester) async {
      when(() => listPatients(q: 'Marc')).thenAnswer((_) async => Right([]));
      when(() => listQuotes()).thenAnswer((_) async => Right([_quote]));

      await openDialogAndSearch(tester, 'Marc');

      await tester.tap(find.widgetWithText(ListTile, 'Marc Dubois'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_dialog')), findsNothing);
      expect(find.text('devis page quote-marc'), findsOneWidget);
    },
  );

  testWidgets(
    '#5579 : taper sur un résultat patient ferme le dialogue et navigue '
    'vers sa fiche détail',
    (tester) async {
      when(() => listPatients(q: 'Marc'))
          .thenAnswer((_) async => Right([_patient]));
      when(() => listQuotes()).thenAnswer((_) async => Right([]));

      await openDialogAndSearch(tester, 'Marc');

      await tester.tap(find.widgetWithText(ListTile, 'Marc Dubois'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_dialog')), findsNothing);
      expect(find.text('patients page pat-marc'), findsOneWidget);
    },
  );

  testWidgets(
    '#5579 : taper un terme sans valider déclenche une recherche après '
    '~300ms (debounce), sans attendre Entrée',
    (tester) async {
      when(() => listPatients(q: 'Marc'))
          .thenAnswer((_) async => Right([_patient]));
      when(() => listQuotes()).thenAnswer((_) async => Right([]));

      await tester.pumpWidget(_harness(_buildRouter()));
      await tester.tap(find.byKey(const Key('open_global_search')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Marc');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_results')), findsOneWidget);
      verify(() => listPatients(q: 'Marc')).called(1);
    },
  );
}
