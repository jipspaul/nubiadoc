import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/correspondents/correspondent_stats_cubit.dart';
import 'package:app_secretariat/features/correspondents/correspondents_bloc.dart';
import 'package:app_secretariat/features/correspondents/correspondents_event.dart';
import 'package:app_secretariat/features/correspondents/correspondents_page.dart';
import 'package:app_secretariat/features/correspondents/correspondents_state.dart';

class _MockCabinetCorrespondentsRepository extends Mock
    implements CabinetCorrespondentsRepository {}

class _MockCorrespondentsBloc
    extends MockBloc<CorrespondentsEvent, CorrespondentsState>
    implements CorrespondentsBloc {}

class _MockGetCorrespondentStats extends Mock
    implements GetCorrespondentStatsUseCase {}

class _FakeCorrespondentsEvent extends Fake implements CorrespondentsEvent {}

final _correspondent = CabinetCorrespondent(
  id: 'corr-1',
  displayName: 'Dr Adresseur',
  specialty: 'Orthodontie',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  // --- CorrespondentsBloc ----------------------------------------------------
  group('CorrespondentsBloc', () {
    late _MockCabinetCorrespondentsRepository repo;
    late ListCabinetCorrespondentsUseCase list;
    late CreateCabinetCorrespondentUseCase create;
    late UpdateCabinetCorrespondentUseCase update;
    late DeleteCabinetCorrespondentUseCase delete;

    setUp(() {
      repo = _MockCabinetCorrespondentsRepository();
      list = ListCabinetCorrespondentsUseCase(repo);
      create = CreateCabinetCorrespondentUseCase(repo);
      update = UpdateCabinetCorrespondentUseCase(repo);
      delete = DeleteCabinetCorrespondentUseCase(repo);
    });

    CorrespondentsBloc buildBloc() => CorrespondentsBloc(
          list: list,
          create: create,
          update: update,
          delete: delete,
        );

    blocTest<CorrespondentsBloc, CorrespondentsState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => repo.list())
            .thenAnswer((_) async => Right([_correspondent]));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CorrespondentsLoadRequested()),
      expect: () => [
        const CorrespondentsLoading(),
        CorrespondentsLoaded([_correspondent]),
      ],
    );

    blocTest<CorrespondentsBloc, CorrespondentsState>(
      'émet Loading puis Empty si liste vide',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => const Right([]));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CorrespondentsLoadRequested()),
      expect: () => [
        const CorrespondentsLoading(),
        const CorrespondentsEmpty(),
      ],
    );

    blocTest<CorrespondentsBloc, CorrespondentsState>(
      'émet MutationSuccess puis recharge la liste après une création',
      build: () {
        when(() => repo.create(
              displayName: any(named: 'displayName'),
              specialty: any(named: 'specialty'),
              email: any(named: 'email'),
              phone: any(named: 'phone'),
              address: any(named: 'address'),
              rpps: any(named: 'rpps'),
              notes: any(named: 'notes'),
            )).thenAnswer((_) async => Right(_correspondent));
        when(() => repo.list())
            .thenAnswer((_) async => Right([_correspondent]));
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const CorrespondentsCreateRequested(displayName: 'Dr Adresseur'),
      ),
      expect: () => [
        const CorrespondentsMutationSuccess(),
        const CorrespondentsLoading(),
        CorrespondentsLoaded([_correspondent]),
      ],
    );

    blocTest<CorrespondentsBloc, CorrespondentsState>(
      'émet MutationError sur échec de création (nom vide)',
      build: () {
        when(() => repo.create(
              displayName: any(named: 'displayName'),
              specialty: any(named: 'specialty'),
              email: any(named: 'email'),
              phone: any(named: 'phone'),
              address: any(named: 'address'),
              rpps: any(named: 'rpps'),
              notes: any(named: 'notes'),
            )).thenAnswer(
          (_) async => const Left(ValidationFailure(
            message: 'Le nom du correspondant est obligatoire ou un champ '
                'est invalide.',
          )),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const CorrespondentsCreateRequested(displayName: ''),
      ),
      expect: () => [
        const CorrespondentsMutationError(
            'Le nom du correspondant est obligatoire ou un champ '
            'est invalide.'),
      ],
    );

    blocTest<CorrespondentsBloc, CorrespondentsState>(
      'émet MutationError sur suppression refusée (409 référencé)',
      build: () {
        when(() => repo.delete(any())).thenAnswer(
          (_) async => const Left(ServerFailure(
            message: 'Ce correspondant est référencé par au moins un '
                'patient ou un courrier : impossible de le supprimer.',
            statusCode: 409,
            code: 'correspondent_in_use',
          )),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CorrespondentsDeleteRequested('corr-1')),
      expect: () => [
        const CorrespondentsMutationError(
            'Ce correspondant est référencé par au moins un patient ou un '
            'courrier : impossible de le supprimer.'),
      ],
    );
  });

  // --- CorrespondentsPage widget test -----------------------------------------
  group('CorrespondentsPage', () {
    late _MockCorrespondentsBloc bloc;
    late _MockGetCorrespondentStats getStats;

    setUpAll(() {
      registerFallbackValue(_FakeCorrespondentsEvent());
    });

    setUp(() {
      bloc = _MockCorrespondentsBloc();
      getStats = _MockGetCorrespondentStats();
      when(() => getStats(any())).thenAnswer(
        (_) async => const Right(CorrespondentStats(
          referredPatientsCount: 3,
          billedRevenueCents: 45000,
          lettersSentCount: 2,
        )),
      );
      GetIt.instance.registerFactory<CorrespondentStatsCubit>(
        () => CorrespondentStatsCubit(getStats: getStats),
      );
      addTearDown(GetIt.instance.reset);
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<CorrespondentsBloc>.value(
            value: bloc,
            child: const CorrespondentsPage(),
          ),
        );

    testWidgets('état vide : affiche NubiaEmptyState', (tester) async {
      when(() => bloc.state).thenReturn(const CorrespondentsEmpty());
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('correspondents_empty')), findsOneWidget);
      expect(find.text('Aucun correspondant enregistré.'), findsOneWidget);
      expect(find.byKey(const Key('add_correspondent_fab')), findsOneWidget);
    });

    testWidgets('état rempli : affiche les correspondants', (tester) async {
      when(() => bloc.state)
          .thenReturn(CorrespondentsLoaded([_correspondent]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Dr Adresseur'), findsOneWidget);
      expect(find.text('Orthodontie'), findsOneWidget);
      expect(find.byKey(const Key('correspondent_edit_corr-1')),
          findsOneWidget);
      expect(find.byKey(const Key('correspondent_delete_corr-1')),
          findsOneWidget);
    });

    testWidgets(
        'tap sur un correspondant ouvre sa fiche avec ses stats',
        (tester) async {
      when(() => bloc.state)
          .thenReturn(CorrespondentsLoaded([_correspondent]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('correspondent_tile_corr-1')));
      await tester.pumpAndSettle();

      expect(find.text('Patients adressés : 3'), findsOneWidget);
      expect(find.byKey(const Key('correspondent_stats_billed_revenue')),
          findsOneWidget);
      expect(find.text('Courriers envoyés : 2'), findsOneWidget);
    });

    testWidgets('tap supprimer ajoute CorrespondentsDeleteRequested',
        (tester) async {
      when(() => bloc.state)
          .thenReturn(CorrespondentsLoaded([_correspondent]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('correspondent_delete_corr-1')));
      await tester.pump();

      final captured = verify(() => bloc.add(captureAny())).captured.last
          as CorrespondentsDeleteRequested;
      expect(captured.id, 'corr-1');
    });

    testWidgets('état d\'erreur : affiche le message', (tester) async {
      when(() => bloc.state)
          .thenReturn(const CorrespondentsError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });
  });
}
