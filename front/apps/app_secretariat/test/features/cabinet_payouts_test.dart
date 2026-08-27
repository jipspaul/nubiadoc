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

Widget _wrapPage(CabinetPayoutsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<CabinetPayoutsBloc>.value(
        value: bloc,
        child: const CabinetPayoutsPage(),
      ),
    );

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
      patientName: 'Léa Bernard',
      time: '10:02',
      amountCents: 18200,
      methodLabel: 'espèces',
      reconcilableByProvider: false,
    ),
  ],
);

final _withDailyInternalPayments = CabinetPayout(
  id: 'po_mock_daily',
  provider: PayoutProvider.stripe,
  amountCents: 202400,
  currency: 'EUR',
  arrivalDate: DateTime(2026, 8, 8),
  reconciliationStatus: PayoutReconciliationStatus.reconciled,
  internalPaymentsTotalCents: 202400,
  internalPayments: const [
    InternalPayment(
      patientName: 'Camille Moreau',
      time: '14:32',
      amountCents: 72500,
      methodLabel: 'Carte',
      reconcilableByProvider: true,
    ),
    InternalPayment(
      patientName: 'Léa Bernard',
      time: '10:02',
      amountCents: 18200,
      methodLabel: 'Espèces',
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
      expect(find.text('Écart'), findsOneWidget);
    },
  );

  testWidgets(
    'cellule Virement (design-v2, #5103) : date en titre, id en sous-ligne '
    'monospace, pastille provider',
    (tester) async {
      final bloc = MockCabinetPayoutsBloc();
      when(() => bloc.state).thenReturn(CabinetPayoutsLoaded([_reconciled]));
      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('28/07/2026'), findsOneWidget);
      expect(find.text(_reconciled.id), findsOneWidget);
      expect(find.text('STR'), findsOneWidget);

      final idText = tester.widget<Text>(find.text(_reconciled.id));
      expect(idText.style?.fontFamily, 'monospace');
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
        // Tableau à colonnes alignées (design-v2, point 6) + volet 400px :
        // ne tiennent que sur un écran large, la surface de test par défaut
        // (800px) est trop étroite une fois le volet ouvert.
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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

  group('comparaison Reçu en banque / Encaissé au cabinet (#5108)', () {
    testWidgets(
      'deux blocs côte à côte avec les libellés exacts et les montants',
      (tester) async {
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
          find.byKey(const Key('payout_comparison_bank')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('payout_comparison_cabinet')),
          findsOneWidget,
        );
        expect(find.text('Reçu en banque'), findsOneWidget);
        expect(find.text('Encaissé au cabinet'), findsOneWidget);
        // Le montant apparaît aussi dans la colonne « Montant reçu » du
        // tableau (design-v2, point 6) : on scope à la tuile de comparaison.
        expect(
          find.descendant(
            of: find.byKey(const Key('payout_comparison_bank')),
            matching: find.text('1 842,00 €'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('payout_comparison_cabinet')),
            matching: find.text('2 024,00 €'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'écart négatif → encart danger avec le montant absolu et le sens '
      '"la banque a reçu moins que ce qui a été encaissé"',
      (tester) async {
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
          find.byKey(const Key('payout_reconciliation_gap')),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Écart de 182,00 € — la banque a reçu moins que ce qui a été '
            'encaissé',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'écart positif → sens "la banque a reçu plus que ce qui a été '
      'encaissé"',
      (tester) async {
        final payoutBankReceivedMore = CabinetPayout(
          id: 'po_mock_bank_more',
          provider: PayoutProvider.stripe,
          amountCents: 202400,
          currency: 'EUR',
          arrivalDate: DateTime(2026, 8, 8),
          reconciliationStatus: PayoutReconciliationStatus.toVerify,
          internalPaymentsTotalCents: 184200,
        );
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [payoutBankReceivedMore],
            selectedPayoutId: payoutBankReceivedMore.id,
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
          find.textContaining(
            'Écart de 182,00 € — la banque a reçu plus que ce qui a été '
            'encaissé',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'virement rapproché → pas d\'encart d\'écart',
      (tester) async {
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_reconciled],
            selectedPayoutId: _reconciled.id,
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
          find.byKey(const Key('payout_reconciliation_gap')),
          findsNothing,
        );
      },
    );
  });

  group('encart « piste probable » (#5110)', () {
    testWidgets(
      'un paiement espèces non rapprochable par le prestataire égal à '
      "l'écart → encart affiché avec le mot exact",
      (tester) async {
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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

  group('bouton « Exporter (CSV) » en barre d\'outils (#5104)', () {
    testWidgets(
      'présent avec le libellé exact et l\'icône download',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state)
            .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
        await tester.pumpWidget(_wrapPage(bloc));

        expect(
          find.byKey(const Key('cabinet_payouts_export_csv')),
          findsOneWidget,
        );
        expect(find.text('Exporter (CSV)'), findsOneWidget);
        expect(find.byIcon(Icons.download), findsOneWidget);
      },
    );

    testWidgets('liste vide → bouton désactivé', (tester) async {
      final bloc = MockCabinetPayoutsBloc();
      when(() => bloc.state).thenReturn(const CabinetPayoutsLoaded([]));
      await tester.pumpWidget(_wrapPage(bloc));

      final button = tester.widget<NubiaButton>(
        find.byKey(const Key('cabinet_payouts_export_csv')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('en chargement → bouton désactivé', (tester) async {
      final bloc = MockCabinetPayoutsBloc();
      when(() => bloc.state).thenReturn(const CabinetPayoutsLoading());
      await tester.pumpWidget(_wrapPage(bloc));

      final button = tester.widget<NubiaButton>(
        find.byKey(const Key('cabinet_payouts_export_csv')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('virements présents → bouton activé', (tester) async {
      final bloc = MockCabinetPayoutsBloc();
      when(() => bloc.state)
          .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
      await tester.pumpWidget(_wrapPage(bloc));

      final button = tester.widget<NubiaButton>(
        find.byKey(const Key('cabinet_payouts_export_csv')),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('liste « Paiements internes du jour » (#5109)', () {
    testWidgets(
      'affiche le compteur, une ligne par paiement (moyen · heure, montant) '
      'et la mention "non rapprochable" pour les canaux physiques',
      (tester) async {
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_withDailyInternalPayments],
            selectedPayoutId: _withDailyInternalPayments.id,
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
          find.byKey(const Key('payout_internal_payments_section')),
          findsOneWidget,
        );
        expect(find.text('Paiements internes du jour'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);

        expect(find.text('Camille Moreau'), findsOneWidget);
        expect(find.text('Carte · 14:32'), findsOneWidget);
        expect(find.text('725,00 €'), findsOneWidget);

        expect(find.text('Léa Bernard'), findsOneWidget);
        expect(find.text('Espèces · 10:02'), findsOneWidget);
        expect(find.text('182,00 €'), findsOneWidget);

        expect(find.text('non rapprochable'), findsOneWidget);
      },
    );

    testWidgets(
      'aucun paiement interne ce jour-là → section absente',
      (tester) async {
        tester.view.physicalSize = const Size(1360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
          find.byKey(const Key('payout_internal_payments_section')),
          findsNothing,
        );
      },
    );
  });

  group('rangée de compteurs KPI en tête d\'écran (design-v2, point 4a)', () {
    testWidgets(
      'valeurs calculées depuis la liste : reçu, rapprochés, à vérifier, '
      'écart cumulé',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded(
            [_reconciled, _toVerify, _toVerifyWithCashLead],
          ),
        );
        await tester.pumpWidget(_wrap(bloc));

        final totalReceivedCents = _reconciled.amountCents +
            _toVerify.amountCents +
            _toVerifyWithCashLead.amountCents;
        final cumulativeGapCents =
            _toVerify.differenceCents + _toVerifyWithCashLead.differenceCents;

        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_received')),
            matching: find.text(NubiaMoney.formatCents(totalReceivedCents)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_received')),
            matching: find.text('virements reçus'),
          ),
          findsOneWidget,
        );

        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_reconciled')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_reconciled')),
            matching: find.text('virements rapprochés'),
          ),
          findsOneWidget,
        );

        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_to_verify')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_to_verify')),
            matching: find.text('à vérifier'),
          ),
          findsOneWidget,
        );

        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_cumulative_gap')),
            matching: find.text(NubiaMoney.formatCents(cumulativeGapCents)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_cumulative_gap')),
            matching: find.text('écart cumulé'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '« à vérifier » et « écart cumulé » en couleur danger',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state).thenReturn(
          CabinetPayoutsLoaded([_reconciled, _toVerifyWithCashLead]),
        );
        await tester.pumpWidget(_wrap(bloc));

        final tokens = NubiaTheme.light.extension<NubiaTokens>()!;

        final toVerifyValue = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_to_verify')),
            matching: find.text('1'),
          ),
        );
        expect(toVerifyValue.style?.color, tokens.dangerFg);

        final gapValue = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_cumulative_gap')),
            matching: find.text(
              NubiaMoney.formatCents(_toVerifyWithCashLead.differenceCents),
            ),
          ),
        );
        expect(gapValue.style?.color, tokens.dangerFg);

        final receivedValue = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('cabinet_payouts_kpi_received')),
            matching: find.text(
              NubiaMoney.formatCents(
                _reconciled.amountCents + _toVerifyWithCashLead.amountCents,
              ),
            ),
          ),
        );
        expect(receivedValue.style?.color, isNot(tokens.dangerFg));
      },
    );
  });

  group('bandeau « aucun compte connecté » (#5099)', () {
    testWidgets(
      'demoMode (défaut) → bandeau warning avec libellés exacts et bouton '
      '"Connecter Stripe"',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state)
            .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
        await tester.pumpWidget(_wrap(bloc));

        expect(
          find.byKey(const Key('cabinet_payouts_no_account_banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Aucun compte de paiement connecté.'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Les virements affichés sont des données de démonstration',
          ),
          findsOneWidget,
        );
        expect(find.text('Connecter Stripe'), findsOneWidget);
      },
    );

    testWidgets('demoMode == false → bandeau masqué', (tester) async {
      final bloc = MockCabinetPayoutsBloc();
      when(() => bloc.state)
          .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<CabinetPayoutsBloc>.value(
            value: bloc,
            child: const CabinetPayoutsBody(demoMode: false),
          ),
        ),
      );

      expect(
        find.byKey(const Key('cabinet_payouts_no_account_banner')),
        findsNothing,
      );
    });
  });

  group('sélecteur de mois en en-tête (#5101)', () {
    testWidgets(
      'tap chevron gauche décrémente le mois affiché et recharge',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state)
            .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
        await tester.pumpWidget(_wrapPage(bloc));

        await tester.tap(find.byKey(const Key('cabinet_payouts_month_prev')));
        await tester.pump();

        final now = DateTime.now();
        final previousMonth = DateTime(now.year, now.month - 1);
        verify(
          () => bloc.add(CabinetPayoutsMonthChanged(previousMonth)),
        ).called(1);
      },
    );

    testWidgets(
      'tap chevron droit incrémente le mois affiché et recharge',
      (tester) async {
        final bloc = MockCabinetPayoutsBloc();
        when(() => bloc.state)
            .thenReturn(CabinetPayoutsLoaded([_reconciled, _toVerify]));
        await tester.pumpWidget(_wrapPage(bloc));

        await tester.tap(find.byKey(const Key('cabinet_payouts_month_next')));
        await tester.pump();

        final now = DateTime.now();
        final nextMonth = DateTime(now.year, now.month + 1);
        verify(
          () => bloc.add(CabinetPayoutsMonthChanged(nextMonth)),
        ).called(1);
      },
    );
  });
}
