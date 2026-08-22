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
  // #5261 : l'avatar d'initiales n'est plus affiché sur une carte « à venir »
  // (remplacé par le rail de date) — il subsiste sur l'historique, d'où un
  // RDV passé ici.
  testWidgets('avatar « Mes RDV » : « Dr Amélie Dubois » → initiales « AD »',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Amélie Dubois',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.completed,
    );

    final bloc = MockMesRdvBloc();
    whenListen(
      bloc,
      const Stream<MesRdvState>.empty(),
      initialState: MesRdvLoaded(upcoming: const [], history: [appt]),
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

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();

    expect(find.text('AD'), findsOneWidget);
    expect(find.text('DD'), findsNothing);
  });
}
