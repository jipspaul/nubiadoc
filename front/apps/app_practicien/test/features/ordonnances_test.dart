import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/ordonnances/ordonnances_bloc.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_event.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_state.dart';
import 'package:app_practicien/pro_config.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockCreatePrescriptionUseCase extends Mock
    implements CreatePrescriptionUseCase {}

class MockSignPrescriptionUseCase extends Mock
    implements SignPrescriptionUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _item = PrescriptionItem(
  label: 'Amoxicilline 500 mg',
  posology: '1 comprimé 3x/jour',
  duration: '7 jours',
  quantity: '21',
);

final _prescription = Prescription(
  id: 'presc-1',
  patientId: 'pat-1',
  items: [_item],
  status: PrescriptionStatus.draft,
  createdAt: DateTime(2026, 6, 19),
);

final _prescriptionSigned = Prescription(
  id: 'presc-1',
  patientId: 'pat-1',
  items: [_item],
  status: PrescriptionStatus.signed,
  createdAt: DateTime(2026, 6, 19),
);

OrdonnancesBloc _makeBloc({
  required MockCreatePrescriptionUseCase create,
  required MockSignPrescriptionUseCase sign,
}) =>
    OrdonnancesBloc(create: create, sign: sign);

Widget _wrap(OrdonnancesBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _OrdonnancesBodyDirect()),
      ),
    );

