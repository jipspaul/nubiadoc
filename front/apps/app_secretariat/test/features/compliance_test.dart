//! Tests : `ComplianceBloc`/`ComplianceItemRow`/`ComplianceAlertsCard`
//! (#7169/#7170) — chargement de l'échéancier, clôture en un tap (recharge
//! la liste), rendu de la ligne d'item (alerte/justificatif), et rendu de
//! la carte dashboard (squelette/vide/liste).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_secretariat/features/compliance/compliance_bloc.dart';
import 'package:app_secretariat/features/compliance/compliance_event.dart';
import 'package:app_secretariat/features/compliance/compliance_state.dart';
import 'package:app_secretariat/features/compliance/widgets/compliance_item_row.dart';
import 'package:app_secretariat/features/dashboard/compliance_alerts_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/widgets/compliance_alerts_card.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockListComplianceItemsUseCase extends Mock
    implements ListComplianceItemsUseCase {}

class MockCreateComplianceItemUseCase extends Mock
    implements CreateComplianceItemUseCase {}

class MockCompleteComplianceItemUseCase extends Mock
    implements CompleteComplianceItemUseCase {}

class MockAttachComplianceEvidenceUseCase extends Mock
    implements AttachComplianceEvidenceUseCase {}

class MockComplianceAlertsSummaryCubit
    extends MockCubit<ComplianceAlertsSummaryState>
    implements ComplianceAlertsSummaryCubit {}

const _overdueItem = ComplianceItem(
  id: 'item-1',
  kind: 'training',
  label: 'Formation gestes et soins d\'urgence',
  dueDate: '2026-01-01',
  status: 'pending',
  alertLevel: 'overdue',
  createdAt: '2025-12-01T09:00:00Z',
);

const _upcomingItem = ComplianceItem(
  id: 'item-2',
  kind: 'equipment_check',
  equipmentLabel: 'Autoclave n°1',
  label: 'Contrôle annuel autoclave',
  dueDate: '2026-10-01',
  status: 'pending',
  createdAt: '2026-01-02T09:00:00Z',
);

void main() {
  group('ComplianceBloc', () {
    blocTest<ComplianceBloc, ComplianceState>(
      'ComplianceLoadRequested réussi émet Loading puis Loaded',
      build: () {
        final listItems = MockListComplianceItemsUseCase();
        when(() => listItems())
            .thenAnswer((_) async => const Right([_overdueItem]));
        return ComplianceBloc(
          listItems: listItems,
          createItem: MockCreateComplianceItemUseCase(),
          completeItem: MockCompleteComplianceItemUseCase(),
          attachEvidence: MockAttachComplianceEvidenceUseCase(),
        );
      },
      act: (bloc) => bloc.add(const ComplianceLoadRequested()),
      expect: () => [
        const ComplianceLoading(),
        const ComplianceLoaded(items: [_overdueItem]),
      ],
    );

    blocTest<ComplianceBloc, ComplianceState>(
      'ComplianceLoadRequested en échec émet Loading puis Error',
      build: () {
        final listItems = MockListComplianceItemsUseCase();
        when(() => listItems())
            .thenAnswer((_) async => const Left(_FakeFailure('Erreur réseau')));
        return ComplianceBloc(
          listItems: listItems,
          createItem: MockCreateComplianceItemUseCase(),
          completeItem: MockCompleteComplianceItemUseCase(),
          attachEvidence: MockAttachComplianceEvidenceUseCase(),
        );
      },
      act: (bloc) => bloc.add(const ComplianceLoadRequested()),
      expect: () => [
        const ComplianceLoading(),
        const ComplianceError('Erreur réseau'),
      ],
    );

    blocTest<ComplianceBloc, ComplianceState>(
      'ComplianceCompleteRequested réussi recharge la liste',
      build: () {
        final listItems = MockListComplianceItemsUseCase();
        final completeItem = MockCompleteComplianceItemUseCase();
        var callCount = 0;
        when(() => listItems()).thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? const Right([_overdueItem, _upcomingItem])
              : const Right([_upcomingItem]);
        });
        when(() => completeItem('item-1'))
            .thenAnswer((_) async => const Right('done'));
        return ComplianceBloc(
          listItems: listItems,
          createItem: MockCreateComplianceItemUseCase(),
          completeItem: completeItem,
          attachEvidence: MockAttachComplianceEvidenceUseCase(),
        );
      },
      act: (bloc) async {
        bloc.add(const ComplianceLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ComplianceCompleteRequested('item-1'));
      },
      expect: () => [
        const ComplianceLoading(),
        const ComplianceLoaded(items: [_overdueItem, _upcomingItem]),
        const ComplianceLoaded(
          items: [_overdueItem, _upcomingItem],
          actionInProgress: true,
        ),
        const ComplianceLoading(),
        const ComplianceLoaded(items: [_upcomingItem]),
      ],
    );
  });

  group('ComplianceItemRow (widget)', () {
    testWidgets('affiche le libellé, le type et une alerte échue',
        (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ComplianceItemRow(item: _overdueItem),
        ),
      );

      expect(find.byKey(const Key('compliance_item_row_item-1')),
          findsOneWidget);
      expect(find.text('Formation gestes et soins d\'urgence'),
          findsOneWidget);
      expect(find.text('Échu'), findsOneWidget);
    });

    testWidgets('cliquer sur clôturer appelle le callback', (tester) async {
      var completed = false;
      await tester.pumpApp(
        Scaffold(
          body: ComplianceItemRow(
            item: _upcomingItem,
            onComplete: () => completed = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('compliance_item_complete_item-2')));
      await tester.pump();

      expect(completed, isTrue);
    });
  });

  group('ComplianceAlertsCard (widget)', () {
    testWidgets('affiche un squelette pendant le chargement', (tester) async {
      final cubit = MockComplianceAlertsSummaryCubit();
      when(() => cubit.state)
          .thenReturn(const ComplianceAlertsSummaryLoading());
      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<ComplianceAlertsSummaryCubit>.value(
              value: cubit, child: const ComplianceAlertsCard()),
        ),
      );

      expect(find.byKey(const Key('compliance_alerts_card_loading')),
          findsOneWidget);
    });

    testWidgets('affiche un message quand aucune alerte', (tester) async {
      final cubit = MockComplianceAlertsSummaryCubit();
      when(() => cubit.state).thenReturn(
          const ComplianceAlertsSummaryLoaded(alertingItems: []));
      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<ComplianceAlertsSummaryCubit>.value(
              value: cubit, child: const ComplianceAlertsCard()),
        ),
      );

      expect(find.byKey(const Key('compliance_alerts_card_empty')),
          findsOneWidget);
    });

    testWidgets('affiche les items en alerte', (tester) async {
      final cubit = MockComplianceAlertsSummaryCubit();
      when(() => cubit.state).thenReturn(
          const ComplianceAlertsSummaryLoaded(alertingItems: [_overdueItem]));
      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<ComplianceAlertsSummaryCubit>.value(
              value: cubit, child: const ComplianceAlertsCard()),
        ),
      );

      expect(find.byKey(const Key('compliance_item_row_item-1')),
          findsOneWidget);
    });
  });
}
