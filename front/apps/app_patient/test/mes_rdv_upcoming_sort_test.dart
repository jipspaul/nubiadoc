// Régression #3801 — l'onglet « À venir » listait le RDV le plus LOINTAIN
// en premier (état de tri unique partagé avec l'historique, par défaut
// DESC). Le prochain RDV doit apparaître en tête. Rend la vraie
// MesRdvPage (bloc via GetIt, comme en prod) — pas une reproduction
// locale de la logique de tri.
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

  final soon = Appointment(
    id: 'rdv-soon',
    cabinetId: 'cab-1',
    practitionerName: 'Dr Proche',
    practitionerSpecialty: 'Dentiste',
    startsAt: DateTime.now().add(const Duration(days: 1)),
    duration: const Duration(minutes: 30),
    motif: 'Contrôle',
    status: AppointmentStatus.confirmed,
  );
  final far = Appointment(
    id: 'rdv-far',
    cabinetId: 'cab-1',
    practitionerName: 'Dr Lointain',
    practitionerSpecialty: 'Dentiste',
    startsAt: DateTime.now().add(const Duration(days: 90)),
    duration: const Duration(minutes: 30),
    motif: 'Détartrage',
    status: AppointmentStatus.confirmed,
  );

  late _MockMesRdvBloc mockBloc;

  setUp(() async {
    mockBloc = _MockMesRdvBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<MesRdvBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets('À venir affiche le RDV le plus proche en premier par défaut',
      (tester) async {
    // upcoming inséré dans le désordre (far avant soon) : la page doit
    // trier, pas se contenter de l'ordre reçu.
    final state = MesRdvLoaded(upcoming: [far, soon], history: const []);
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

    final ySoon = tester.getTopLeft(find.text('Dr Proche')).dy;
    final yFar = tester.getTopLeft(find.text('Dr Lointain')).dy;
    expect(
      ySoon,
      lessThan(yFar),
      reason: 'le prochain RDV (Dr Proche) doit être au-dessus du plus '
          'lointain (Dr Lointain) — l\'utilisateur ne doit pas avoir à '
          'scroller pour voir son prochain rendez-vous',
    );
  });
}
