import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/home/home_bloc.dart';
import 'package:app_patient/features/home/home_event.dart';
import 'package:app_patient/features/home/home_page.dart';
import 'package:app_patient/features/home/home_state.dart';
import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetDashboardSummaryUseCase extends Mock
    implements GetDashboardSummaryUseCase {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _summary = DashboardSummary(
  upcomingAppointments: 2,
  documentsToSign: 1,
  pendingPaymentsCents: 0,
  unreadMessages: 3,
  pendingQuestionnaires: 0,
);

const _emptySummary = DashboardSummary(
  upcomingAppointments: 0,
  documentsToSign: 0,
  pendingPaymentsCents: 0,
  unreadMessages: 0,
  pendingQuestionnaires: 0,
);

Widget _wrap(HomeBloc bloc) {
  final authCubit = MockAuthCubit();
  when(() => authCubit.state).thenReturn(const AuthUnauthenticated());
  return MaterialApp(
    theme: NubiaTheme.light,
    home: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: bloc),
        BlocProvider<AuthCubit>(create: (_) => authCubit),
      ],
      child: const Scaffold(body: HomePage()),
    ),
  );
}

HomeBloc _makeBloc(MockGetDashboardSummaryUseCase uc) =>
    HomeBloc(getDashboardSummary: uc);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetDashboardSummaryUseCase mockGetSummary;

  setUp(() {
    mockGetSummary = MockGetDashboardSummaryUseCase();
  });

  group('HomePage', () {
    testWidgets('affiche un indicateur de chargement en état initial',
        (tester) async {
      final bloc = _makeBloc(mockGetSummary);

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche les cartes de résumé en état loaded', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_summary));

      final bloc = _makeBloc(mockGetSummary);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_content')), findsOneWidget);
      expect(find.byKey(const Key('card_appointments')), findsOneWidget);
      expect(find.byKey(const Key('card_documents')), findsOneWidget);
      expect(find.byKey(const Key('card_messages')), findsOneWidget);
    });

    testWidgets('affiche l\'état vide quand le résumé est vide',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_empty')), findsOneWidget);
    });

    testWidgets('affiche un message d\'erreur en état error', (tester) async {
      when(() => mockGetSummary()).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );

      final bloc = _makeBloc(mockGetSummary);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Erreur réseau.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });

  group('HomeBloc', () {
    blocTest<HomeBloc, HomeState>(
      'émet [Loading, Loaded] quand getDashboardSummary réussit',
      build: () {
        when(() => mockGetSummary())
            .thenAnswer((_) async => const Right(_summary));
        return _makeBloc(mockGetSummary);
      },
      act: (bloc) => bloc.add(const HomeLoadRequested()),
      expect: () => [
        const HomeLoading(),
        isA<HomeLoaded>().having(
          (s) => s.summary.upcomingAppointments,
          'upcomingAppointments',
          2,
        ),
      ],
    );

    blocTest<HomeBloc, HomeState>(
      'émet [Loading, Error] quand getDashboardSummary échoue',
      build: () {
        when(() => mockGetSummary()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')),
        );
        return _makeBloc(mockGetSummary);
      },
      act: (bloc) => bloc.add(const HomeLoadRequested()),
      expect: () => [
        const HomeLoading(),
        isA<HomeError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );
  });
}
