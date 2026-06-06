import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/account_repository.dart';
import 'package:nubia_patient/domain/usecases/account/get_coverage_use_case.dart';
import 'package:nubia_patient/domain/usecases/account/upload_coverage_card_use_case.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_bloc.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_event.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_state.dart';

class MockAccountRepository extends Mock implements AccountRepository {}

const _coverage = HealthCoverage(
  regime: HealthInsuranceRegime.regimeGeneral,
  insuranceName: 'MGEN',
  memberNumber: '12345',
  thirdPartyPayment: false,
  nssPartial: '2 91 03 …78',
);

void main() {
  late MockAccountRepository repository;
  late GetCoverageUseCase getCoverage;
  late UploadCoverageCardUseCase uploadCard;

  setUpAll(() {
    registerFallbackValue(CoverageCardSide.recto);
  });

  setUp(() {
    repository = MockAccountRepository();
    getCoverage = GetCoverageUseCase(repository);
    uploadCard = UploadCoverageCardUseCase(repository);
  });

  CoverageBloc buildBloc() => CoverageBloc(getCoverage, uploadCard);

  group('CoverageBloc — chargement', () {
    blocTest<CoverageBloc, CoverageState>(
      'émet Loading puis Loaded quand le repo retourne une couverture',
      build: () {
        when(() => repository.getCoverage())
            .thenAnswer((_) async => const Right(_coverage));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CoverageLoadRequested()),
      expect: () => [
        const CoverageLoading(),
        const CoverageLoaded(_coverage),
      ],
    );

    blocTest<CoverageBloc, CoverageState>(
      'émet Loading puis Error quand le repo retourne une failure',
      build: () {
        when(() => repository.getCoverage())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const CoverageLoadRequested()),
      expect: () => [
        const CoverageLoading(),
        const CoverageError('Erreur réseau. Vérifiez votre connexion.'),
      ],
    );
  });

  group('CoverageBloc — upload carte mutuelle', () {
    blocTest<CoverageBloc, CoverageState>(
      'émet CardUploading puis CardUploaded et appelle POST coverage/card',
      build: () {
        when(
          () => repository.uploadCoverageCard(
            filePath: any(named: 'filePath'),
            mimeType: any(named: 'mimeType'),
            side: any(named: 'side'),
          ),
        ).thenAnswer((_) async => const Right('doc-abc123'));
        return buildBloc();
      },
      seed: () => const CoverageLoaded(_coverage),
      act: (bloc) => bloc.add(const CoverageCardUploadRequested(
        filePath: '/tmp/card.jpg',
        mimeType: 'image/jpeg',
        side: CoverageCardSide.recto,
      )),
      expect: () => [
        const CoverageCardUploading(_coverage),
        const CoverageCardUploaded(coverage: _coverage, documentId: 'doc-abc123'),
      ],
      verify: (_) {
        verify(
          () => repository.uploadCoverageCard(
            filePath: '/tmp/card.jpg',
            mimeType: 'image/jpeg',
            side: CoverageCardSide.recto,
          ),
        ).called(1);
      },
    );

    blocTest<CoverageBloc, CoverageState>(
      'émet CardUploading puis CardUploadError quand le repo retourne une failure',
      build: () {
        when(
          () => repository.uploadCoverageCard(
            filePath: any(named: 'filePath'),
            mimeType: any(named: 'mimeType'),
            side: any(named: 'side'),
          ),
        ).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Erreur lors de l\'envoi de la carte.'),
          ),
        );
        return buildBloc();
      },
      seed: () => const CoverageLoaded(_coverage),
      act: (bloc) => bloc.add(const CoverageCardUploadRequested(
        filePath: '/tmp/card.jpg',
        mimeType: 'image/jpeg',
        side: CoverageCardSide.recto,
      )),
      expect: () => [
        const CoverageCardUploading(_coverage),
        const CoverageCardUploadError(
          coverage: _coverage,
          message: 'Erreur lors de l\'envoi de la carte.',
        ),
      ],
    );

    blocTest<CoverageBloc, CoverageState>(
      'ignore l\'upload si aucune couverture chargée',
      build: () => buildBloc(),
      act: (bloc) => bloc.add(const CoverageCardUploadRequested(
        filePath: '/tmp/card.jpg',
        mimeType: 'image/jpeg',
        side: CoverageCardSide.recto,
      )),
      expect: () => <CoverageState>[],
      verify: (_) {
        verifyNever(() => repository.uploadCoverageCard(
              filePath: any(named: 'filePath'),
              mimeType: any(named: 'mimeType'),
              side: any(named: 'side'),
            ));
      },
    );
  });

  group('GetCoverageUseCase', () {
    test('retourne la couverture du repository', () async {
      when(() => repository.getCoverage())
          .thenAnswer((_) async => const Right(_coverage));

      final result = await getCoverage();

      expect(result, const Right<Failure, HealthCoverage>(_coverage));
    });
  });
}
