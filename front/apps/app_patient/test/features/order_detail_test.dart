import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/pharmacy_orders/order_detail_page.dart';
import 'package:app_patient/features/pharmacy_orders/orders_bloc.dart';

class MockPatientOrderDetailCubit extends MockCubit<PatientOrderDetailState>
    implements PatientOrderDetailCubit {}

void main() {
  group('PatientOrderDetailBody (widget)', () {
    testWidgets('état erreur → bouton Réessayer visible et relance le chargement',
        (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state)
          .thenReturn(const PatientOrderDetailError('Connexion perdue.'));
      when(() => cubit.reload()).thenAnswer((_) async {});

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      final errorWidget =
          tester.widget<NubiaErrorWidget>(find.byType(NubiaErrorWidget));
      expect(errorWidget.onRetry, isNotNull);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      verify(() => cubit.reload()).called(1);
    });

    PharmacyOrder makeReadyOrder({DateTime? readyAt, DateTime? pickupDeadline}) =>
        PharmacyOrder(
          id: 'o1',
          pharmacyId: 'p1',
          prescriptionId: 'rx1',
          status: PharmacyOrderStatus.ready,
          createdAt: DateTime.utc(2026, 8, 10),
          updatedAt: DateTime.utc(2026, 8, 10),
          readyAt: readyAt,
          pickupDeadline: pickupDeadline,
        );

    testWidgets(
        'commande ready avec readyAt → bandeau « Prête depuis » avec '
        'fallback 7 jours sous le QR', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
        PatientOrderDetailLoaded(
          makeReadyOrder(readyAt: DateTime(2026, 8, 16, 10, 4)),
          pickupToken: 'TOK123',
          pickupShortCode: 'K7M4-T2QX',
        ),
      );

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('pickup_deadline_banner')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('pickup_deadline_banner')),
          matching: find.textContaining('Prête depuis 10:04'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('pickup_deadline_banner')),
          matching: find.textContaining('à retirer sous 7 jours'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pickupDeadline fourni par le back → utilisé au lieu du fallback',
        (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
        PatientOrderDetailLoaded(
          makeReadyOrder(
            readyAt: DateTime(2026, 8, 16, 10, 4),
            pickupDeadline: DateTime(2026, 8, 19, 10, 4),
          ),
          pickupToken: 'TOK123',
          pickupShortCode: 'K7M4-T2QX',
        ),
      );

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('pickup_deadline_banner')),
          matching: find.textContaining('à retirer sous 3 jours'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pas ready → aucun bandeau, aucun QR', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
        PatientOrderDetailLoaded(
          PharmacyOrder(
            id: 'o1',
            pharmacyId: 'p1',
            prescriptionId: 'rx1',
            status: PharmacyOrderStatus.preparing,
            createdAt: DateTime.utc(2026, 8, 10),
            updatedAt: DateTime.utc(2026, 8, 10),
          ),
        ),
      );

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('pickup_deadline_banner')), findsNothing);
    });

    testWidgets('ready sans pickupToken (QR pas encore chargé) → pas de bandeau',
        (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
        PatientOrderDetailLoaded(
          makeReadyOrder(readyAt: DateTime(2026, 8, 16, 10, 4)),
        ),
      );

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('pickup_deadline_banner')), findsNothing);
    });
  });
}
