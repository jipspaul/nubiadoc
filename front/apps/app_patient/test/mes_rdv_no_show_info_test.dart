// Issue #5272 — une carte historique au statut « Absent » (noShow) doit
// expliquer la non-présentation et le frais éventuel (jamais en dur, issu
// des données du RDV).
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

  Future<void> pump(WidgetTester tester, Appointment appt) async {
    final state = MesRdvLoaded(upcoming: const [], history: [appt]);
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

    // Onglet Historique.
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'un RDV noShow avec frais affiche « Non présenté — facturé 30 € selon la charte du cabinet »',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.noShow,
      noShowFeeCents: 3000,
    );

    await pump(tester, appt);

    expect(
      find.text(
        'Non présenté — facturé 30 € selon la charte du cabinet',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.info), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
  });

  testWidgets(
      'un RDV noShow sans frais connu affiche seulement « Non présenté »',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-2',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.noShow,
    );

    await pump(tester, appt);

    expect(find.text('Non présenté'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('un RDV confirmé ne montre pas la ligne « Non présenté »',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-3',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.completed,
    );

    await pump(tester, appt);

    expect(find.textContaining('Non présenté'), findsNothing);
  });
}
