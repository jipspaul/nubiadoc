// Issue #6846 — QA-20260910-31 : depuis la recherche praticien
// (`/appointments`), ouvrir la feuille de détail d'un praticien puis
// déclencher un retour (navigateur ou in-app, équivalents sous go_router :
// les deux dépilent la même entrée de `RouteMatchList`) ne doit refermer que
// la feuille et laisser `/appointments` avec sa recherche intacte — pas
// éjecter du tunnel vers la route précédente. Déjà corrigé par #7803 (route
// dédiée `AppRouter.appointmentsProvider`, `NubiaBottomSheet.page`) : ce test
// verrouille le scénario exact du rapport QA pour éviter une régression.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';
import 'package:app_patient/router/app_router.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

const _provider = ProviderResult(
  id: 'prov-amelie',
  displayName: 'Dr Amélie Dubois',
  specialty: 'Omnipratique',
);

void main() {
  late _MockAppointmentsBloc mockBloc;

  setUp(() {
    mockBloc = _MockAppointmentsBloc();
    when(() => mockBloc.state).thenReturn(const AppointmentsInitial());
    when(() => mockBloc.stream).thenAnswer((_) => const Stream.empty());
    GetIt.instance.registerFactory<AppointmentsBloc>(() => mockBloc);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets(
    'retour depuis la feuille praticien referme la feuille et laisse '
    '/appointments avec sa recherche intacte, sans éjecter du tunnel',
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go(AppRouter.appointments);

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      router.push(AppRouter.appointmentsProvider, extra: _provider);
      await tester.pumpAndSettle();

      // `currentConfiguration.uri` ne reflète volontairement pas les
      // `ImperativeRouteMatch` (doc `RouteMatchList.uri`, go_router) — c'est
      // `routeInformationProvider.value.uri` qui porte l'URL réellement
      // publiée au navigateur (`optionURLReflectsImperativeAPIs`, #7095).
      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRouter.appointmentsProvider,
      );
      expect(find.byKey(const Key('sheet_provider_prov-amelie')), findsOneWidget);

      // Retour (navigateur ou in-app) : go_router dépile l'entrée
      // `appointmentsProvider` elle-même, pas `/appointments` en dessous.
      router.pop();
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRouter.appointments,
      );
      expect(find.byKey(const Key('sheet_provider_prov-amelie')), findsNothing);
      expect(find.byKey(const Key('search_field')), findsOneWidget);
    },
  );
}
