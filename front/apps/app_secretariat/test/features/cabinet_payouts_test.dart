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

final _toVerifyWithCashLead = CabinetPayout(
  id: 'po_mock_cash_lead',
  provider: PayoutProvider.stripe,
  amountCents: 184200,
  currency: 'EUR',
  arrivalDate: DateTime(2026, 8, 8),
  reconciliationStatus: PayoutReconciliationStatus.toVerify,
  internalPaymentsTotalCents: 202400,
  internalPayments: const [
    InternalPayment(
      amountCents: 18200,
      methodLabel: 'espèces',
      reconcilableByProvider: false,
    ),
  ],
);

Widget _wrap(CabinetPayoutsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<CabinetPayoutsBloc>.value(
        value: bloc,
        child: const CabinetPayoutsBody(),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const CabinetPayoutsLoadRequested());
  });

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

  group('volet de détail — actions de résolution (#5111)', () {
    testWidgets(
      'aucun virement sélectionné → pas d\'actions de rapprochement',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state)
            .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
        await tester.pumpWidget(_wrap(bloc));

        expect(
          find.byKey(const Key('payout_action_mark_reconciled')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('payout_action_flag_accountant')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'virement sélectionné → CTA "Marquer comme rapproché" (icône check) '
      'et bouton secondaire "Signaler au comptable"',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_reconciled, _toVerify],
            selectedPayoutId: _toVerify.id,
          ),
        );
        // `Scaffold` requis : le volet contient des boutons Material
        // (`FilledButton`/`OutlinedButton`) qui exigent un ancêtre `Material`.
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: Scaffold(
              body: BlocProvider<CabinetPayoutsBloc>.value(
                value: bloc,
                child: const CabinetPayoutsBody(),
              ),
            ),
          ),
        );

        expect(find.text('Marquer comme rapproché'), findsOneWidget);
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(find.text('Signaler au comptable'), findsOneWidget);
      },
    );

    testWidgets(
      'tap sur "Marquer comme rapproché" émet CabinetPayoutMarkedReconciled',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_reconciled, _toVerify],
            selectedPayoutId: _toVerify.id,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: Scaffold(
              body: BlocProvider<CabinetPayoutsBloc>.value(
                value: bloc,
                child: const CabinetPayoutsBody(),
              ),
            ),
          ),
        );

        await tester.tap(
          find.byKey(const Key('payout_action_mark_reconciled')),
        );
        await tester.pump();

        verify(
          () => bloc.add(
            any(
              that: isA<CabinetPayoutMarkedReconciled>()
                  .having((e) => e.id, 'id', _toVerify.id),
            ),
          ),
        ).called(1);
      },
    );

    testWidgets(
      'tap sur "Signaler au comptable" émet CabinetPayoutFlaggedToAccountant '
      'et affiche un feedback',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_reconciled, _toVerify],
            selectedPayoutId: _toVerify.id,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: Scaffold(
              body: BlocProvider<CabinetPayoutsBloc>.value(
                value: bloc,
                child: const CabinetPayoutsBody(),
              ),
            ),
          ),
        );

        await tester.tap(
          find.byKey(const Key('payout_action_flag_accountant')),
        );
        await tester.pump();

        verify(
          () => bloc.add(
            any(
              that: isA<CabinetPayoutFlaggedToAccountant>()
                  .having((e) => e.id, 'id', _toVerify.id),
            ),
          ),
        ).called(1);
        expect(find.text('Signalé au comptable.'), findsOneWidget);
      },
    );
  });

  group('encart « piste probable » (#5110)', () {
    testWidgets(
      'un paiement espèces non rapprochable par le prestataire égal à '
      "l'écart → encart affiché avec le mot exact",
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_toVerifyWithCashLead],
            selectedPayoutId: _toVerifyWithCashLead.id,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: Scaffold(
              body: BlocProvider<CabinetPayoutsBloc>.value(
                value: bloc,
                child: const CabinetPayoutsBody(),
              ),
            ),
          ),
        );

        expect(
          find.byKey(const Key('payout_probable_lead')),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Piste probable : le paiement en espèces de 182,00 € ne '
            "transite pas par Stripe — il explique exactement l'écart. À "
            'rapprocher de la caisse, pas du virement.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      "aucun paiement interne ne correspond à l'écart → encart absent",
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded([_toVerify], selectedPayoutId: _toVerify.id),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: Scaffold(
              body: BlocProvider<CabinetPayoutsBloc>.value(
                value: bloc,
                child: const CabinetPayoutsBody(),
              ),
            ),
          ),
        );

        expect(
          find.byKey(const Key('payout_probable_lead')),
          findsNothing,
        );
      },
    );

    testWidgets(
      "l'affichage de l'encart ne modifie aucun statut (indicatif seul)",
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_toVerifyWithCashLead],
            selectedPayoutId: _toVerifyWithCashLead.id,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: Scaffold(
              body: BlocProvider<CabinetPayoutsBloc>.value(
                value: bloc,
                child: const CabinetPayoutsBody(),
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('payout_probable_lead')), findsOneWidget);
        verifyNever(() => bloc.add(any()));
      },
    );
  });
}
