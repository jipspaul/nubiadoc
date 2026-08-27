//! Tests bloc : sélection + résolution d'écart du volet rapprochement
//! (#5111) — `CabinetPayoutSelected`, `CabinetPayoutMarkedReconciled`,
//! `CabinetPayoutFlaggedToAccountant`.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/cabinet_payouts/cabinet_payouts_bloc.dart';
import 'package:app_secretariat/features/cabinet_payouts/cabinet_payouts_event.dart';
import 'package:app_secretariat/features/cabinet_payouts/cabinet_payouts_state.dart';

class _MockCabinetPayoutsRepository extends Mock
    implements CabinetPayoutsRepository {}

/// Mois courant, calculé dynamiquement pour que les virements mock restent
/// dans le mois affiché par défaut par le sélecteur d'en-tête (#5101),
/// quelle que soit la date d'exécution des tests.
final _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
final _previousMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);

final _toVerify = CabinetPayout(
  id: 'po_mock_unmatched',
  provider: PayoutProvider.stripe,
  amountCents: 999999,
  currency: 'EUR',
  arrivalDate: DateTime(_currentMonth.year, _currentMonth.month, 15),
  reconciliationStatus: PayoutReconciliationStatus.toVerify,
  internalPaymentsTotalCents: 0,
);

final _fromPreviousMonth = CabinetPayout(
  id: 'po_mock_previous_month',
  provider: PayoutProvider.gocardless,
  amountCents: 42000,
  currency: 'EUR',
  arrivalDate: DateTime(_previousMonth.year, _previousMonth.month, 15),
  reconciliationStatus: PayoutReconciliationStatus.toVerify,
  internalPaymentsTotalCents: 42000,
);

void main() {
  late _MockCabinetPayoutsRepository repository;

  setUp(() {
    repository = _MockCabinetPayoutsRepository();
    when(() => repository.markReconciled(any()))
        .thenAnswer((_) async => const Right(unit));
    when(() => repository.flagToAccountant(any()))
        .thenAnswer((_) async => const Right(unit));
  });

  CabinetPayoutsBloc build() => CabinetPayoutsBloc(
        getPayouts: GetCabinetPayoutsUseCase(repository),
        markReconciled: MarkPayoutReconciledUseCase(repository),
        flagToAccountant: FlagPayoutToAccountantUseCase(repository),
      );

  blocTest<CabinetPayoutsBloc, CabinetPayoutsState>(
    'sélectionner un virement l\'affiche dans le volet ; le resélectionner '
    'le désélectionne',
    build: () {
      when(() => repository.getPayouts())
          .thenAnswer((_) async => Right([_toVerify]));
      return build();
    },
    act: (b) => b
      ..add(const CabinetPayoutsLoadRequested())
      ..add(CabinetPayoutSelected(_toVerify.id))
      ..add(CabinetPayoutSelected(_toVerify.id)),
    expect: () => [
      const CabinetPayoutsLoading(),
      CabinetPayoutsLoaded([_toVerify], selectedMonth: _currentMonth),
      CabinetPayoutsLoaded(
        [_toVerify],
        selectedPayoutId: _toVerify.id,
        selectedMonth: _currentMonth,
      ),
      CabinetPayoutsLoaded([_toVerify], selectedMonth: _currentMonth),
    ],
  );

  blocTest<CabinetPayoutsBloc, CabinetPayoutsState>(
    'marquer comme rapproché fait basculer reconciliationStatus '
    'sans changer la sélection',
    build: () {
      when(() => repository.getPayouts())
          .thenAnswer((_) async => Right([_toVerify]));
      return build();
    },
    act: (b) => b
      ..add(const CabinetPayoutsLoadRequested())
      ..add(CabinetPayoutSelected(_toVerify.id))
      ..add(CabinetPayoutMarkedReconciled(_toVerify.id)),
    verify: (b) {
      final state = b.state as CabinetPayoutsLoaded;
      expect(state.selectedPayoutId, _toVerify.id);
      expect(
        state.payouts.single.reconciliationStatus,
        PayoutReconciliationStatus.reconciled,
      );
      verify(() => repository.markReconciled(_toVerify.id)).called(1);
    },
  );

  blocTest<CabinetPayoutsBloc, CabinetPayoutsState>(
    "marquer comme rapproché n'affecte pas l'état si la persistance "
    'serveur échoue (#5969 : jamais de badge que le prochain refresh '
    'annulerait)',
    build: () {
      when(() => repository.getPayouts())
          .thenAnswer((_) async => Right([_toVerify]));
      when(() => repository.markReconciled(any())).thenAnswer(
        (_) async => const Left(ServerFailure(message: 'boom')),
      );
      return build();
    },
    act: (b) => b
      ..add(const CabinetPayoutsLoadRequested())
      ..add(CabinetPayoutMarkedReconciled(_toVerify.id)),
    verify: (b) {
      final state = b.state as CabinetPayoutsLoaded;
      expect(
        state.payouts.single.reconciliationStatus,
        PayoutReconciliationStatus.toVerify,
      );
    },
  );

  blocTest<CabinetPayoutsBloc, CabinetPayoutsState>(
    'signaler au comptable appelle la persistance serveur (#5969) sans '
    "émettre de nouvel état (feedback porté par l'UI)",
    build: () {
      when(() => repository.getPayouts())
          .thenAnswer((_) async => Right([_toVerify]));
      return build();
    },
    act: (b) => b
      ..add(const CabinetPayoutsLoadRequested())
      ..add(CabinetPayoutFlaggedToAccountant(_toVerify.id)),
    expect: () => [
      const CabinetPayoutsLoading(),
      CabinetPayoutsLoaded([_toVerify], selectedMonth: _currentMonth),
    ],
    verify: (_) {
      verify(() => repository.flagToAccountant(_toVerify.id)).called(1);
    },
  );

  blocTest<CabinetPayoutsBloc, CabinetPayoutsState>(
    'le sélecteur de mois filtre la liste sur le mois choisi et recharge '
    '(#5101)',
    build: () {
      when(() => repository.getPayouts()).thenAnswer(
        (_) async => Right([_toVerify, _fromPreviousMonth]),
      );
      return build();
    },
    act: (b) => b
      ..add(const CabinetPayoutsLoadRequested())
      ..add(CabinetPayoutsMonthChanged(_previousMonth)),
    expect: () => [
      const CabinetPayoutsLoading(),
      CabinetPayoutsLoaded([_toVerify], selectedMonth: _currentMonth),
      const CabinetPayoutsLoading(),
      CabinetPayoutsLoaded(
        [_fromPreviousMonth],
        selectedMonth: _previousMonth,
      ),
    ],
  );
}
