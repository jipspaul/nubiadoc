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

final _toVerify = CabinetPayout(
  id: 'po_mock_unmatched',
  provider: PayoutProvider.stripe,
  amountCents: 999999,
  currency: 'EUR',
  arrivalDate: DateTime(2026, 7, 30),
  reconciliationStatus: PayoutReconciliationStatus.toVerify,
  internalPaymentsTotalCents: 0,
);

void main() {
  late _MockCabinetPayoutsRepository repository;

  setUp(() => repository = _MockCabinetPayoutsRepository());

  CabinetPayoutsBloc build() =>
      CabinetPayoutsBloc(getPayouts: GetCabinetPayoutsUseCase(repository));

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
      CabinetPayoutsLoaded([_toVerify]),
      CabinetPayoutsLoaded([_toVerify], selectedPayoutId: _toVerify.id),
      CabinetPayoutsLoaded([_toVerify]),
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
    },
  );

  blocTest<CabinetPayoutsBloc, CabinetPayoutsState>(
    'signaler au comptable n\'émet aucun nouvel état (feedback porté par '
    "l'UI)",
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
      CabinetPayoutsLoaded([_toVerify]),
    ],
  );
}
