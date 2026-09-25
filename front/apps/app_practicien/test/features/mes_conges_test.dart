//! Tests : `MesCongesBloc`/`MesCongesBody` (#7143/#7144) — chargement,
//! annulation d'une demande (recharge la liste), et rendu de l'écran
//! (chargement/vide/liste/erreur). Même convention que `tasks_test.dart`.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_practicien/features/mes_conges/mes_conges_bloc.dart';
import 'package:app_practicien/features/mes_conges/mes_conges_event.dart';
import 'package:app_practicien/features/mes_conges/mes_conges_page.dart';
import 'package:app_practicien/features/mes_conges/mes_conges_state.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockListLeaveRequestsUseCase extends Mock
    implements ListLeaveRequestsUseCase {}

class MockCreateLeaveRequestUseCase extends Mock
    implements CreateLeaveRequestUseCase {}

class MockCancelLeaveRequestUseCase extends Mock
    implements CancelLeaveRequestUseCase {}

class MockMesCongesBloc extends MockBloc<MesCongesEvent, MesCongesState>
    implements MesCongesBloc {}

const _pendingRequest = LeaveRequest(
  id: 'leave-1',
  userId: 'user-1',
  startsAt: '2026-08-01T00:00:00Z',
  endsAt: '2026-08-05T23:59:59Z',
  kind: 'paid_leave',
  status: 'pending',
);

const _approvedRequest = LeaveRequest(
  id: 'leave-2',
  userId: 'user-1',
  startsAt: '2026-09-01T00:00:00Z',
  endsAt: '2026-09-02T23:59:59Z',
  kind: 'sick_leave',
  status: 'approved',
);

void main() {
  group('MesCongesBloc', () {
    blocTest<MesCongesBloc, MesCongesState>(
      'MesCongesLoadRequested réussi émet Loading puis Loaded',
      build: () {
        final listLeaveRequests = MockListLeaveRequestsUseCase();
        when(() => listLeaveRequests(
                userId: any(named: 'userId'), status: any(named: 'status')))
            .thenAnswer((_) async => const Right([_pendingRequest]));
        return MesCongesBloc(
          listLeaveRequests: listLeaveRequests,
          createLeaveRequest: MockCreateLeaveRequestUseCase(),
          cancelLeaveRequest: MockCancelLeaveRequestUseCase(),
        );
      },
      act: (bloc) =>
          bloc.add(const MesCongesLoadRequested(userId: 'user-1')),
      expect: () => [
        const MesCongesLoading(),
        const MesCongesLoaded(requests: [_pendingRequest], userId: 'user-1'),
      ],
    );

    blocTest<MesCongesBloc, MesCongesState>(
      'MesCongesLoadRequested en échec émet Loading puis Error',
      build: () {
        final listLeaveRequests = MockListLeaveRequestsUseCase();
        when(() => listLeaveRequests(
                userId: any(named: 'userId'), status: any(named: 'status')))
            .thenAnswer((_) async => const Left(_FakeFailure('Erreur réseau')));
        return MesCongesBloc(
          listLeaveRequests: listLeaveRequests,
          createLeaveRequest: MockCreateLeaveRequestUseCase(),
          cancelLeaveRequest: MockCancelLeaveRequestUseCase(),
        );
      },
      act: (bloc) => bloc.add(const MesCongesLoadRequested()),
      expect: () => [
        const MesCongesLoading(),
        const MesCongesError('Erreur réseau'),
      ],
    );

    final cancelLeaveRequest = MockCancelLeaveRequestUseCase();
    blocTest<MesCongesBloc, MesCongesState>(
      'MesCongesCancelRequested réussi recharge la liste',
      build: () {
        final listLeaveRequests = MockListLeaveRequestsUseCase();
        var callCount = 0;
        when(() => listLeaveRequests(
            userId: any(named: 'userId'),
            status: any(named: 'status'))).thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? const Right([_pendingRequest, _approvedRequest])
              : const Right([_approvedRequest]);
        });
        when(() => cancelLeaveRequest('leave-1'))
            .thenAnswer((_) async => const Right(_pendingRequest));
        return MesCongesBloc(
          listLeaveRequests: listLeaveRequests,
          createLeaveRequest: MockCreateLeaveRequestUseCase(),
          cancelLeaveRequest: cancelLeaveRequest,
        );
      },
      act: (bloc) async {
        bloc.add(const MesCongesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const MesCongesCancelRequested('leave-1'));
      },
      expect: () => [
        const MesCongesLoading(),
        const MesCongesLoaded(requests: [_pendingRequest, _approvedRequest]),
        const MesCongesLoaded(
          requests: [_pendingRequest, _approvedRequest],
          actionInProgress: true,
        ),
        const MesCongesLoading(),
        const MesCongesLoaded(requests: [_approvedRequest]),
      ],
      verify: (_) => verify(() => cancelLeaveRequest('leave-1')).called(1),
    );
  });

  group('MesCongesBody (widget)', () {
    testWidgets('affiche un indicateur de chargement', (tester) async {
      final bloc = MockMesCongesBloc();
      when(() => bloc.state).thenReturn(const MesCongesLoading());
      await tester.pumpApp(
        BlocProvider<MesCongesBloc>.value(
            value: bloc, child: const MesCongesBody()),
      );

      expect(find.byKey(const Key('mes_conges_loading')), findsOneWidget);
    });

    testWidgets('aucune demande → état vide', (tester) async {
      final bloc = MockMesCongesBloc();
      when(() => bloc.state).thenReturn(const MesCongesLoaded(requests: []));
      await tester.pumpApp(
        BlocProvider<MesCongesBloc>.value(
            value: bloc, child: const MesCongesBody()),
      );

      expect(find.byKey(const Key('mes_conges_empty')), findsOneWidget);
    });

    testWidgets('affiche mes demandes de congé', (tester) async {
      final bloc = MockMesCongesBloc();
      when(() => bloc.state).thenReturn(
          const MesCongesLoaded(requests: [_pendingRequest, _approvedRequest]));
      await tester.pumpApp(
        BlocProvider<MesCongesBloc>.value(
            value: bloc, child: const MesCongesBody()),
      );

      expect(find.byKey(const Key('leave_request_row_leave-1')),
          findsOneWidget);
      expect(find.byKey(const Key('leave_request_row_leave-2')),
          findsOneWidget);
      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('Approuvé'), findsOneWidget);
    });

    testWidgets(
        'annuler une demande pending dispatch MesCongesCancelRequested',
        (tester) async {
      final bloc = MockMesCongesBloc();
      when(() => bloc.state)
          .thenReturn(const MesCongesLoaded(requests: [_pendingRequest]));
      await tester.pumpApp(
        BlocProvider<MesCongesBloc>.value(
            value: bloc, child: const MesCongesBody()),
      );

      await tester
          .tap(find.byKey(const Key('leave_request_cancel_leave-1')));
      await tester.pump();

      verify(() =>
              bloc.add(const MesCongesCancelRequested('leave-1')))
          .called(1);
    });

    testWidgets('erreur → NubiaErrorWidget avec message', (tester) async {
      final bloc = MockMesCongesBloc();
      when(() => bloc.state)
          .thenReturn(const MesCongesError('Erreur réseau'));
      await tester.pumpApp(
        BlocProvider<MesCongesBloc>.value(
            value: bloc, child: const MesCongesBody()),
      );

      expect(find.byKey(const Key('mes_conges_error')), findsOneWidget);
    });
  });
}
