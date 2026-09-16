// Issue #7045 — la carte « à votre décision » d'un plan de soins (et les
// autres appelants : détail de plan, notifications) poussent
// `/financial?id=<quoteId>` pour ouvrir DIRECTEMENT le devis ciblé, mais le
// builder de la route ignorait `state` et démarrait systématiquement
// `FinancialLoadRequested()` (liste complète, non filtrée). Ce test verrouille
// que `?id=` est bien lu et déclenche `FinancialQuoteSelected(id)`.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/financial/financial_bloc.dart';
import 'package:app_patient/features/financial/financial_event.dart';
import 'package:app_patient/features/financial/financial_state.dart';
import 'package:app_patient/router/app_router.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

class _MockFinancialBloc extends MockBloc<FinancialEvent, FinancialState>
    implements FinancialBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const FinancialLoadRequested());
  });

  late _MockFinancialBloc mockBloc;

  setUp(() async {
    mockBloc = _MockFinancialBloc();
    whenListen(
      mockBloc,
      const Stream<FinancialState>.empty(),
      initialState: const FinancialInitial(),
    );
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<FinancialBloc>(() => mockBloc);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets(
    '/financial?id=… déclenche FinancialQuoteSelected(id), pas le chargement de la liste complète',
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go('/financial?id=d2e04bfb-6fed-4e68-b513-c1ac36aeeaf5');

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      // Pas de pumpAndSettle : l'état initial/loading affiche un squelette
      // shimmer en boucle infinie (même contrainte que
      // mes_rdv_history_count_test.dart) — un simple pump suffit, `create()`
      // du BlocProvider (et donc `mockBloc.add`) s'exécute synchronement.
      await tester.pump();

      verify(
        () => mockBloc.add(
          const FinancialQuoteSelected('d2e04bfb-6fed-4e68-b513-c1ac36aeeaf5'),
        ),
      ).called(1);
      verifyNever(() => mockBloc.add(const FinancialLoadRequested()));
    },
  );

  testWidgets(
    '/financial sans id charge toujours la liste complète (comportement inchangé)',
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go('/financial');

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      // Pas de pumpAndSettle : l'état initial/loading affiche un squelette
      // shimmer en boucle infinie (même contrainte que
      // mes_rdv_history_count_test.dart) — un simple pump suffit, `create()`
      // du BlocProvider (et donc `mockBloc.add`) s'exécute synchronement.
      await tester.pump();

      verify(() => mockBloc.add(const FinancialLoadRequested())).called(1);
    },
  );
}
