// Issue #5268 — traitement visuel « passé » d'une carte de l'historique :
// fond légèrement retiré (`#FCFCFB`) et rail de date neutralisé (`n500`,
// plus aucun brand), contrairement à une carte « à venir » (fond blanc,
// rail `brand`).
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

  final pastAppt = Appointment(
    id: 'rdv-past',
    cabinetId: 'cab-1',
    practitionerName: 'Dr Lemaire',
    practitionerSpecialty: 'Dentiste',
    startsAt: DateTime.now().subtract(const Duration(days: 2)),
    duration: const Duration(minutes: 30),
    motif: 'Traitement de carie',
    status: AppointmentStatus.completed,
  );

  final upcomingAppt = Appointment(
    id: 'rdv-upcoming',
    cabinetId: 'cab-1',
    practitionerName: 'Dr Lemaire',
    practitionerSpecialty: 'Dentiste',
    startsAt: DateTime.now().add(const Duration(days: 2)),
    duration: const Duration(minutes: 30),
    motif: 'Contrôle annuel',
    status: AppointmentStatus.confirmed,
  );

  Future<void> pump(WidgetTester tester) async {
    final state = MesRdvLoaded(upcoming: [upcomingAppt], history: [pastAppt]);
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
  }

  testWidgets(
      'une carte à venir garde le fond blanc et un rail brand',
      (tester) async {
    await pump(tester);

    final card = tester.widget<NubiaCard>(find.byType(NubiaCard).first);
    expect(card.backgroundColor, isNull);

    final dateRow = tester.widget<Icon>(
      find.byIcon(Icons.calendar_today_outlined).first,
    );
    expect(dateRow.color, NubiaTheme.light.colorScheme.primary);
  });

  testWidgets(
      'une carte de l\'historique a un fond #FCFCFB et un rail neutre n500',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();

    final card = tester.widget<NubiaCard>(find.byType(NubiaCard).first);
    expect(card.backgroundColor, const Color(0xFFFCFCFB));

    final dateRow = tester.widget<Icon>(
      find.byIcon(Icons.calendar_today_outlined).first,
    );
    expect(dateRow.color, NubiaColors.n500);
  });
}
