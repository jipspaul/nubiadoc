import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
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
  });
}
