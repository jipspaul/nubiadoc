import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_page.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';

class MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

// #5563/#5593 — le champ `beneficiary` de l'API (tuteur vs dépendant) doit
// être visible dans « Mes RDV », pas seulement parsé et jeté.
void main() {
  Future<void> pump(
    WidgetTester tester,
    List<Appointment> upcoming,
  ) async {
    final bloc = MockMesRdvBloc();
    whenListen(
      bloc,
      const Stream<MesRdvState>.empty(),
      initialState: MesRdvLoaded(upcoming: upcoming, history: const []),
    );

    GetIt.instance.registerFactory<MesRdvBloc>(() => bloc);
    addTearDown(() => GetIt.instance.reset());

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: MesRdvPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      '« Mes RDV » affiche le nom du bénéficiaire pour un RDV de dépendant',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.confirmed,
      beneficiaryIsSelf: false,
      beneficiaryName: 'QAFlow Dep',
    );

    await pump(tester, [appt]);

    expect(find.text('Pour QAFlow Dep'), findsOneWidget);
  });

  testWidgets(
      '« Mes RDV » n\'affiche aucun bénéficiaire pour un RDV pris par le tuteur pour lui-même',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-2',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.confirmed,
    );

    await pump(tester, [appt]);

    expect(find.textContaining('Pour '), findsNothing);
  });
}
