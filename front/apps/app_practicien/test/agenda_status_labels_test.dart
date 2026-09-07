// Régression #3802 — tout créneau occupé affichait « Réservé » +
// Confirmer/Démarrer quel que soit son statut réel (annulé/terminé/à
// confirmer confondus). Rend la vraie AgendaBody (bloc via BlocProvider,
// comme en prod) pour vérifier le libellé et les actions par statut.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_page.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

class _MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

class _MockProAuthCubit extends MockCubit<AuthState>
    implements ProAuthCubit {}

AgendaEntry _entryWithStatus(
  String id,
  String status, {
  String practitionerId = 'prac-1',
  DateTime? startsAt,
}) =>
    AgendaEntry(
      id: id,
      cabinetId: 'cab-1',
      practitionerId: practitionerId,
      practitionerName: 'Dr. Dupont',
      startsAt: startsAt ?? DateTime(2026, 6, 16, 9, 0),
      endsAt: (startsAt ?? DateTime(2026, 6, 16, 9, 0))
          .add(const Duration(minutes: 30)),
      patientId: 'pat-1',
      patientName: 'Marie Martin',
      motif: 'Détartrage',
      isFree: false,
      status: status,
    );

/// #6651 : le praticien connecté par défaut dans ces tests possède l'entrée
/// (`practitionerId: 'prac-1'`) — la garde de propriété ajoutée pour
/// l'issue est donc neutre pour les scénarios de libellé/statut déjà
/// couverts ici ; elle est exercée explicitement plus bas.
Future<void> _pump(
  WidgetTester tester,
  AgendaEntry entry, {
  String? sessionPractitionerId = 'prac-1',
}) async {
  final mockBloc = _MockAgendaBloc();
  final state =
      AgendaLoaded(entries: [entry], weekStart: DateTime(2026, 6, 16));
  whenListen(
    mockBloc,
    Stream<AgendaState>.fromIterable([state]).asBroadcastStream(),
    initialState: state,
  );

  final mockAuthCubit = _MockProAuthCubit();
  when(() => mockAuthCubit.state).thenReturn(
    AuthAuthenticated(
      AuthSession(
        kind: UserKind.pro,
        userId: 'user-1',
        role: ProRole.practitioner,
        practitionerId: sessionPractitionerId,
      ),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<AgendaBloc>.value(
        value: mockBloc,
        child: BlocProvider<ProAuthCubit>.value(
          value: mockAuthCubit,
          child: const Scaffold(body: AgendaBody()),
        ),
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

  // #6651 — l'agenda praticien liste tout le cabinet (#6213) mais
  // `POST .../start` (scheduling.rs) rejette un démarrage hors fenêtre
  // (409 too_early) ou sur le RDV d'un confrère (403 forbidden) : le bouton
  // ne doit être offert que là où l'appel peut aboutir.
  testWidgets(
      'RDV confirmé d\'un confrère : Démarrer absent (403 forbidden côté back)',
      (tester) async {
    await _pump(
      tester,
      _entryWithStatus('ag-confrere', 'confirmed', practitionerId: 'prac-2'),
      sessionPractitionerId: 'prac-1',
    );

    expect(find.byKey(const Key('start_ag-confrere')), findsNothing);
  });

  testWidgets(
      'RDV confirmé trop tôt (starts_at - 60min pas atteint) : Démarrer absent '
      '(409 too_early côté back)', (tester) async {
    await _pump(
      tester,
      _entryWithStatus(
        'ag-too-early',
        'confirmed',
        startsAt: DateTime.now().add(const Duration(hours: 3)),
      ),
    );

    expect(find.byKey(const Key('start_ag-too-early')), findsNothing);
  });
}
