import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/prescriptions/prescriptions_cubit.dart';
import 'package:app_patient/features/prescriptions/prescriptions_page.dart';

class MockPatientPharmacyRepository extends Mock
    implements PatientPharmacyRepository {}

class MockPrescriptionsCubit extends MockCubit<PrescriptionsState>
    implements PrescriptionsCubit {}

PatientPrescription prescription(
  String id, {
  PrescriptionStatus status = PrescriptionStatus.sent,
  String? documentId = 'doc-1',
}) =>
    PatientPrescription(
      id: id,
      status: status,
      documentId: documentId,
      createdAt: DateTime(2026, 9, 2),
    );

void main() {
  late MockPatientPharmacyRepository pharmacyRepo;
  late MockDocumentRepository documentRepo;

  setUp(() {
    pharmacyRepo = MockPatientPharmacyRepository();
    documentRepo = MockDocumentRepository();
  });

  PrescriptionsCubit buildCubit() => PrescriptionsCubit(
        listPrescriptions: ListMyPrescriptionsUseCase(pharmacyRepo),
        getDocumentSignedUrl: GetDocumentSignedUrlUseCase(documentRepo),
      );

  group('PrescriptionsCubit', () {
    blocTest<PrescriptionsCubit, PrescriptionsState>(
      'load() expose la liste servie par GET /v1/account/prescriptions',
      build: () {
        when(() => pharmacyRepo.listPrescriptions()).thenAnswer(
          (_) async => Right([prescription('rx1'), prescription('rx2')]),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<PrescriptionsLoading>(),
        isA<PrescriptionsLoaded>().having(
          (s) => s.prescriptions.map((p) => p.id),
          'ids',
          ['rx1', 'rx2'],
        ),
      ],
    );

    blocTest<PrescriptionsCubit, PrescriptionsState>(
      'load() en échec → PrescriptionsError',
      build: () {
        when(() => pharmacyRepo.listPrescriptions()).thenAnswer(
          (_) async => const Left(ServerFailure(message: 'Erreur serveur')),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [isA<PrescriptionsLoading>(), isA<PrescriptionsError>()],
    );

    blocTest<PrescriptionsCubit, PrescriptionsState>(
      'openDocument() récupère une URL signée',
      build: () {
        when(() => documentRepo.getSignedUrl('doc-1'))
            .thenAnswer((_) async => const Right('https://example/doc-1.pdf'));
        return buildCubit();
      },
      act: (cubit) => cubit.openDocument('doc-1'),
      expect: () => [
        isA<PrescriptionsDocumentReady>()
            .having((s) => s.url, 'url', 'https://example/doc-1.pdf'),
      ],
    );
  });

  group('PrescriptionsPage (widget)', () {
    testWidgets('liste les ordonnances avec leur statut', (tester) async {
      final cubit = MockPrescriptionsCubit();
      when(() => cubit.state).thenReturn(
        PrescriptionsLoaded([prescription('rx1')]),
      );
      whenListen(cubit, const Stream<PrescriptionsState>.empty());

      await tester.pumpApp(
        BlocProvider<PrescriptionsCubit>.value(
          value: cubit,
          child: const Scaffold(body: PrescriptionsBody()),
        ),
      );

      expect(find.byKey(const Key('prescription_rx1')), findsOneWidget);
      expect(find.text('Transmise à une pharmacie'), findsOneWidget);
    });

    testWidgets('aucune ordonnance → EmptyState', (tester) async {
      final cubit = MockPrescriptionsCubit();
      when(() => cubit.state).thenReturn(const PrescriptionsLoaded([]));
      whenListen(cubit, const Stream<PrescriptionsState>.empty());

      await tester.pumpApp(
        BlocProvider<PrescriptionsCubit>.value(
          value: cubit,
          child: const Scaffold(body: PrescriptionsBody()),
        ),
      );

      expect(find.byKey(const Key('prescriptions_empty')), findsOneWidget);
    });
  });
}
