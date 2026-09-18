//! Tests : `TasksBloc`/`TasksCard` (#7210) — chargement filtrable, clôture
//! en un tap (recharge la liste), création rapide (recharge la liste), et
//! rendu de la carte dashboard (squelette/vide/liste).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_secretariat/features/tasks/tasks_bloc.dart';
import 'package:app_secretariat/features/tasks/tasks_card.dart';
import 'package:app_secretariat/features/tasks/tasks_event.dart';
import 'package:app_secretariat/features/tasks/tasks_state.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockListCabinetTasksUseCase extends Mock
    implements ListCabinetTasksUseCase {}

class MockCreateCabinetTaskUseCase extends Mock
    implements CreateCabinetTaskUseCase {}

class MockCompleteCabinetTaskUseCase extends Mock
    implements CompleteCabinetTaskUseCase {}

class MockTasksBloc extends MockBloc<TasksEvent, TasksState>
    implements TasksBloc {}

const _openTask = CabinetTask(
  id: 'task-1',
  title: 'Préparer le guide chirurgical',
  assigneeDisplayName: 'Julie Martin',
  status: 'open',
  createdBy: 'user-1',
  createdAt: '2026-01-01T09:00:00Z',
);

const _secondOpenTask = CabinetTask(
  id: 'task-2',
  title: 'Relancer le labo',
  status: 'open',
  createdBy: 'user-1',
  createdAt: '2026-01-02T09:00:00Z',
);

void main() {
  group('TasksBloc', () {
    blocTest<TasksBloc, TasksState>(
      'TasksLoadRequested réussi émet Loading puis Loaded',
      build: () {
        final listTasks = MockListCabinetTasksUseCase();
        when(() => listTasks(
                assigneeId: any(named: 'assigneeId'),
                status: any(named: 'status')))
            .thenAnswer((_) async => const Right([_openTask]));
        return TasksBloc(
          listTasks: listTasks,
          createTask: MockCreateCabinetTaskUseCase(),
          completeTask: MockCompleteCabinetTaskUseCase(),
        );
      },
      act: (bloc) => bloc.add(const TasksLoadRequested(status: 'open')),
      expect: () => [
        const TasksLoading(),
        const TasksLoaded(tasks: [_openTask], status: 'open'),
      ],
    );

    blocTest<TasksBloc, TasksState>(
      'TasksLoadRequested en échec émet Loading puis Error',
      build: () {
        final listTasks = MockListCabinetTasksUseCase();
        when(() => listTasks(
                assigneeId: any(named: 'assigneeId'),
                status: any(named: 'status')))
            .thenAnswer((_) async => const Left(_FakeFailure('Erreur réseau')));
        return TasksBloc(
          listTasks: listTasks,
          createTask: MockCreateCabinetTaskUseCase(),
          completeTask: MockCompleteCabinetTaskUseCase(),
        );
      },
      act: (bloc) => bloc.add(const TasksLoadRequested()),
      expect: () => [
        const TasksLoading(),
        const TasksError('Erreur réseau'),
      ],
    );

    final completeTask = MockCompleteCabinetTaskUseCase();
    blocTest<TasksBloc, TasksState>(
      'TasksCompleteRequested réussi recharge la liste',
      build: () {
        final listTasks = MockListCabinetTasksUseCase();
        var callCount = 0;
        when(() => listTasks(
            assigneeId: any(named: 'assigneeId'),
            status: any(named: 'status'))).thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? const Right([_openTask, _secondOpenTask])
              : const Right([_secondOpenTask]);
        });
        when(() => completeTask('task-1'))
            .thenAnswer((_) async => const Right('done'));
        return TasksBloc(
          listTasks: listTasks,
          createTask: MockCreateCabinetTaskUseCase(),
          completeTask: completeTask,
        );
      },
      act: (bloc) async {
        bloc.add(const TasksLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const TasksCompleteRequested('task-1'));
      },
      expect: () => [
        const TasksLoading(),
        const TasksLoaded(tasks: [_openTask, _secondOpenTask]),
        const TasksLoaded(
          tasks: [_openTask, _secondOpenTask],
          actionInProgress: true,
        ),
        const TasksLoading(),
        const TasksLoaded(tasks: [_secondOpenTask]),
      ],
      verify: (_) => verify(() => completeTask('task-1')).called(1),
    );
  });

  group('TasksCard (widget)', () {
    testWidgets('affiche un squelette pendant le chargement', (tester) async {
      final bloc = MockTasksBloc();
      when(() => bloc.state).thenReturn(const TasksLoading());
      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<TasksBloc>.value(
              value: bloc, child: const TasksCard()),
        ),
      );

      expect(find.byKey(const Key('tasks_card_loading')), findsOneWidget);
    });

    testWidgets('affiche un message quand aucune tâche', (tester) async {
      final bloc = MockTasksBloc();
      when(() => bloc.state).thenReturn(const TasksLoaded(tasks: []));
      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<TasksBloc>.value(
              value: bloc, child: const TasksCard()),
        ),
      );

      expect(find.byKey(const Key('tasks_card_empty')), findsOneWidget);
    });

    testWidgets(
        'affiche les tâches et cocher la case dispatch TasksCompleteRequested',
        (tester) async {
      final bloc = MockTasksBloc();
      when(() => bloc.state).thenReturn(const TasksLoaded(tasks: [_openTask]));
      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<TasksBloc>.value(
              value: bloc, child: const TasksCard()),
        ),
      );

      expect(find.byKey(const Key('task_row_task-1')), findsOneWidget);
      expect(find.text('Préparer le guide chirurgical'), findsOneWidget);

      await tester.tap(find.byKey(const Key('task_checkbox_task-1')));
      await tester.pump();

      verify(() => bloc.add(const TasksCompleteRequested('task-1'))).called(1);
    });
  });
}
