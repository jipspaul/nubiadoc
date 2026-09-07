/// #6704 — la prise de rendez-vous doit rester atteignable depuis l'accueil.
///
/// La recherche de praticien (carte + créneaux, `/appointments`) n'était
/// joignable que par l'icône loupe non libellée de la barre d'en-tête : ce
/// test fige le bouton explicite de l'accueil pour que le point d'entrée ne
/// puisse plus disparaître silencieusement.
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
import 'package:app_patient/session/auth_cubit.dart';

class MockGetDashboardSummaryUseCase extends Mock
    implements GetDashboardSummaryUseCase {}

class MockListPatientTreatmentPlansUseCase extends Mock
    implements ListPatientTreatmentPlansUseCase {}

class MockGetUpcomingAppointmentsUseCase extends Mock
    implements GetUpcomingAppointmentsUseCase {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

const _summary = DashboardSummary(
  upcomingAppointments: 0,
  documentsToSign: 0,
  pendingPaymentsCents: 0,
  unreadMessages: 0,
);

void main() {
  setUpAll(() => registerFallbackValue(const HomeLoadRequested()));

  testWidgets('l\'accueil expose un bouton « Prendre un rendez-vous »',
      (tester) async {
    final getSummary = MockGetDashboardSummaryUseCase();
    final listPlans = MockListPatientTreatmentPlansUseCase();
    final getUpcoming = MockGetUpcomingAppointmentsUseCase();
    when(() => getSummary()).thenAnswer((_) async => const Right(_summary));
    when(() => listPlans())
        .thenAnswer((_) async => const Right(<PatientTreatmentPlan>[]));
    when(() => getUpcoming())
        .thenAnswer((_) async => const Right(<Appointment>[]));

    final authCubit = MockAuthCubit();
    when(() => authCubit.state).thenReturn(const AuthUnauthenticated());

    final bloc = HomeBloc(
      getDashboardSummary: getSummary,
      listTreatmentPlans: listPlans,
      getUpcomingAppointments: getUpcoming,
    )..add(const HomeLoadRequested());

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

    expect(find.byKey(const Key('home_book_appointment_cta')), findsOneWidget);
    expect(find.text('Prendre un rendez-vous'), findsOneWidget);
  });
}
