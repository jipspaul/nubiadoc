//! Tests : `CongesBloc`/`CongesPage` (#7143/#7144) — chargement de la file
//! de validation, approbation/refus (recharge la liste), et 403 (secrétaire
//! simple) affiché en erreur d'action plutôt que de bloquer l'écran. Même
//! convention que `audit_log_test.dart`/`tasks_test.dart`.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_secretariat/features/conges/conges_bloc.dart';
import 'package:app_secretariat/features/conges/conges_event.dart';
import 'package:app_secretariat/features/conges/conges_page.dart';
import 'package:app_secretariat/features/conges/conges_state.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockListLeaveRequestsUseCase extends Mock
    implements ListLeaveRequestsUseCase {}

class MockDecideLeaveRequestUseCase extends Mock
    implements DecideLeaveRequestUseCase {}

class MockListMembersUseCase extends Mock implements ListMembersUseCase {}

class MockCongesBloc extends MockBloc<CongesEvent, CongesState>
    implements CongesBloc {}

const _pendingRequest = LeaveRequest(
  id: 'leave-1',
  userId: 'user-1',
  startsAt: '2026-08-01T00:00:00Z',
  endsAt: '2026-08-05T23:59:59Z',
  kind: 'paid_leave',
  status: 'pending',
);

void main() {
  group('CongesBloc', () {
    blocTest<CongesBloc, CongesState>(
      'CongesLoadRequested réussi émet Loading puis Loaded',
      build: () {
        final listLeaveRequests = MockListLeaveRequestsUseCase();
        when(() => listLeaveRequests(status: any(named: 'status')))
            .thenAnswer((_) async => const Right([_pendingRequest]));
        return CongesBloc(
          listLeaveRequests: listLeaveRequests,
          decideLeaveRequest: MockDecideLeaveRequestUseCase(),
        );
      },
      act: (bloc) => bloc.add(const CongesLoadRequested(status: 'pending')),
      expect: () => [
        const CongesLoading(),
        const CongesLoaded(requests: [_pendingRequest], status: 'pending'),
      ],
    );

    blocTest<CongesBloc, CongesState>(
      'CongesLoadRequested en échec émet Loading puis Error',
      build: () {
        final listLeaveRequests = MockListLeaveRequestsUseCase();
        when(() => listLeaveRequests(status: any(named: 'status')))
            .thenAnswer((_) async => const Left(_FakeFailure('Erreur réseau')));
        return CongesBloc(
          listLeaveRequests: listLeaveRequests,
          decideLeaveRequest: MockDecideLeaveRequestUseCase(),
        );
      },
      act: (bloc) => bloc.add(const CongesLoadRequested()),
      expect: () => [
        const CongesLoading(),
        const CongesError('Erreur réseau'),
      ],
    );

    final decideLeaveRequest = MockDecideLeaveRequestUseCase();
    blocTest<CongesBloc, CongesState>(
      'CongesDecideRequested (approve) réussi recharge la liste',
      build: () {
        final listLeaveRequests = MockListLeaveRequestsUseCase();
        var callCount = 0;
        when(() => listLeaveRequests(status: any(named: 'status')))
            .thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? const Right([_pendingRequest])
              : const Right([]);
        });
        when(() => decideLeaveRequest(id: 'leave-1', approve: true))
            .thenAnswer((_) async => const Right(_pendingRequest));
        return CongesBloc(
          listLeaveRequests: listLeaveRequests,
          decideLeaveRequest: decideLeaveRequest,
        );
      },
      act: (bloc) async {
        bloc.add(const CongesLoadRequested(status: 'pending'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const CongesDecideRequested(
            leaveRequestId: 'leave-1', approve: true));
      },
      expect: () => [
        const CongesLoading(),
        const CongesLoaded(requests: [_pendingRequest], status: 'pending'),
        const CongesLoaded(
          requests: [_pendingRequest],
          status: 'pending',
          actionInProgress: true,
        ),
        const CongesLoading(),
        const CongesLoaded(requests: [], status: 'pending'),
      ],
      verify: (_) =>
          verify(() => decideLeaveRequest(id: 'leave-1', approve: true))
              .called(1),
    );

    blocTest<CongesBloc, CongesState>(
      '403 (secrétaire simple) → erreur d\'action, pas un écran bloqué',
      build: () {
        final listLeaveRequests = MockListLeaveRequestsUseCase();
        when(() => listLeaveRequests(status: any(named: 'status')))
            .thenAnswer((_) async => const Right([_pendingRequest]));
        final decide = MockDecideLeaveRequestUseCase();
        when(() => decide(id: 'leave-1', approve: true)).thenAnswer(
            (_) async => const Left(ServerFailure(
                message: 'Validation réservée aux administrateurs/managers.',
                statusCode: 403)));
        return CongesBloc(
          listLeaveRequests: listLeaveRequests,
          decideLeaveRequest: decide,
        );
      },
      act: (bloc) async {
        bloc.add(const CongesLoadRequested(status: 'pending'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const CongesDecideRequested(
            leaveRequestId: 'leave-1', approve: true));
      },
      expect: () => [
        const CongesLoading(),
        const CongesLoaded(requests: [_pendingRequest], status: 'pending'),
        const CongesLoaded(
          requests: [_pendingRequest],
          status: 'pending',
          actionInProgress: true,
        ),
        const CongesLoaded(
          requests: [_pendingRequest],
          status: 'pending',
          actionError: 'Validation réservée aux administrateurs/managers.',
        ),
      ],
    );
  });

  group('CongesPage (widget)', () {
    setUp(() {
      final listMembers = MockListMembersUseCase();
      when(() => listMembers()).thenAnswer((_) async => const Right([]));
      GetIt.instance
          .registerFactory<ListMembersUseCase>(() => listMembers);
    });

    tearDown(() => GetIt.instance.reset());

    testWidgets('affiche la file de demandes en attente', (tester) async {
      final bloc = MockCongesBloc();
      when(() => bloc.state).thenReturn(
          const CongesLoaded(requests: [_pendingRequest], status: 'pending'));
      await tester.pumpApp(
        BlocProvider<CongesBloc>.value(value: bloc, child: const CongesPage()),
      );
      await tester.pump();

      expect(
          find.byKey(const Key('leave_request_row_leave-1')), findsOneWidget);
      expect(find.byKey(const Key('leave_request_approve_leave-1')),
          findsOneWidget);
      expect(find.byKey(const Key('leave_request_reject_leave-1')),
          findsOneWidget);
    });

    testWidgets('aucune demande → état vide', (tester) async {
      final bloc = MockCongesBloc();
      when(() => bloc.state)
          .thenReturn(const CongesLoaded(requests: [], status: 'pending'));
      await tester.pumpApp(
        BlocProvider<CongesBloc>.value(value: bloc, child: const CongesPage()),
      );
      await tester.pump();

      expect(find.byKey(const Key('conges_empty')), findsOneWidget);
    });

    testWidgets('tap Approuver dispatch CongesDecideRequested(approve: true)',
        (tester) async {
      final bloc = MockCongesBloc();
      when(() => bloc.state).thenReturn(
          const CongesLoaded(requests: [_pendingRequest], status: 'pending'));
      await tester.pumpApp(
        BlocProvider<CongesBloc>.value(value: bloc, child: const CongesPage()),
      );
      await tester.pump();

      await tester
          .tap(find.byKey(const Key('leave_request_approve_leave-1')));
      await tester.pump();

      verify(() => bloc.add(const CongesDecideRequested(
          leaveRequestId: 'leave-1', approve: true))).called(1);
    });
  });
}
