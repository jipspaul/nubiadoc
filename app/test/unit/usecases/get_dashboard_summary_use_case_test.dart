import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/dashboard_repository.dart';
import 'package:nubia_patient/domain/usecases/dashboard/get_dashboard_summary_use_case.dart';

class MockDashboardRepository extends Mock implements DashboardRepository {}

void main() {
  late MockDashboardRepository repository;
  late GetDashboardSummaryUseCase useCase;

  setUp(() {
    repository = MockDashboardRepository();
    useCase = GetDashboardSummaryUseCase(repository);
  });

  const summary = DashboardSummary(
    upcomingAppointments: 2,
    documentsToSign: 1,
    pendingPaymentsCents: 38000,
    unreadMessages: 3,
    pendingQuestionnaires: 0,
  );

  test('returns DashboardSummary on success', () async {
    when(() => repository.getSummary())
        .thenAnswer((_) async => const Right(summary));

    final result = await useCase();

    expect(result, const Right<Failure, DashboardSummary>(summary));
    verify(() => repository.getSummary()).called(1);
  });

  test('returns Failure when repository fails', () async {
    when(() => repository.getSummary())
        .thenAnswer((_) async => const Left(NetworkFailure()));

    final result = await useCase();

    expect(result.isLeft(), isTrue);
  });
}
