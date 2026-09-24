//! Tests widget : `CrOperatoireFormPage` (#7153) — chargement du brouillon
//! existant, autosave débouncé à la frappe sur une section, aperçu en
//! lecture seule, finalisation (verrouille l'édition).

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/cr_operatoire_form_page.dart';

class _MockGetConsultationCr extends Mock
    implements GetConsultationCrUseCase {}

class _MockSaveConsultationCr extends Mock
    implements SaveConsultationCrUseCase {}

class _MockFinalizeConsultationCr extends Mock
    implements FinalizeConsultationCrUseCase {}

void main() {
  late _MockGetConsultationCr getCr;
  late _MockSaveConsultationCr saveCr;
  late _MockFinalizeConsultationCr finalizeCr;

  setUpAll(() {
    registerFallbackValue(<CrSectionEntry>[]);
  });

  setUp(() {
    getCr = _MockGetConsultationCr();
    saveCr = _MockSaveConsultationCr();
    finalizeCr = _MockFinalizeConsultationCr();
    GetIt.instance
      ..registerFactory<GetConsultationCrUseCase>(() => getCr)
      ..registerFactory<SaveConsultationCrUseCase>(() => saveCr)
      ..registerFactory<FinalizeConsultationCrUseCase>(() => finalizeCr);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const CrOperatoireFormPage(consultationId: 'session-1'),
      );

  testWidgets(
      'charge le brouillon existant et pré-remplit la section sélectionnée',
      (tester) async {
    when(() => getCr('session-1')).thenAnswer(
      (_) async => const Right(ConsultationCr(
        sections: [
          CrSectionEntry(
            key: 'diagnostic',
            title: 'Diagnostic',
            content: 'Carie profonde 26',
          ),
        ],
        status: 'draft',
      )),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.text('Carie profonde 26'),
      findsOneWidget,
    );
  });

  testWidgets('la frappe déclenche un autosave débouncé de toutes les sections',
      (tester) async {
    when(() => getCr('session-1')).thenAnswer(
      (_) async => const Right(ConsultationCr(sections: [], status: 'draft')),
    );
    when(() => saveCr(
          consultationId: any(named: 'consultationId'),
          sections: any(named: 'sections'),
        )).thenAnswer(
      (_) async => const Right(ConsultationCr(sections: [], status: 'draft')),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('cr_section_field_diagnostic')),
      'Carie profonde 26',
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    final captured = verify(() => saveCr(
          consultationId: 'session-1',
          sections: captureAny(named: 'sections'),
        )).captured;
    expect(captured, hasLength(1));
    final sections = captured.first as List<CrSectionEntry>;
    final diagnostic = sections.firstWhere((s) => s.key == 'diagnostic');
    expect(diagnostic.content, 'Carie profonde 26');

    expect(find.textContaining('Enregistré automatiquement'), findsOneWidget);
  });

  testWidgets('l\'aperçu affiche uniquement les sections renseignées',
      (tester) async {
    when(() => getCr('session-1')).thenAnswer(
      (_) async => const Right(ConsultationCr(
        sections: [
          CrSectionEntry(
            key: 'chirurgie',
            title: 'Chirurgie',
            content: 'Extraction 38 sous anesthésie locale',
          ),
        ],
        status: 'draft',
      )),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cr_operatoire_preview_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cr_operatoire_preview_view')), findsOneWidget);
    expect(
      find.text('Extraction 38 sous anesthésie locale'),
      findsOneWidget,
    );
  });

  testWidgets('finaliser verrouille l\'édition des sections', (tester) async {
    when(() => getCr('session-1')).thenAnswer(
      (_) async => const Right(ConsultationCr(
        sections: [
          CrSectionEntry(
            key: 'diagnostic',
            title: 'Diagnostic',
            content: 'Carie profonde 26',
          ),
        ],
        status: 'draft',
      )),
    );
    when(() => saveCr(
          consultationId: any(named: 'consultationId'),
          sections: any(named: 'sections'),
        )).thenAnswer(
      (_) async => const Right(ConsultationCr(sections: [], status: 'draft')),
    );
    when(() => finalizeCr('session-1')).thenAnswer(
      (_) async => const Right(ConsultationCr(
        sections: [
          CrSectionEntry(
            key: 'diagnostic',
            title: 'Diagnostic',
            content: 'Carie profonde 26',
          ),
        ],
        status: 'finalized',
      )),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cr_operatoire_finalize_button')));
    await tester.pumpAndSettle();

    verify(() => finalizeCr('session-1')).called(1);
    expect(find.text('Finalisé'), findsOneWidget);

    final field = tester.widget<TextField>(
      find.byKey(const Key('cr_section_field_diagnostic')),
    );
    expect(field.readOnly, isTrue);
  });
}
