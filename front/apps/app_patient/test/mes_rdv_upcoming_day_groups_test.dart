// Issue #5262 — l'onglet « À venir » doit regrouper les cartes par jour sous
// des en-têtes collants : « Aujourd'hui » en brand700 pour le jour courant,
// puis le libellé de date pour les jours suivants (ex. « Jeudi 13 août »).
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

const _weekdays = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _dayLabel(DateTime date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';

void main() {
  setUpAll(() {
    registerFallbackValue(const MesRdvLoadRequested());
  });

  Appointment apptAt(String id, DateTime startsAt) => Appointment(
        id: id,
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire $id',
        practitionerSpecialty: 'Dentiste',
        startsAt: startsAt,
        duration: const Duration(minutes: 30),
        motif: 'Contrôle',
        status: AppointmentStatus.confirmed,
      );

  late _MockMesRdvBloc mockBloc;

  setUp(() async {
    mockBloc = _MockMesRdvBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<MesRdvBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets(
      'les RDV à venir sont regroupés par jour, "Aujourd\'hui" en tête en brand700',
      (tester) async {
    final now = DateTime.now();
    final today9h = DateTime(now.year, now.month, now.day, 9);
    final today = today9h.isAfter(now)
        ? today9h
        : DateTime(now.year, now.month, now.day, 23, 59);
    final later = now.add(const Duration(days: 10));
    final laterLabel = _dayLabel(later);

    final upcoming = [
      apptAt('rdv-today', today),
      apptAt('rdv-later', later),
    ];
    final state = MesRdvLoaded(upcoming: upcoming, history: const []);
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

    expect(find.byKey(const Key('upcoming_list')), findsOneWidget);
    expect(find.text('Aujourd\'hui'), findsOneWidget);
    expect(find.text(laterLabel), findsOneWidget);

    final todayHeader = tester.widget<Text>(find.text('Aujourd\'hui'));
    expect(
      todayHeader.style?.color,
      NubiaColors.brand700,
      reason: 'le jour courant doit afficher "Aujourd\'hui" en brand700',
    );

    final todayTop = tester.getTopLeft(find.text('Aujourd\'hui')).dy;
    final laterTop = tester.getTopLeft(find.text(laterLabel)).dy;
    expect(todayTop, lessThan(laterTop),
        reason: 'le groupe du jour courant doit précéder les jours suivants');
  });
}
