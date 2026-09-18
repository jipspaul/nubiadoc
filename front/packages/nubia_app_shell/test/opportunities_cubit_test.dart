import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MockGetCabinetOpportunitiesUseCase extends Mock
    implements GetCabinetOpportunitiesUseCase {}

const _serverFailure = ServerFailure(message: 'Erreur serveur');

OpportunityCategory _category({
  required String kind,
  int count = 1,
  int totalAmountCents = 0,
}) =>
    OpportunityCategory(
      kind: kind,
      count: count,
      totalAmountCents: totalAmountCents,
      items: [
        for (var i = 0; i < count; i++)
          OpportunityItem(kind: kind, patientId: 'patient-$i'),
      ],
    );

void main() {
  group('OpportunitiesCubit', () {
    late MockGetCabinetOpportunitiesUseCase getOpportunities;

    setUp(() {
      getOpportunities = MockGetCabinetOpportunitiesUseCase();
    });

    blocTest<OpportunitiesCubit, OpportunitiesState>(
      'succès → OpportunitiesLoaded avec les catégories reçues',
      build: () {
        when(() => getOpportunities()).thenAnswer(
          (_) async => Right([
            _category(kind: 'quote_sent_no_response', totalAmountCents: 5000),
            _category(kind: 'birthday_today', count: 2),
          ]),
        );
        return OpportunitiesCubit(getOpportunities: getOpportunities);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const OpportunitiesLoading(),
        isA<OpportunitiesLoaded>().having(
          (s) => s.categories.map((c) => c.kind).toList(),
          'kinds',
          ['quote_sent_no_response', 'birthday_today'],
        ),
      ],
    );

    blocTest<OpportunitiesCubit, OpportunitiesState>(
      'échec réseau → OpportunitiesError (pas de liste vide silencieuse)',
      build: () {
        when(() => getOpportunities())
            .thenAnswer((_) async => const Left(_serverFailure));
        return OpportunitiesCubit(getOpportunities: getOpportunities);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const OpportunitiesLoading(),
        const OpportunitiesError(message: 'Erreur serveur'),
      ],
    );
  });
}
