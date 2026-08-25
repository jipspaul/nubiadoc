// Issue #5270 — un RDV historique `completed` facturé doit proposer une
// action « Facture · <montant> » en plus de « Reprendre RDV » (#5269),
// jamais de montant inventé.
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
      'un RDV completed facturé affiche « Facture · 148,50 € » avec icône receipt_long',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Traitement de carie',
      status: AppointmentStatus.completed,
      invoiceAmountCents: 14850,
    );

    await pump(tester, appt);

    expect(find.text('Facture · 148,50 €'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    // #5269 : « Reprendre RDV » reste affiché en plus de la facture, comme
    // sur toute carte historique.
    expect(find.text('Reprendre RDV'), findsOneWidget);
  });

  testWidgets(
      'un RDV completed sans facture connue replie sur « Reprendre RDV »',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-2',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Traitement de carie',
      status: AppointmentStatus.completed,
    );

    await pump(tester, appt);

    expect(find.text('Reprendre RDV'), findsOneWidget);
    expect(find.textContaining('Facture'), findsNothing);
  });

  testWidgets(
      'un RDV noShow ne montre pas de facture mais montre « Reprendre RDV » (#5269)',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-3',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Traitement de carie',
      status: AppointmentStatus.noShow,
    );

    await pump(tester, appt);

    expect(find.textContaining('Facture'), findsNothing);
    expect(find.text('Reprendre RDV'), findsOneWidget);
  });
}
