//! Tests : `LabWorkOrdersPage`/`LabWorkOrdersBloc` (#4149) — les bons
//! s'affichent groupés par statut ; changer le statut d'un bon met à jour le
//! badge affiché. Golden test indisponible dans ce monorepo (aucune infra
//! golden_toolkit/goldens/ n'existe ailleurs) — substitué par ces tests
//! widget standard couvrant la même assertion comportementale.
//!
//! `pump()` à durée explicite plutôt que `pumpAndSettle()` (même convention
//! que `waiting_room_test.dart`/`stock_inventory_test.dart`). Ne PAS appeler
//! `bloc.close()` sur un Bloc injecté via `BlocProvider.value` dans un test
//! widget — `.value` ne prend pas possession du cycle de vie du bloc, un
//! `close()` explicite y bloque indéfiniment (cf. `stock_inventory_test.dart`).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/lab_work/lab_work_orders_bloc.dart';
import 'package:app_practicien/features/lab_work/lab_work_orders_event.dart';
import 'package:app_practicien/features/lab_work/lab_work_orders_page.dart';
import 'package:app_practicien/features/lab_work/lab_work_orders_state.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockListLabWorkOrdersUseCase extends Mock
    implements ListLabWorkOrdersUseCase {}

class MockUpdateLabWorkOrderStatusUseCase extends Mock
    implements UpdateLabWorkOrderStatusUseCase {}

class MockLabWorkOrdersBloc
    extends MockBloc<LabWorkOrdersEvent, LabWorkOrdersState>
    implements LabWorkOrdersBloc {}

const _sentOrder = LabWorkOrder(
  id: 'order-1',
  patientId: 'patient-1',
  labName: 'Labo Dentaire Alpha',
  purchasePriceCents: 15000,
  status: 'sent',
  sentAt: '2026-01-01T09:00:00Z',
);

const _fittedOrder = LabWorkOrder(
  id: 'order-2',
  patientId: 'patient-2',
  labName: 'Labo Dentaire Beta',
  purchasePriceCents: 20000,
  status: 'fitted',
  sentAt: '2026-01-02T09:00:00Z',
);

Widget _wrap(LabWorkOrdersBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<LabWorkOrdersBloc>.value(
        value: bloc,
        child: const LabWorkOrdersPage(),
      ),
    );

void main() {
  group('LabWorkOrdersPage (widget)', () {
    testWidgets(
        'le chargement affiche un squelette par colonne, pas un spinner '
        'centré (#5066)', (tester) async {
      // Surface agrandie : les 4 groupes + leurs cartes squelette dépassent
      // la hauteur de test par défaut (600px), ListView ne construit que ce
      // qui est visible.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final bloc = MockLabWorkOrdersBloc();
      when(() => bloc.state).thenReturn(const LabWorkOrdersLoading());
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NubiaSkeletonLoader), findsNWidgets(8));
      expect(
        find.byKey(const Key('lab_work_group_skeleton_sent')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lab_work_group_skeleton_try_in')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lab_work_group_skeleton_returned')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lab_work_group_skeleton_fitted')),
        findsOneWidget,
      );
    });

    testWidgets('les bons s\'affichent groupés par statut', (tester) async {
      final bloc = MockLabWorkOrdersBloc();
      when(() => bloc.state)
          .thenReturn(const LabWorkOrdersLoaded([_sentOrder, _fittedOrder]));
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('lab_work_group_sent')), findsOneWidget);
      expect(find.byKey(const Key('lab_work_group_fitted')), findsOneWidget);
      expect(
        find.byKey(const Key('lab_work_group_try_in')),
        findsNothing,
        reason: 'aucun groupe pour un statut sans bon',
      );
      expect(find.byKey(const Key('lab_work_order_order-1')), findsOneWidget);
      expect(find.byKey(const Key('lab_work_order_order-2')), findsOneWidget);

      // Le bon "fitted" est en fin de progression : pas de bouton Avancer.
      expect(
        find.byKey(const Key('lab_work_order_advance_order-2')),
        findsNothing,
      );
    });

    testWidgets(
        'le bouton "Nouveau bon" affiche un feedback "à venir" plutôt que '
        'de créer silencieusement un bon (#5065)', (tester) async {
      final bloc = MockLabWorkOrdersBloc();
      when(() => bloc.state)
          .thenReturn(const LabWorkOrdersLoaded([_sentOrder]));
      await tester.pumpWidget(_wrap(bloc));

      expect(
        find.byKey(const Key('lab_work_orders_new_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('lab_work_orders_new_button')));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('LabWorkOrdersBloc (via LabWorkOrdersPage, vrai Bloc)', () {
    testWidgets('changer le statut d\'un bon met à jour le badge affiché',
        (tester) async {
      final mockList = MockListLabWorkOrdersUseCase();
      final mockUpdateStatus = MockUpdateLabWorkOrderStatusUseCase();
      when(() => mockList()).thenAnswer((_) async => const Right([_sentOrder]));
      when(() => mockUpdateStatus('order-1', 'try_in'))
          .thenAnswer((_) async => const Right('try_in'));

      final bloc = LabWorkOrdersBloc(
        list: mockList,
        updateStatus: mockUpdateStatus,
      );
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('lab_work_order_order-1')),
          matching: find.text('Envoyé au labo'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('lab_work_order_advance_order-1')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('lab_work_order_order-1')),
          matching: find.text('Essayage'),
        ),
        findsOneWidget,
      );
      verify(() => mockUpdateStatus('order-1', 'try_in')).called(1);
    });

    testWidgets(
        'un rechargement échoué alors que des bons sont affichés conserve '
        'la liste et affiche une seule surface d\'erreur (#5067)',
        (tester) async {
      final mockList = MockListLabWorkOrdersUseCase();
      final mockUpdateStatus = MockUpdateLabWorkOrderStatusUseCase();
      var callCount = 0;
      when(() => mockList()).thenAnswer((_) async {
        callCount++;
        return callCount == 1
            ? const Right([_sentOrder])
            : const Left(_FakeFailure('Erreur réseau'));
      });

      final bloc = LabWorkOrdersBloc(
        list: mockList,
        updateStatus: mockUpdateStatus,
      );
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      bloc.add(const LabWorkOrdersLoadRequested());
      await tester.pump();

      // La liste reste affichée : pas de plein écran `NubiaErrorWidget`.
      expect(find.byKey(const Key('lab_work_order_order-1')), findsOneWidget);
      expect(find.byType(NubiaErrorWidget), findsNothing);

      // Une seule surface d'erreur : la snackbar.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Erreur réseau'), findsOneWidget);
    });
  });
}
