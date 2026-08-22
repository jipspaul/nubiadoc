// #5259 — chaque use case délègue au port AccountRepository, à l'image des
// use cases existants (AddDependentUseCase/DeleteDependentUseCase).
import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

class MockAccountRepository extends Mock implements AccountRepository {}

void main() {
  late MockAccountRepository repo;

  const request = AccessRequest(
    id: 'ar-1',
    firstName: 'Jean',
    lastName: 'Dupont',
    relationship: DependentRelationship.conjoint,
    status: AccessRequestStatus.envoyee,
    channel: AccessRequestChannel.email,
    grantedScope: {AccessRight.rendezVous},
  );

  setUpAll(() {
    registerFallbackValue(DependentRelationship.autre);
    registerFallbackValue(AccessRequestChannel.email);
    registerFallbackValue(<AccessRight>{});
  });

  setUp(() => repo = MockAccountRepository());

  test('SendAccessRequestUseCase délègue firstName/lastName/relationship/'
      'channel/scope au repo', () async {
    when(() => repo.sendAccessRequest(
          firstName: 'Jean',
          lastName: 'Dupont',
          relationship: DependentRelationship.conjoint,
          channel: AccessRequestChannel.email,
          scope: {AccessRight.rendezVous},
          email: 'jean@example.com',
          phone: null,
        )).thenAnswer((_) async => const Right(request));

    final result = await SendAccessRequestUseCase(repo)(
      firstName: 'Jean',
      lastName: 'Dupont',
      relationship: DependentRelationship.conjoint,
      channel: AccessRequestChannel.email,
      scope: const {AccessRight.rendezVous},
      email: 'jean@example.com',
    );

    expect(result.getOrElse(() => throw StateError('doit être un Right')),
        request);
  });

  test('ResendAccessRequestUseCase délègue l\'id au repo', () async {
    when(() => repo.resendAccessRequest('ar-1'))
        .thenAnswer((_) async => const Right(request));

    await ResendAccessRequestUseCase(repo)('ar-1');

    verify(() => repo.resendAccessRequest('ar-1')).called(1);
  });

  test('CancelAccessRequestUseCase délègue l\'id au repo', () async {
    when(() => repo.cancelAccessRequest('ar-1'))
        .thenAnswer((_) async => const Right(null));

    await CancelAccessRequestUseCase(repo)('ar-1');

    verify(() => repo.cancelAccessRequest('ar-1')).called(1);
  });

  test('AcceptAccessRequestUseCase délègue l\'id au repo', () async {
    when(() => repo.acceptAccessRequest('ar-1'))
        .thenAnswer((_) async => const Right(request));

    await AcceptAccessRequestUseCase(repo)('ar-1');

    verify(() => repo.acceptAccessRequest('ar-1')).called(1);
  });

  test('RefuseAccessRequestUseCase délègue l\'id au repo', () async {
    when(() => repo.refuseAccessRequest('ar-1'))
        .thenAnswer((_) async => const Right(request));

    await RefuseAccessRequestUseCase(repo)('ar-1');

    verify(() => repo.refuseAccessRequest('ar-1')).called(1);
  });

  test('RevokeAccessUseCase délègue l\'id au repo, distinct de '
      'DeleteDependentUseCase (révocation côté invité, pas gestionnaire)',
      () async {
    when(() => repo.revokeAccess('ar-1'))
        .thenAnswer((_) async => const Right(null));

    await RevokeAccessUseCase(repo)('ar-1');

    verify(() => repo.revokeAccess('ar-1')).called(1);
  });

  test('propage le Failure du repo (ex: SendAccessRequestUseCase)', () async {
    when(() => repo.sendAccessRequest(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          relationship: any(named: 'relationship'),
          channel: any(named: 'channel'),
          scope: any(named: 'scope'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
        )).thenAnswer(
      (_) async => const Left(
        ServerFailure(message: 'Invitation refusée.', statusCode: 422),
      ),
    );

    final result = await SendAccessRequestUseCase(repo)(
      firstName: 'Jean',
      lastName: 'Dupont',
      relationship: DependentRelationship.autre,
      channel: AccessRequestChannel.sms,
      scope: const {},
    );

    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect((failure as ServerFailure).statusCode, 422),
      (_) => fail('doit être un Left'),
    );
  });
}
