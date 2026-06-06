import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/dashboard_repository.dart';
import 'package:nubia_patient/domain/usecases/dashboard/get_dashboard_summary_use_case.dart';
import 'package:nubia_patient/presentation/features/home/bloc/dashboard_bloc.dart';

class MockGetDashboardSummaryUseCase extends Mock
    implements GetDashboardSummaryUseCase {}

const _summary = DashboardSummary(
  upcomingAppointments: 2,
  documentsToSign: 1,
  pendingPaymentsCents: 38000,
  unreadMessages: 3,
  pendingQuestionnaires: 0,
);

void main() {
  late MockGetDashboardSummaryUseCase useCase;

  setUp(() {
    useCase = MockGetDashboardSummaryUseCase();
  });

  blocTest<DashboardBloc, DashboardState>(
    'émet [DashboardLoading, DashboardLoaded] quand le use case réussit',
    build: () {
      when(() => useCase()).thenAnswer((_) async => const Right(_summary));
      return DashboardBloc(useCase);
    },
    act: (bloc) => bloc.add(const DashboardLoadRequested()),
    expect: () => [
      const DashboardLoading(),
      const DashboardLoaded(_summary),
    ],
  );

  blocTest<DashboardBloc, DashboardState>(
    'émet [DashboardLoading, DashboardError] quand le use case échoue',
    build: () {
      when(() => useCase())
          .thenAnswer((_) async => const Left(NetworkFailure()));
      return DashboardBloc(useCase);
    },
    act: (bloc) => bloc.add(const DashboardLoadRequested()),
    expect: () => [
      const DashboardLoading(),
      const DashboardError('Erreur réseau. Vérifiez votre connexion.'),
    ],
  );
}
