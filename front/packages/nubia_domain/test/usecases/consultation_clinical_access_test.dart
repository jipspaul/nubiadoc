import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

class _MockConsultationRepository extends Mock
    implements ConsultationRepository {}

class _MockSessionPort extends Mock implements SessionPort {}

void main() {
  group('GetConsultationContextUseCase — gating clinical', () {
    late _MockConsultationRepository repo;
    late _MockSessionPort session;
    late GetConsultationContextUseCase useCase;

    setUp(() {
      repo = _MockConsultationRepository();
      session = _MockSessionPort();
      useCase = GetConsultationContextUseCase(repo, session);
    });

    test('retourne ClinicalAccessDenied quand canAccessClinical est false',
        () async {
      when(() => session.canAccessClinical).thenReturn(false);

      final result = await useCase.call('consult-1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ClinicalAccessDenied>()),
        (_) => fail('devrait retourner Left'),
      );
      verifyNever(() => repo.getById(any()));
    });

    test('délègue au repository quand canAccessClinical est true', () async {
      when(() => session.canAccessClinical).thenReturn(true);
      final ctx = ConsultationContext(
        id: 'consult-1',
        cabinetId: 'cab-1',
        appointmentId: 'apt-1',
        patientId: 'pat-1',
        patientName: 'Jean Dupont',
        practitionerId: 'prac-1',
        startedAt: DateTime(2026),
        isCompleted: false,
      );
      when(() => repo.getById('consult-1')).thenAnswer((_) async => Right(ctx));

      final result = await useCase.call('consult-1');

      expect(result.isRight(), isTrue);
      verify(() => repo.getById('consult-1')).called(1);
    });
  });

  group('AddConsultationActUseCase — gating clinical', () {
    late _MockSessionPort session;

    setUp(() {
      session = _MockSessionPort();
    });

    test('retourne ClinicalAccessDenied quand canAccessClinical est false',
        () async {
      when(() => session.canAccessClinical).thenReturn(false);
      final repo = _MockClinicalSessionRepository();
      final useCase = AddConsultationActUseCase(repo, session);

      final result = await useCase.call(
        consultationId: 'c-1',
        ccamCode: 'HBMD035',
        label: 'Extraction dentaire',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ClinicalAccessDenied>()),
        (_) => fail('devrait retourner Left'),
      );
    });
  });

  group('CompleteConsultationUseCase — gating clinical', () {
    late _MockSessionPort session;

    setUp(() {
      session = _MockSessionPort();
    });

    test('retourne ClinicalAccessDenied quand canAccessClinical est false',
        () async {
      when(() => session.canAccessClinical).thenReturn(false);
      final repo = _MockClinicalSessionRepository();
      final useCase = CompleteConsultationUseCase(repo, session);

      final result = await useCase.call('c-1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ClinicalAccessDenied>()),
        (_) => fail('devrait retourner Left'),
      );
    });
  });
}

class _MockClinicalSessionRepository extends Mock
    implements ClinicalSessionRepository {}
