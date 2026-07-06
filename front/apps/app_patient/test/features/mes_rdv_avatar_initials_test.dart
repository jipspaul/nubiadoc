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

void main() {
  // #3419 — les initiales de l'avatar « Mes RDV » ne doivent pas inclure le
  // préfixe de civilité : « Dr Amélie Dubois » → « AD » (et non « DD »).
  testWidgets('avatar « Mes RDV » : « Dr Amélie Dubois » → initiales « AD »',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Amélie Dubois',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.confirmed,
    );

    final bloc = MockMesRdvBloc();
    whenListen(
      bloc,
      const Stream<MesRdvState>.empty(),
      initialState: MesRdvLoaded(upcoming: [appt], history: const []),
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

    expect(find.text('AD'), findsOneWidget);
    expect(find.text('DD'), findsNothing);
  });
}
