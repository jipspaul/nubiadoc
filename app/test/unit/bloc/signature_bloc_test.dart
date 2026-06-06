import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/signature_repository.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_bloc.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_event.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_state.dart';

class MockSignatureRepository extends Mock implements SignatureRepository {}

void main() {
  late MockSignatureRepository repository;

  setUp(() {
    repository = MockSignatureRepository();
  });

  group('SignatureBloc — confirmation', () {
    blocTest<SignatureBloc, SignatureState>(
      'passe à SignatureSigned après SignatureConfirmed depuis SignatureInProgress',
      build: () => SignatureBloc(repository),
      seed: () => const SignatureInProgress(),
      act: (bloc) => bloc.add(const SignatureConfirmed()),
      expect: () => [const SignatureSigned()],
    );

    blocTest<SignatureBloc, SignatureState>(
      'ignore SignatureConfirmed si l\'état n\'est pas SignatureInProgress',
      build: () => SignatureBloc(repository),
      seed: () => const SignaturePending(),
      act: (bloc) => bloc.add(const SignatureConfirmed()),
      expect: () => <SignatureState>[],
    );
  });

  group('SignatureBloc — annulation', () {
    blocTest<SignatureBloc, SignatureState>(
      'repasse à SignaturePending après SignatureCancelled depuis SignatureInProgress',
      build: () => SignatureBloc(repository),
      seed: () => const SignatureInProgress(),
      act: (bloc) => bloc.add(const SignatureCancelled()),
      expect: () => [const SignaturePending()],
    );
  });

  group('SignatureBloc — démarrage', () {
    blocTest<SignatureBloc, SignatureState>(
      'émet SignatureFailed si le repository retourne une erreur',
      build: () {
        when(
          () => repository.getSignatureUrl(
            documentId: any(named: 'documentId'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer((_) async => const Left(NetworkFailure()));
        return SignatureBloc(repository);
      },
      act: (bloc) => bloc.add(
        const SignatureStartRequested(
          documentId: 'doc-42',
          idempotencyKey: 'doc-42-123456',
        ),
      ),
      expect: () => [
        const SignatureInProgress(),
        const SignatureFailed('Erreur réseau. Vérifiez votre connexion.'),
      ],
    );
  });
}
