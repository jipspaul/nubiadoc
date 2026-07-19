// Régression #3802 — tout créneau occupé affichait « Réservé » +
// Confirmer/Démarrer quel que soit son statut réel (annulé/terminé/à
// confirmer confondus). Rend la vraie AgendaBody (bloc via BlocProvider,
// comme en prod) pour vérifier le libellé et les actions par statut.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_page.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';

class _MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

AgendaEntry _entryWithStatus(String id, String status) => AgendaEntry(
      id: id,
      cabinetId: 'cab-1',
      practitionerId: 'prac-1',
      practitionerName: 'Dr. Dupont',
      startsAt: DateTime(2026, 6, 16, 9, 0),
      endsAt: DateTime(2026, 6, 16, 9, 30),
      patientId: 'pat-1',
      patientName: 'Marie Martin',
      motif: 'Détartrage',
      isFree: false,
      status: status,
    );

Future<void> _pump(WidgetTester tester, AgendaEntry entry) async {
  final mockBloc = _MockAgendaBloc();
  final state =
      AgendaLoaded(entries: [entry], weekStart: DateTime(2026, 6, 16));
  whenListen(
    mockBloc,
    Stream<AgendaState>.fromIterable([state]).asBroadcastStream(),
    initialState: state,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<AgendaBloc>.value(
        value: mockBloc,
        child: const Scaffold(body: AgendaBody()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('RDV annulé : libellé Annulé, aucun bouton d\'action',
      (tester) async {
    await _pump(tester, _entryWithStatus('ag-cancelled', 'cancelled'));

    expect(find.text('Annulé'), findsOneWidget);
    expect(find.text('Réservé'), findsNothing);
    expect(find.byKey(const Key('confirm_ag-cancelled')), findsNothing);
    expect(find.byKey(const Key('start_ag-cancelled')), findsNothing);
  });

  testWidgets('RDV terminé : libellé Terminé, aucun bouton d\'action',
      (tester) async {
    await _pump(tester, _entryWithStatus('ag-done', 'done'));

    expect(find.text('Terminé'), findsOneWidget);
    expect(find.byKey(const Key('confirm_ag-done')), findsNothing);
    expect(find.byKey(const Key('start_ag-done')), findsNothing);
  });

  testWidgets(
      'RDV à confirmer (requested) : libellé À confirmer, seul Confirmer '
      'est proposé', (tester) async {
    await _pump(tester, _entryWithStatus('ag-requested', 'requested'));

    expect(find.text('À confirmer'), findsOneWidget);
    expect(find.byKey(const Key('confirm_ag-requested')), findsOneWidget);
    expect(find.byKey(const Key('start_ag-requested')), findsNothing);
  });

  testWidgets(
      'RDV confirmé : libellé Confirmé, seul Démarrer est proposé '
      '(re-Confirmer donnerait 409)', (tester) async {
    await _pump(tester, _entryWithStatus('ag-confirmed', 'confirmed'));

    expect(find.text('Confirmé'), findsOneWidget);
    expect(find.byKey(const Key('confirm_ag-confirmed')), findsNothing);
    expect(find.byKey(const Key('start_ag-confirmed')), findsOneWidget);
  });
}
