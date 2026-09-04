// Issue #6375 — QA-20260903-47 : l'affordance « Modifier » (edit_calendar)
// doit être joignable depuis le menu « Plus d'actions » d'une carte « À
// venir », et pousser vers `AppRouter.modifyRdv` (#3804/#5264). Absente en
// pratique uniquement quand `Appointment.canModify` est faux (RDV à moins de
// 24h ou statut non requested/confirmed) — cf. `appointment.dart`.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_page.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';

class _MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const MesRdvLoadRequested());
  });

  late _MockMesRdvBloc mockBloc;

  setUp(() async {
    mockBloc = _MockMesRdvBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<MesRdvBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  Appointment appointment({
    required DateTime startsAt,
    AppointmentStatus status = AppointmentStatus.requested,
  }) =>
      Appointment(
        id: 'rdv-1',
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        startsAt: startsAt,
        duration: const Duration(minutes: 30),
        motif: 'Détartrage',
        status: status,
      );

  Future<GoRouter> pump(WidgetTester tester, Appointment appt) async {
    final state = MesRdvLoaded(upcoming: [appt], history: const []);
    whenListen(
      mockBloc,
      Stream<MesRdvState>.fromIterable([state]).asBroadcastStream(),
      initialState: state,
    );

    final router = GoRouter(
      initialLocation: '/mes-rdv',
      routes: [
        GoRoute(path: '/mes-rdv', builder: (_, __) => const MesRdvPage()),
        GoRoute(
          path: '/rdv/:id/modifier',
          builder: (_, state) => Scaffold(
            body: Text('modify-screen-${state.pathParameters['id']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets(
      'RDV requested à plus de 24h : le menu "Plus d\'actions" propose '
      '"Modifier" et pousse vers /rdv/:id/modifier', (tester) async {
    final appt = appointment(
      startsAt: DateTime.now().add(const Duration(days: 5)),
    );
    await pump(tester, appt);

    await tester.tap(find.byKey(const Key('more_actions_rdv-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modify_rdv-1')), findsOneWidget);
    expect(find.text('Modifier'), findsOneWidget);

    await tester.tap(find.byKey(const Key('modify_rdv-1')));
    await tester.pumpAndSettle();

    expect(find.text('modify-screen-rdv-1'), findsOneWidget);
  });

  testWidgets(
      'RDV à moins de 24h : "Modifier" est absent du menu (garde 24h, '
      'cf. reschedule_appointment côté API)', (tester) async {
    final appt = appointment(
      startsAt: DateTime.now().add(const Duration(hours: 10)),
    );
    await pump(tester, appt);

    await tester.tap(find.byKey(const Key('more_actions_rdv-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modify_rdv-1')), findsNothing);
  });
}
