//! #5580 : la recherche globale (⌘K, #5389) doit interroger patients ET
//! devis sur le même terme, fusionner les deux dans une liste unique
//! étiquetée par type, et permettre de naviguer vers le devis correspondant.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
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
  quoteRef: 'quote-marc',
  cabinetId: 'cab-1',
  patientId: 'pat-marc',
  patientName: 'Marc Dubois',
  totalCents: 12000,
  patientShareCents: 4000,
  status: CabinetQuoteStatus.sent,
  createdAt: DateTime(2026, 2, 1),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    key: const Key('open_global_search'),
                    onPressed: () => openGlobalSearchDialog(context),
                    child: const Text('Rechercher'),
                  ),
                  ElevatedButton(
                    key: const Key('open_global_search_with_destinations'),
                    onPressed: () => openGlobalSearchDialog(
                      context,
                      destinations: _testDestinations,
                    ),
                    child: const Text('Rechercher (⌘K)'),
                  ),
                ],
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

  testWidgets(
    '#5143 : la palette liste les destinations de nav et taper les filtre '
    'par libellé',
    (tester) async {
      when(() => listPatients(q: 'Agenda'))
          .thenAnswer((_) async => Right([]));
      when(() => listQuotes()).thenAnswer((_) async => Right([]));

      await tester.pumpWidget(_harness(_buildRouter()));
      await tester.tap(
        find.byKey(const Key('open_global_search_with_destinations')),
      );
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
      expect(
        find.descendant(of: destinationsList, matching: find.text('Agenda')),
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
    },
  );

  testWidgets(
    '#5143 : cliquer une destination filtrée ferme la palette et navigue '
    'vers sa route',
    (tester) async {
      when(() => listPatients(q: 'Agenda'))
          .thenAnswer((_) async => Right([]));
      when(() => listQuotes()).thenAnswer((_) async => Right([]));

      await tester.pumpWidget(_harness(_buildRouter()));
      await tester.tap(
        find.byKey(const Key('open_global_search_with_destinations')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Agenda');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Agenda'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_dialog')), findsNothing);
      expect(find.text('agenda page'), findsOneWidget);
    },
  );

  testWidgets(
    '#5143 : ↓ puis Entrée navigue vers une destination sans souris ni '
    'saisie',
    (tester) async {
      await tester.pumpWidget(_harness(_buildRouter()));
      await tester.tap(
        find.byKey(const Key('open_global_search_with_destinations')),
      );
      await tester.pumpAndSettle();

      // Liste complète visible sans avoir tapé : ↓ déplace la sélection de
      // « Tableau de bord » (1re entrée) vers « Agenda » (2e), Entrée y
      // navigue — aucun clic ni frappe de texte.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_dialog')), findsNothing);
      expect(find.text('agenda page'), findsOneWidget);
    },
  );
}
