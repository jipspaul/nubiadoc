//! Tests widget : `PatientTagsSection` (#4041) — 0, 1, 3 étiquettes.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_fiche.dart';

class _MockListPatientTags extends Mock implements ListPatientTagsUseCase {}

class _MockCreatePatientTag extends Mock implements CreatePatientTagUseCase {}

class _MockDeletePatientTag extends Mock implements DeletePatientTagUseCase {}

PatientTag _tag(String suffix) => PatientTag(
      id: 'tag-$suffix',
      label: 'Étiquette $suffix',
      color: '#94A3B8',
      createdBy: 'user-1',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late _MockListPatientTags listTags;

  setUp(() {
    listTags = _MockListPatientTags();
    GetIt.instance.registerFactory<ListPatientTagsUseCase>(() => listTags);
    GetIt.instance.registerFactory<CreatePatientTagUseCase>(
      () => _MockCreatePatientTag(),
    );
    GetIt.instance.registerFactory<DeletePatientTagUseCase>(
      () => _MockDeletePatientTag(),
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const PatientTagsSection(patientId: 'patient-1'),
        ),
      );

  testWidgets('0 étiquette — affiche le message vide', (tester) async {
    when(() => listTags('patient-1')).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_tags_empty')), findsOneWidget);
    expect(find.byType(NubiaChip), findsNothing);
  });

  testWidgets('1 étiquette — affiche 1 chip', (tester) async {
    when(() => listTags('patient-1'))
        .thenAnswer((_) async => Right([_tag('a')]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byType(NubiaChip), findsOneWidget);
    expect(find.text('Étiquette a'), findsOneWidget);
  });

  testWidgets('3 étiquettes — affiche 3 chips', (tester) async {
    when(() => listTags('patient-1')).thenAnswer(
      (_) async => Right([_tag('a'), _tag('b'), _tag('c')]),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byType(NubiaChip), findsNWidgets(3));
  });
}
