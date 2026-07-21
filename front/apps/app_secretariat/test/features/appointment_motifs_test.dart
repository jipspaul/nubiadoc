import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/appointment_motifs/appointment_motifs_bloc.dart';
import 'package:app_secretariat/features/appointment_motifs/appointment_motifs_event.dart';
import 'package:app_secretariat/features/appointment_motifs/appointment_motifs_page.dart';
import 'package:app_secretariat/features/appointment_motifs/appointment_motifs_state.dart';
import 'package:app_secretariat/session/pro_auth_cubit.dart';

class _MockAppointmentMotifsRepository extends Mock
    implements AppointmentMotifsRepository {}

class _MockAppointmentMotifsBloc
    extends MockBloc<AppointmentMotifsEvent, AppointmentMotifsState>
    implements AppointmentMotifsBloc {}

class _MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

class _FakeAppointmentMotifsEvent extends Fake
    implements AppointmentMotifsEvent {}

const _adminSession = AuthSession(
  kind: UserKind.pro,
  userId: 'me',
  role: ProRole.admin,
);

const _secretarySession = AuthSession(
  kind: UserKind.pro,
  userId: 'me',
  role: ProRole.secretary,
);

void main() {
  // --- AppointmentMotifsBloc ----------------------------------------------
  group('AppointmentMotifsBloc', () {
    late _MockAppointmentMotifsRepository repo;
    late ListAppointmentMotifsUseCase list;
    late CreateAppointmentMotifUseCase create;
    late UpdateAppointmentMotifUseCase update;
    late DeleteAppointmentMotifUseCase delete;

    const motifs = [
      AppointmentMotif(
          id: 'm1', label: 'Détartrage', defaultDurationMinutes: 30),
    ];

    setUp(() {
      repo = _MockAppointmentMotifsRepository();
      list = ListAppointmentMotifsUseCase(repo);
      create = CreateAppointmentMotifUseCase(repo);
      update = UpdateAppointmentMotifUseCase(repo);
      delete = DeleteAppointmentMotifUseCase(repo);
    });

    AppointmentMotifsBloc buildBloc() => AppointmentMotifsBloc(
          list: list,
          create: create,
          update: update,
          delete: delete,
        );

    blocTest<AppointmentMotifsBloc, AppointmentMotifsState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => const Right(motifs));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AppointmentMotifsLoadRequested()),
      expect: () => [
        const AppointmentMotifsLoading(),
        const AppointmentMotifsLoaded(motifs),
      ],
    );

    blocTest<AppointmentMotifsBloc, AppointmentMotifsState>(
      'émet Loading puis Empty si liste vide',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => const Right([]));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AppointmentMotifsLoadRequested()),
      expect: () => [
        const AppointmentMotifsLoading(),
        const AppointmentMotifsEmpty(),
      ],
    );

    blocTest<AppointmentMotifsBloc, AppointmentMotifsState>(
      'émet MutationSuccess puis recharge la liste après une création',
      build: () {
        when(() => repo.create(
              label: any(named: 'label'),
              defaultDurationMinutes: any(named: 'defaultDurationMinutes'),
            )).thenAnswer((_) async => Right(motifs.first));
        when(() => repo.list()).thenAnswer((_) async => const Right(motifs));
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const AppointmentMotifsCreateRequested(label: 'Détartrage'),
      ),
      expect: () => [
        const AppointmentMotifsMutationSuccess(),
        const AppointmentMotifsLoading(),
        const AppointmentMotifsLoaded(motifs),
      ],
    );

    blocTest<AppointmentMotifsBloc, AppointmentMotifsState>(
      'émet WriteForbidden sur 403 (création admin-only)',
      build: () {
        when(() => repo.create(
              label: any(named: 'label'),
              defaultDurationMinutes: any(named: 'defaultDurationMinutes'),
            )).thenAnswer(
          (_) async => const Left(ServerFailure(
            message: 'Réservé aux administrateurs du cabinet.',
            statusCode: 403,
          )),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        const AppointmentMotifsCreateRequested(label: 'Détartrage'),
      ),
      expect: () => [
        const AppointmentMotifsWriteForbidden(
            'Réservé aux administrateurs du cabinet.'),
      ],
    );

    blocTest<AppointmentMotifsBloc, AppointmentMotifsState>(
      'émet MutationSuccess puis recharge après une suppression',
      build: () {
        when(() => repo.delete(any()))
            .thenAnswer((_) async => const Right(null));
        when(() => repo.list()).thenAnswer((_) async => const Right([]));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AppointmentMotifsDeleteRequested('m1')),
      expect: () => [
        const AppointmentMotifsMutationSuccess(),
        const AppointmentMotifsLoading(),
        const AppointmentMotifsEmpty(),
      ],
    );
  });

  // --- AppointmentMotifsPage widget test -----------------------------------
  group('AppointmentMotifsPage', () {
    late _MockAppointmentMotifsBloc bloc;
    late _MockProAuthCubit authCubit;

    setUpAll(() {
      registerFallbackValue(_FakeAppointmentMotifsEvent());
    });

    setUp(() {
      bloc = _MockAppointmentMotifsBloc();
      authCubit = _MockProAuthCubit();
    });

    Widget buildPage(AuthSession session) {
      when(() => authCubit.state).thenReturn(AuthAuthenticated(session));
      return MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentMotifsBloc>.value(value: bloc),
            BlocProvider<ProAuthCubit>.value(value: authCubit),
          ],
          child: const AppointmentMotifsPage(),
        ),
      );
    }

    testWidgets('état vide : affiche NubiaEmptyState', (tester) async {
      when(() => bloc.state).thenReturn(const AppointmentMotifsEmpty());
      await tester.pumpWidget(buildPage(_secretarySession));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_motifs_empty')), findsOneWidget);
      expect(find.text('Aucun motif de RDV enregistré.'), findsOneWidget);
    });

    testWidgets('état rempli : affiche les motifs', (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentMotifsLoaded([
          AppointmentMotif(
              id: 'm1', label: 'Détartrage', defaultDurationMinutes: 30),
          AppointmentMotif(id: 'm2', label: 'Urgence douleur'),
        ]),
      );
      await tester.pumpWidget(buildPage(_secretarySession));
      await tester.pumpAndSettle();

      expect(find.text('Détartrage'), findsOneWidget);
      expect(find.text('Urgence douleur'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
    });

    testWidgets('rôle secretary : FAB et actions édition/suppression masqués',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentMotifsLoaded([
          AppointmentMotif(id: 'm1', label: 'Détartrage'),
        ]),
      );
      await tester.pumpWidget(buildPage(_secretarySession));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_motif_fab')), findsNothing);
      expect(find.byKey(const Key('motif_edit_m1')), findsNothing);
      expect(find.byKey(const Key('motif_delete_m1')), findsNothing);
    });

    testWidgets('rôle admin : FAB et actions édition/suppression visibles',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentMotifsLoaded([
          AppointmentMotif(id: 'm1', label: 'Détartrage'),
        ]),
      );
      await tester.pumpWidget(buildPage(_adminSession));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_motif_fab')), findsOneWidget);
      expect(find.byKey(const Key('motif_edit_m1')), findsOneWidget);
      expect(find.byKey(const Key('motif_delete_m1')), findsOneWidget);
    });

    testWidgets('état d\'erreur : affiche le message', (tester) async {
      when(() => bloc.state)
          .thenReturn(const AppointmentMotifsError('Erreur de connexion'));
      await tester.pumpWidget(buildPage(_secretarySession));
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });
  });
}
