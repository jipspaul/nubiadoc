//! Tests widget : `PlanSessionsSection` (#7172) — liste des séances
//! proposées, proposition (dialogue de réglage), sélection d'un créneau et
//! création du RDV.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/treatment_plans/treatment_sessions_cubit.dart';
import 'package:app_practicien/features/treatment_plans/widgets/plan_sessions_section.dart';

class MockTreatmentSessionsCubit extends MockCubit<TreatmentSessionsState>
    implements TreatmentSessionsCubit {}

const _sessionA = TreatmentSession(
  id: 'sess-a',
  position: 1,
  durationMin: 30,
  quoteItemIds: ['qi-1'],
);

const _sessionScheduled = TreatmentSession(
  id: 'sess-b',
  position: 2,
  durationMin: 45,
  quoteItemIds: ['qi-2', 'qi-3'],
  status: 'scheduled',
  appointmentId: 'appt-1',
);

final _slot = ProposedSlot(
  id: 'slot-1',
  practitionerId: 'prac-1',
  startsAt: DateTime(2026, 10, 5, 9),
  endsAt: DateTime(2026, 10, 5, 9, 30),
);

Widget _wrap(TreatmentSessionsCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<TreatmentSessionsCubit>.value(
          value: cubit,
          child: const PlanSessionsSection(planId: 'plan-1'),
        ),
      ),
    );

void main() {
  late MockTreatmentSessionsCubit cubit;

  setUp(() {
    cubit = MockTreatmentSessionsCubit();
  });

  testWidgets('aucune séance proposée → message vide affiché',
      (tester) async {
    when(() => cubit.state).thenReturn(const TreatmentSessionsInitial());
    await tester.pumpWidget(_wrap(cubit));

    expect(
      find.byKey(const Key('treatment_plan_sessions_empty_plan-1')),
      findsOneWidget,
    );
  });

  testWidgets('séances proposées → une ligne par séance avec pill statut',
      (tester) async {
    when(() => cubit.state).thenReturn(
      const TreatmentSessionsLoaded(sessions: [_sessionA, _sessionScheduled]),
    );
    await tester.pumpWidget(_wrap(cubit));

    expect(find.byKey(const Key('treatment_session_sess-a')), findsOneWidget);
    expect(find.text('Séance 1 · 30 min'), findsOneWidget);
    expect(find.text('Séance 2 · 45 min'), findsOneWidget);

    // Séance déjà programmée : plus de bouton créneaux, message dédié.
    expect(
      find.byKey(const Key('treatment_session_scheduled_sess-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('treatment_session_slots_button_sess-b')),
      findsNothing,
    );
  });

  testWidgets(
      'Proposer des séances → dialogue de durée puis propose(defaultDurationMin)',
      (tester) async {
    when(() => cubit.state).thenReturn(const TreatmentSessionsInitial());
    when(() => cubit.propose(defaultDurationMin: any(named: 'defaultDurationMin')))
        .thenAnswer((_) async {});
    await tester.pumpWidget(_wrap(cubit));

    await tester.tap(find.byKey(const Key('treatment_plan_propose_sessions_plan-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('treatment_plan_propose_sessions_dialog_plan-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('treatment_plan_propose_sessions_submit_plan-1')),
    );
    await tester.pumpAndSettle();

    verify(() => cubit.propose(defaultDurationMin: 30)).called(1);
  });

  testWidgets('Voir les créneaux → appelle loadSlots sur la séance',
      (tester) async {
    when(() => cubit.state).thenReturn(
      const TreatmentSessionsLoaded(sessions: [_sessionA]),
    );
    when(() => cubit.loadSlots('sess-a')).thenAnswer((_) async {});
    await tester.pumpWidget(_wrap(cubit));

    await tester.tap(
      find.byKey(const Key('treatment_session_slots_button_sess-a')),
    );
    await tester.pumpAndSettle();

    verify(() => cubit.loadSlots('sess-a')).called(1);
  });

  testWidgets(
      'séance dépliée avec créneaux → sélection d\'un chip appelle schedule',
      (tester) async {
    when(() => cubit.state).thenReturn(
      TreatmentSessionsLoaded(
        sessions: const [_sessionA],
        expandedSessionId: 'sess-a',
        slots: [_slot],
      ),
    );
    when(() => cubit.schedule('sess-a', 'slot-1')).thenAnswer((_) async {});
    await tester.pumpWidget(_wrap(cubit));

    final slotChip = find.byKey(const Key('treatment_session_slot_slot-1'));
    expect(slotChip, findsOneWidget);

    await tester.tap(slotChip);
    await tester.pumpAndSettle();

    verify(() => cubit.schedule('sess-a', 'slot-1')).called(1);
  });
}
