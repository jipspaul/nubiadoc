import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';
import 'package:app_patient/router/app_router.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

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

  // Régression #7920 : `/appointments/provider` porte `extra` (le praticien
  // déjà résolu) uniquement dans l'historique en mémoire — un F5, un lien
  // partagé ou une restauration d'onglet arrivent sur cette route sans lui.
  // Avant le fix, le pageBuilder retombait alors sur SizedBox.shrink() DANS
  // la feuille modale : un voile gris plein écran sans aucun contrôle.
  testWidgets(
    'atteindre /appointments/provider sans praticien résolu (F5/lien direct) '
    'redirige vers l\'annuaire au lieu d\'un voile gris sans issue',
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go(AppRouter.appointmentsProvider);

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prendre un rendez-vous'), findsOneWidget);
    },
  );
}
