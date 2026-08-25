// Issue #5271 — une carte historique terminée doit afficher les chips de
// synthèse documentaire (compte-rendu / ordonnance(s)) uniquement quand le
// document correspondant existe, et jamais sur l'onglet « À venir ».
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
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

  Appointment historyAppointment({
    bool hasReport = false,
    int prescriptionCount = 0,
  }) =>
      Appointment(
        id: 'rdv-1',
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime.now().subtract(const Duration(days: 2)),
        duration: const Duration(minutes: 30),
        motif: 'Traitement de carie',
        status: AppointmentStatus.completed,
        hasReport: hasReport,
        prescriptionCount: prescriptionCount,
      );

  Future<void> pump(
    WidgetTester tester, {
    required List<Appointment> upcoming,
    required List<Appointment> history,
  }) async {
    final state = MesRdvLoaded(upcoming: upcoming, history: history);
    whenListen(
      mockBloc,
      Stream<MesRdvState>.fromIterable([state]).asBroadcastStream(),
      initialState: state,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: MesRdvPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'un RDV terminé avec compte-rendu et 1 ordonnance affiche les deux chips',
      (tester) async {
    await pump(
      tester,
      upcoming: const [],
      history: [
        historyAppointment(hasReport: true, prescriptionCount: 1),
      ],
    );

    expect(find.text('Compte-rendu'), findsOneWidget);
    expect(find.byIcon(Icons.description), findsOneWidget);
    expect(find.text('1 ordonnance'), findsOneWidget);
    expect(find.byIcon(Icons.medication), findsOneWidget);
  });

  testWidgets('plusieurs ordonnances affichent le pluriel explicite',
      (tester) async {
    await pump(
      tester,
      upcoming: const [],
      history: [
        historyAppointment(prescriptionCount: 3),
      ],
    );

    expect(find.text('3 ordonnances'), findsOneWidget);
    expect(find.text('Compte-rendu'), findsNothing);
  });

  testWidgets('aucun document disponible : aucune chip affichée',
      (tester) async {
    await pump(
      tester,
      upcoming: const [],
      history: [historyAppointment()],
    );

    expect(find.text('Compte-rendu'), findsNothing);
    expect(find.byIcon(Icons.medication), findsNothing);
  });

  testWidgets('un RDV à venir ne montre jamais les chips (même avec doc)',
      (tester) async {
    final upcomingAppt = Appointment(
      id: 'rdv-upcoming',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: AppointmentStatus.confirmed,
      hasReport: true,
      prescriptionCount: 2,
    );

    await pump(
      tester,
      upcoming: [upcomingAppt],
      history: const [],
    );

    await tester.tap(find.text('À venir'));
    await tester.pumpAndSettle();

    expect(find.text('Compte-rendu'), findsNothing);
    expect(find.textContaining('ordonnance'), findsNothing);
  });
}