/// Direct rendering of bloc states for widget tests (avoids GetIt dependency).
class _OrdonnancesBodyDirect extends StatelessWidget {
  const _OrdonnancesBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdonnancesBloc, OrdonnancesState>(
      builder: (context, state) {
        if (state is OrdonnancesLoading) {
          return const Center(
            key: Key('ordonnances_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is OrdonnancesError) {
          return Center(
            key: const Key('ordonnances_error'),
            child: Text(state.message),
          );
        }
        if (state is OrdonnancesCreated) {
          return Column(
            children: [
              Text(
                key: const Key('ordonnances_created'),
                '${state.prescription.items.length} médicament(s)',
              ),
              ElevatedButton(
                key: const Key('sign_ordonnance_button'),
                onPressed: () => context
                    .read<OrdonnancesBloc>()
                    .add(OrdonnancesSignRequested(state.prescription.id)),
                child: const Text('Signer'),
              ),
            ],
          );
        }
        if (state is OrdonnancesSigned) {
          return const Center(
            key: Key('ordonnances_signed'),
            child: Text('Ordonnance signée'),
          );
        }
        return ElevatedButton(
          key: const Key('create_ordonnance_button'),
          onPressed: () => context.read<OrdonnancesBloc>().add(
                OrdonnancesCreateRequested(
                  patientId: 'pat-1',
                  items: [_item],
                ),
              ),
          child: const Text('Nouvelle ordonnance'),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc tests
// ---------------------------------------------------------------------------

void main() {
  late MockCreatePrescriptionUseCase mockCreate;
  late MockSignPrescriptionUseCase mockSign;

  setUpAll(() {
    registerFallbackValue(
      const PrescriptionItem(
        label: 'x',
        posology: 'y',
        duration: 'z',
        quantity: '1',
      ),
    );
  });

  setUp(() {
    mockCreate = MockCreatePrescriptionUseCase();
    mockSign = MockSignPrescriptionUseCase();
  });

  group('OrdonnancesBloc', () {
    blocTest<OrdonnancesBloc, OrdonnancesState>(
      'émet Loading puis Created après création réussie',
      build: () {
        when(
          () => mockCreate(
            patientId: any(named: 'patientId'),
            items: any(named: 'items'),
          ),
        ).thenAnswer((_) async => Right(_prescription));
        return _makeBloc(create: mockCreate, sign: mockSign);
      },
      act: (bloc) => bloc.add(
        OrdonnancesCreateRequested(patientId: 'pat-1', items: [_item]),
      ),
      expect: () => [
        const OrdonnancesLoading(),
        OrdonnancesCreated(_prescription),
      ],
    );

    blocTest<OrdonnancesBloc, OrdonnancesState>(
      'émet Loading puis Error si la création échoue',
      build: () {
        when(
          () => mockCreate(
            patientId: any(named: 'patientId'),
            items: any(named: 'items'),
          ),
        ).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return _makeBloc(create: mockCreate, sign: mockSign);
      },
      act: (bloc) => bloc.add(
        OrdonnancesCreateRequested(patientId: 'pat-1', items: [_item]),
      ),
      expect: () => [
        const OrdonnancesLoading(),
        const OrdonnancesError('Réseau indisponible'),
      ],
    );

    blocTest<OrdonnancesBloc, OrdonnancesState>(
      'émet Loading puis Signed après signature réussie',
      build: () {
        when(() => mockSign(any()))
            .thenAnswer((_) async => Right(_prescriptionSigned));
        return _makeBloc(create: mockCreate, sign: mockSign);
      },
      act: (bloc) => bloc.add(const OrdonnancesSignRequested('presc-1')),
      expect: () => [
        const OrdonnancesLoading(),
        OrdonnancesSigned(_prescriptionSigned),
      ],
    );

    blocTest<OrdonnancesBloc, OrdonnancesState>(
      'émet Loading puis Error si la signature échoue',
      build: () {
        when(() => mockSign(any())).thenAnswer(
          (_) async => Left(ServerFailure(
            message: 'Impossible de signer.',
            statusCode: 422,
          )),
        );
        return _makeBloc(create: mockCreate, sign: mockSign);
      },
      act: (bloc) => bloc.add(const OrdonnancesSignRequested('presc-1')),
      expect: () => [
        const OrdonnancesLoading(),
        const OrdonnancesError('Impossible de signer.'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('OrdonnancesPage (widget)', () {
    testWidgets('affiche le bouton créer à l\'état initial', (tester) async {
      final bloc = _makeBloc(create: mockCreate, sign: mockSign);
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('create_ordonnance_button')), findsOneWidget);
    });

    testWidgets('affiche la prescription créée avec bouton Signer',
        (tester) async {
      when(
        () => mockCreate(
          patientId: any(named: 'patientId'),
          items: any(named: 'items'),
        ),
      ).thenAnswer((_) async => Right(_prescription));
      final bloc = _makeBloc(create: mockCreate, sign: mockSign)
        ..add(OrdonnancesCreateRequested(patientId: 'pat-1', items: [_item]));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('ordonnances_created')), findsOneWidget);
      expect(find.byKey(const Key('sign_ordonnance_button')), findsOneWidget);
    });

    testWidgets('affiche la confirmation après signature', (tester) async {
      when(() => mockSign(any()))
          .thenAnswer((_) async => Right(_prescriptionSigned));
      final bloc = _makeBloc(create: mockCreate, sign: mockSign)
        ..add(const OrdonnancesSignRequested('presc-1'));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('ordonnances_signed')), findsOneWidget);
    });

    testWidgets('affiche l\'erreur en cas d\'échec', (tester) async {
      when(
        () => mockCreate(
          patientId: any(named: 'patientId'),
          items: any(named: 'items'),
        ),
      ).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = _makeBloc(create: mockCreate, sign: mockSign)
        ..add(OrdonnancesCreateRequested(patientId: 'pat-1', items: [_item]));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('ordonnances_error')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Gating test — destination cachée quand canAccessClinical = false
  // ---------------------------------------------------------------------------

  group('ProConfig — gating includeClinical', () {
    test('la destination Ordonnances requiert includeClinical', () {
      final ordonnancesDest = ProConfig.shellConfig.destinations.firstWhere(
        (d) => d.route == '/ordonnances',
      );
      expect(ordonnancesDest.requiresClinical, isTrue);
    });

    test(
        'aucune destination sans requiresClinical n\'est sur /ordonnances',
        () {
      final nonClinical = ProConfig.shellConfig.destinations
          .where((d) => !d.requiresClinical)
          .map((d) => d.route);
      expect(nonClinical, isNot(contains('/ordonnances')));
    });
  });
}
