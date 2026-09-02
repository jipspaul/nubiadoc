import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
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

class MockListPatientTreatmentPlansUseCase extends Mock
    implements ListPatientTreatmentPlansUseCase {}

class MockGetUpcomingAppointmentsUseCase extends Mock
    implements GetUpcomingAppointmentsUseCase {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _MockHomeBloc extends MockBloc<HomeEvent, HomeState>
    implements HomeBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _summary = DashboardSummary(
  upcomingAppointments: 2,
  documentsToSign: 1,
  pendingPaymentsCents: 0,
  unreadMessages: 3,
);

const _emptySummary = DashboardSummary(
  upcomingAppointments: 0,
  documentsToSign: 0,
  pendingPaymentsCents: 0,
  unreadMessages: 0,
);

const _activePlan = PatientTreatmentPlan(
  id: 'plan-1',
  title: 'Plan orthodontique',
  status: 'in_progress',
  currentStep: 4,
  stepCount: 5,
  currentPhaseTitle: 'Pose de la couronne',
);

final _nextAppointment = Appointment(
  id: 'appt-1',
  cabinetId: 'cabinet-1',
  practitionerName: 'Dr Amélie Rousseau',
  practitionerSpecialty: 'Dentiste',
  startsAt: DateTime.now().toUtc().add(const Duration(days: 2)),
  duration: const Duration(minutes: 30),
  motif: 'Détartrage',
  status: AppointmentStatus.confirmed,
  cabinetAddress: 'Cabinet Nubia Opéra — 12 rue de la Paix, 75002 Paris',
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

HomeBloc _makeBloc(
  MockGetDashboardSummaryUseCase uc,
  MockListPatientTreatmentPlansUseCase listPlans,
  MockGetUpcomingAppointmentsUseCase getUpcoming,
) =>
    HomeBloc(
      getDashboardSummary: uc,
      listTreatmentPlans: listPlans,
      getUpcomingAppointments: getUpcoming,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const HomeLoadRequested());
  });

  late MockGetDashboardSummaryUseCase mockGetSummary;
  late MockListPatientTreatmentPlansUseCase mockListPlans;
  late MockGetUpcomingAppointmentsUseCase mockGetUpcoming;

  setUp(() {
    mockGetSummary = MockGetDashboardSummaryUseCase();
    mockListPlans = MockListPatientTreatmentPlansUseCase();
    mockGetUpcoming = MockGetUpcomingAppointmentsUseCase();
    when(() => mockListPlans())
        .thenAnswer((_) async => const Right(<PatientTreatmentPlan>[]));
    when(() => mockGetUpcoming())
        .thenAnswer((_) async => const Right(<Appointment>[]));
  });

  group('HomePage', () {
    testWidgets('affiche un indicateur de chargement en état initial',
        (tester) async {
      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
        'affiche la date du jour en sous-titre et « Bonjour Patient » par '
        'défaut quand non authentifié', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      final today = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now());
      final expectedSubtitle = today[0].toUpperCase() + today.substring(1);

      expect(find.text('Bonjour Patient'), findsOneWidget);
      expect(find.text(expectedSubtitle), findsOneWidget);
      expect(find.text('Voici votre espace santé'), findsNothing);
    });

    testWidgets('affiche « Bonjour <prénom> » quand authentifié',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      final authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(
          AuthSession(
            kind: UserKind.patient,
            userId: 'user-1',
            displayName: 'Camille',
          ),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bloc),
            BlocProvider<AuthCubit>(create: (_) => authCubit),
          ],
          child: const Scaffold(body: HomePage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bonjour Camille'), findsOneWidget);
    });

    testWidgets(
        'affiche « Bonjour Patient » quand authentifié avec un displayName '
        'vide (bootstrap de session pas encore peuplé)', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      final authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(
          AuthSession(
            kind: UserKind.patient,
            userId: 'user-1',
            displayName: '',
          ),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bloc),
            BlocProvider<AuthCubit>(create: (_) => authCubit),
          ],
          child: const Scaffold(body: HomePage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bonjour Patient'), findsOneWidget);
    });

    testWidgets('affiche les cartes de résumé en état loaded', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_summary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_content')), findsOneWidget);
      expect(find.byKey(const Key('card_devis')), findsOneWidget);
      expect(find.byKey(const Key('card_messages')), findsOneWidget);
    });

    testWidgets(
        'formate un gros montant avec séparateur de milliers (#6166)',
        (tester) async {
      const bigSummary = DashboardSummary(
        upcomingAppointments: 0,
        documentsToSign: 0,
        pendingPaymentsCents: 102443472,
        unreadMessages: 0,
      );
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(bigSummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text(NubiaMoney.formatCents(102443472)), findsOneWidget);
      expect(find.textContaining('1024434'), findsNothing);
    });

    testWidgets('la tuile-compteur « Prochain RDV » a disparu', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_summary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('card_appointments')), findsNothing);
    });

    testWidgets('affiche l\'état vide quand le résumé est vide',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      // La carte héros CTA (#5199) pousse l'état vide sous le pli sur la
      // petite surface de test : on scrolle avant de vérifier sa présence.
      await tester.ensureVisible(
        find.byKey(const Key('home_empty'), skipOffstage: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_empty')), findsOneWidget);
    });

    testWidgets('affiche un message d\'erreur en état error', (tester) async {
      when(() => mockGetSummary()).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Erreur réseau.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets(
        'affiche la carte « Mon suivi » quand un plan actif a des données '
        'de progression', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));
      when(() => mockListPlans())
          .thenAnswer((_) async => const Right([_activePlan]));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      // La carte héros CTA (#5199) pousse « Mon suivi » sous le pli sur la
      // petite surface de test : on scrolle avant de vérifier sa présence.
      await tester.ensureVisible(
        find.byKey(const Key('treatment_progress_card'), skipOffstage: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('treatment_progress_card')), findsOneWidget);
      expect(find.text('Plan de traitement'), findsOneWidget);
      expect(find.text('3 / 5 étapes'), findsOneWidget);
      expect(find.textContaining('Prochaine étape'), findsOneWidget);
    });

    testWidgets(
        'masque la carte « Mon suivi » quand aucun plan actif n\'a de '
        'données de progression', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_summary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('treatment_progress_card')), findsNothing);
    });

    testWidgets(
        'affiche la grille « Accès rapide » avec ses 4 tuiles de navigation',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Accès rapide'), findsOneWidget);
      expect(
        find.byKey(const Key('quick_access_prescriptions')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('quick_access_documents')), findsOneWidget);
      expect(find.byKey(const Key('quick_access_pharmacy')), findsOneWidget);
      expect(find.byKey(const Key('quick_access_dependents')), findsOneWidget);
      expect(find.byKey(const Key('quick_access_home_care')), findsOneWidget);
      expect(find.text('Mes ordonnances'), findsOneWidget);
      expect(find.text('Mes documents'), findsOneWidget);
      expect(find.text('Ma pharmacie'), findsOneWidget);
      expect(find.text('Mes proches'), findsOneWidget);
      expect(find.text('Soins à domicile'), findsOneWidget);
    });

    testWidgets('tuile « Soins à domicile » navigue vers /home-care',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      final authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: bloc),
                  BlocProvider<AuthCubit>(create: (_) => authCubit),
                ],
                child: const Scaffold(body: HomePage()),
              ),
            ),
            GoRoute(
              path: '/home-care',
              builder: (_, __) => const Scaffold(body: Text('Home care')),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('quick_access_home_care'), skipOffstage: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick_access_home_care')));
      await tester.pumpAndSettle();

      expect(find.text('Home care'), findsOneWidget);
    });

    testWidgets('tuile « Mes documents » navigue vers /documents',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      final authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: bloc),
                  BlocProvider<AuthCubit>(create: (_) => authCubit),
                ],
                child: const Scaffold(body: HomePage()),
              ),
            ),
            GoRoute(
              path: '/documents',
              builder: (_, __) => const Scaffold(body: Text('Documents')),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick_access_documents')));
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
    });

    testWidgets(
        'affiche le CTA « Prendre rendez-vous » quand aucun RDV à venir',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hero_appointment_cta')), findsOneWidget);
      expect(find.text('Prendre rendez-vous'), findsOneWidget);
    });

    testWidgets('masque le CTA héros quand un RDV est déjà prévu',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_summary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hero_appointment_cta')), findsNothing);
    });

    testWidgets(
        'affiche le détail du prochain RDV (date, praticien, motif, adresse) '
        'dans la carte héros', (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_summary));
      when(() => mockGetUpcoming())
          .thenAnswer((_) async => Right([_nextAppointment]));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hero_appointment_detail')), findsOneWidget);
      expect(find.byKey(const Key('hero_appointment_cta')), findsNothing);
      expect(find.textContaining('Dans'), findsOneWidget);
      expect(
        find.textContaining('Dr Amélie Rousseau · Détartrage'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cabinet Nubia Opéra'),
        findsOneWidget,
      );
      expect(find.text('Itinéraire'), findsOneWidget);
      expect(find.text('Préparer'), findsOneWidget);
    });

    testWidgets('bouton « Préparer » navigue vers /rdv/:id/prepare',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_summary));
      when(() => mockGetUpcoming())
          .thenAnswer((_) async => Right([_nextAppointment]));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      final authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: bloc),
                  BlocProvider<AuthCubit>(create: (_) => authCubit),
                ],
                child: const Scaffold(body: HomePage()),
              ),
            ),
            GoRoute(
              path: '/rdv/:id/prepare',
              builder: (_, state) => Scaffold(
                body: Text('Prepare ${state.pathParameters['id']}'),
              ),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('hero_prepare_button')));
      await tester.pumpAndSettle();

      expect(find.text('Prepare appt-1'), findsOneWidget);
    });

    testWidgets('tap sur le CTA héros navigue vers /appointments',
        (tester) async {
      when(() => mockGetSummary())
          .thenAnswer((_) async => const Right(_emptySummary));

      final bloc = _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      bloc.add(const HomeLoadRequested());

      final authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: bloc),
                  BlocProvider<AuthCubit>(create: (_) => authCubit),
                ],
                child: const Scaffold(body: HomePage()),
              ),
            ),
            GoRoute(
              path: '/appointments',
              builder: (_, __) => const Scaffold(body: Text('Appointments')),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('hero_appointment_cta')));
      await tester.pumpAndSettle();

      expect(find.text('Appointments'), findsOneWidget);
    });

    testWidgets('tap Réessayer dispatch HomeLoadRequested', (tester) async {
      final mockBloc = _MockHomeBloc();
      when(() => mockBloc.state).thenReturn(const HomeError('Erreur réseau.'));
      when(() => mockBloc.stream).thenAnswer((_) => const Stream.empty());

      final authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<HomeBloc>.value(value: mockBloc),
            BlocProvider<AuthCubit>(create: (_) => authCubit),
          ],
          child: const Scaffold(body: HomePage()),
        ),
      ));

      await tester.tap(find.text('Réessayer'));

      verify(() => mockBloc.add(const HomeLoadRequested())).called(1);
    });
  });

  group('HomeBloc', () {
    blocTest<HomeBloc, HomeState>(
      'émet [Loading, Loaded] quand getDashboardSummary réussit',
      build: () {
        when(() => mockGetSummary())
            .thenAnswer((_) async => const Right(_summary));
        return _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
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
        return _makeBloc(mockGetSummary, mockListPlans, mockGetUpcoming);
      },
      act: (bloc) => bloc.add(const HomeLoadRequested()),
      expect: () => [
        const HomeLoading(),
        isA<HomeError>().having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );
  });
}
