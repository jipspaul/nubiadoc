// Issue #5267 — l'onglet « Historique » doit regrouper les cartes par mois
// sous des en-têtes (« Juillet 2026 », « Juin 2026 »), l'ordre des groupes
// suivant le tri historique (#3801, DESC par défaut).
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

  Appointment apptAt(String id, DateTime startsAt) => Appointment(
        id: id,
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        startsAt: startsAt,
        duration: const Duration(minutes: 30),
        motif: 'Contrôle',
        status: AppointmentStatus.completed,
      );

  testWidgets(
      'les RDV passés sont regroupés par mois, DESC (le plus récent en tête)',
      (tester) async {
    final history = [
      apptAt('rdv-jul-1', DateTime(2026, 7, 10, 9)),
      apptAt('rdv-jul-2', DateTime(2026, 7, 3, 9)),
      apptAt('rdv-jun-1', DateTime(2026, 6, 15, 9)),
    ];
    final state = MesRdvLoaded(upcoming: const [], history: history);
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

    expect(find.byKey(const Key('history_list')), findsOneWidget);
    expect(find.text('JUILLET 2026'), findsOneWidget);
    expect(find.text('JUIN 2026'), findsOneWidget);

    final julyTop = tester.getTopLeft(find.text('JUILLET 2026')).dy;
    final juneTop = tester.getTopLeft(find.text('JUIN 2026')).dy;
    expect(julyTop, lessThan(juneTop),
        reason: 'juillet (plus récent) doit précéder juin — DESC par défaut');
  });
}
