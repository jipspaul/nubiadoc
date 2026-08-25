//! Tests widget : `PatientTagsSection` (#4041) — 0, 1, 3 étiquettes.
//! (#5115) — les étiquettes initiales viennent du chargement unique de la
//! fiche (plus de fetch au montage) ; un échec initial reste visible ; le
//! rechargement après mutation (ajout/suppression) reste local.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/patients/patients_page.dart';

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
  late _MockCreatePatientTag createTag;
  late _MockDeletePatientTag deleteTag;

  setUp(() {
    listTags = _MockListPatientTags();
    createTag = _MockCreatePatientTag();
    deleteTag = _MockDeletePatientTag();
    GetIt.instance.registerFactory<ListPatientTagsUseCase>(() => listTags);
    GetIt.instance.registerFactory<CreatePatientTagUseCase>(() => createTag);
    GetIt.instance.registerFactory<DeletePatientTagUseCase>(() => deleteTag);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection({List<PatientTag>? initialTags, String? initialError}) =>
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: PatientTagsSection(
            patientId: 'patient-1',
            initialTags: initialTags,
            initialError: initialError,
          ),
        ),
      );

  testWidgets('0 étiquette — affiche le message vide', (tester) async {
    await tester.pumpWidget(buildSection(initialTags: const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_tags_empty')), findsOneWidget);
    expect(find.byType(NubiaChip), findsNothing);
  });

  testWidgets('1 étiquette — affiche 1 chip', (tester) async {
    await tester.pumpWidget(buildSection(initialTags: [_tag('a')]));
    await tester.pumpAndSettle();

    expect(find.byType(NubiaChip), findsOneWidget);
    expect(find.text('Étiquette a'), findsOneWidget);
    expect(find.byKey(const Key('patient_tags_empty')), findsNothing);
  });

  testWidgets('3 étiquettes — affiche 3 chips', (tester) async {
    await tester.pumpWidget(
      buildSection(initialTags: [_tag('a'), _tag('b'), _tag('c')]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NubiaChip), findsNWidgets(3));
    expect(find.text('Étiquette a'), findsOneWidget);
    expect(find.text('Étiquette b'), findsOneWidget);
    expect(find.text('Étiquette c'), findsOneWidget);
  });

  testWidgets(
      'supprimer un chip appelle DeletePatientTagUseCase et recharge la '
      'liste', (tester) async {
    when(() => deleteTag('patient-1', 'tag-a'))
        .thenAnswer((_) async => const Right(null));
    when(() => listTags('patient-1')).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildSection(initialTags: [_tag('a')]));
    await tester.pumpAndSettle();

    // Le chip input expose un InkWell dédié sur l'icône « × » (onRemove),
    // distinct de l'InkWell englobant (onTap, non fourni ici) — cible précise.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('patient_tag_tag-a')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    verify(() => deleteTag('patient-1', 'tag-a')).called(1);
    // Rechargement local après mutation (pas au montage, #5115).
    verify(() => listTags('patient-1')).called(1);
  });

  // ── Échec visible (#5115) ────────────────────────────────────────────

  testWidgets('échec du chargement initial — message visible', (tester) async {
    await tester.pumpWidget(buildSection(initialError: 'Erreur réseau'));
    await tester.pumpAndSettle();

    expect(find.text('Erreur réseau'), findsOneWidget);
  });
}
