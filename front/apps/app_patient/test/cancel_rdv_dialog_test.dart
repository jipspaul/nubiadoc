import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/cancel_rdv_dialog.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockCancelAppointmentUseCase extends Mock
    implements CancelAppointmentUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _appt = Appointment(
  id: 'rdv-1',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  practitionerSpecialty: 'Dentiste',
  startsAt: DateTime(2026, 8, 15, 10, 0),
  duration: const Duration(minutes: 30),
  motif: 'Détartrage',
  status: AppointmentStatus.confirmed,
  cabinetAddress: '12 rue de la Paix, Paris',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildTestScaffold(CancelAppointmentUseCase useCase) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          key: const Key('open_dialog'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => CancelRdvDialog(
              appointment: _appt,
              cancelUseCase: useCase,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockCancelAppointmentUseCase mockCancel;

  setUpAll(() {
    registerFallbackValue(_appt);
  });

  setUp(() {
    mockCancel = MockCancelAppointmentUseCase();
  });

  testWidgets('ouverture dialog affiche champ raison et boutons',
      (tester) async {
    await tester.pumpWidget(_buildTestScaffold(mockCancel));

    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cancel_reason_field')), findsOneWidget);
    expect(find.byKey(const Key('confirm_cancel_button')), findsOneWidget);
    expect(find.byKey(const Key('keep_rdv_button')), findsOneWidget);
  });

  testWidgets('confirmer appelle CancelAppointmentUseCase avec le RDV',
      (tester) async {
    when(() => mockCancel(any()))
        .thenAnswer((_) async => Right(_appt));

    await tester.pumpWidget(_buildTestScaffold(mockCancel));
    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_cancel_button')));
    await tester.pumpAndSettle();

    verify(() => mockCancel(_appt)).called(1);
  });

  testWidgets('échec 409 too_late affiche snackbar Trop tard pour annuler',
      (tester) async {
    when(() => mockCancel(any())).thenAnswer(
      (_) async => const Left(
        ServerFailure(
          message: 'Annulation impossible.',
          statusCode: 409,
          code: 'too_late',
        ),
      ),
    );

    await tester.pumpWidget(_buildTestScaffold(mockCancel));
    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.text('Trop tard pour annuler'), findsOneWidget);
  });
}
