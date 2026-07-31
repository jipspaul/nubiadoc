//! Tests : `CabinetPayoutsBody`/`CabinetPayoutsBloc` (#4129) — rapprochement
//! virements Stripe/GoCardless mockés vs paiements internes.
//!
//! `MockCabinetPayoutsBloc` (état fixé directement, comme
//! `cabinet_stats_test.dart`) — évite de faire tourner un vrai Bloc dans un
//! test widget.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/cabinet_payouts/cabinet_payouts_bloc.dart';
import 'package:app_secretariat/features/cabinet_payouts/cabinet_payouts_event.dart';
import 'package:app_secretariat/features/cabinet_payouts/cabinet_payouts_page.dart';
import 'package:app_secretariat/features/cabinet_payouts/cabinet_payouts_state.dart';

class MockCabinetPayoutsBloc
    extends MockBloc<CabinetPayoutsEvent, CabinetPayoutsState>
    implements CabinetPayoutsBloc {}

final _reconciled = CabinetPayout(
  id: 'po_mock_1a2b3c',
  provider: PayoutProvider.stripe,
  amountCents: 15000,
  currency: 'EUR',
  arrivalDate: DateTime(2026, 7, 28),
  reconciliationStatus: PayoutReconciliationStatus.reconciled,
  internalPaymentsTotalCents: 15000,
);

final _toVerify = CabinetPayout(
  id: 'po_mock_unmatched',
  provider: PayoutProvider.stripe,
  amountCents: 999999,
  currency: 'EUR',
  arrivalDate: DateTime(2026, 7, 30),
  reconciliationStatus: PayoutReconciliationStatus.toVerify,
  internalPaymentsTotalCents: 0,
);

Widget _wrap(CabinetPayoutsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<CabinetPayoutsBloc>.value(
        value: bloc,
        child: const CabinetPayoutsBody(),
      ),
    );

void main() {
  testWidgets(
    'un virement sans somme de paiements internes correspondante '
    'est marqué "à vérifier"',
    (tester) async {
      final bloc = MockCabinetPayoutsBloc();
      when(() => bloc.state)
          .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(Key('payout_${_reconciled.id}')), findsOneWidget);
      expect(find.byKey(Key('payout_${_toVerify.id}')), findsOneWidget);

      expect(find.byKey(const Key('payout_status_badge')), findsNWidgets(2));
      expect(find.text('À vérifier'), findsOneWidget);
      expect(find.text('Rapproché'), findsOneWidget);
      expect(find.textContaining('Écart'), findsOneWidget);
    },
  );

  testWidgets('aucun virement → état vide', (tester) async {
    final bloc = MockCabinetPayoutsBloc();
    when(() => bloc.state).thenReturn(const CabinetPayoutsLoaded([]));
    await tester.pumpWidget(_wrap(bloc));

    expect(find.byKey(const Key('cabinet_payouts_empty')), findsOneWidget);
  });
}
