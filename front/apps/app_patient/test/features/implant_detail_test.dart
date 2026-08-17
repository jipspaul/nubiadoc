//! Tests : `ImplantDetailPage`/`ImplantDetailCubit` (#5334). Widget tests
//! couvrent le rendu (boutons d'action + bandeau lecture seule, texte au mot
//! près) ; tests cubit couvrent l'export/partage scopés à l'implant courant
//! — pas de test widget sur l'ouverture/le partage réels du lien, cf.
//! `openDocumentUrl`/`Share.share` jamais exercés au niveau widget ailleurs
//! dans ce monorepo (`implant_passport_test.dart`), seulement au niveau
//! cubit.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/implant_passport/implant_detail_cubit.dart';
import 'package:app_patient/features/implant_passport/implant_detail_page.dart';

class _MockExportImplantPassport extends Mock
    implements ExportImplantPassportUseCase {}

const _implant = ImplantItem(
  id: 'implant-1',
  brand: 'Nobel Biocare',
  lotNumber: 'LOT-42',
  placementDate: '2025-01-15',
  toothPosition: '36',
);

const _implantWithFollowUp = ImplantItem(
  id: 'implant-2',
  brand: 'Straumann',
  lastControlDate: '2026-07-04',
  nextControl: 'Mars 2027 · annuel',
);

const _implantWithLastControlOnly = ImplantItem(
  id: 'implant-3',
  brand: 'Straumann',
  lastControlDate: '2026-07-04',
);

const _implantNoPose = ImplantItem(
  id: 'implant-4',
  brand: 'Straumann',
);

const _implantWithPlacement = ImplantItem(
  id: 'implant-5',
  brand: 'Nobel Biocare',
  placementDate: '2026-03-12',
  practitioner: 'Dr Marc Lefèvre',
  office: 'Nubia Opéra, Paris 2ᵉ',
  prosthesis: 'Couronne céramo-métallique',
);

const _implantWithPlacementDateOnly = ImplantItem(
  id: 'implant-6',
  brand: 'Nobel Biocare',
  placementDate: '2026-03-12',
);

const _implantWithHero = ImplantItem(
  id: 'implant-7',
  brand: 'Nobel Biocare',
  toothPosition: '36',
  placementDate: '2025-01-15',
  manufacturer: 'Nobel Biocare',
  model: 'Replace Select',
);

void main() {
  late _MockExportImplantPassport exportUseCase;

  setUp(() {
    exportUseCase = _MockExportImplantPassport();
    GetIt.instance.registerFactory<ImplantDetailCubit>(
      () => ImplantDetailCubit(export: exportUseCase),
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage([ImplantItem implant = _implant]) => MaterialApp(
        theme: NubiaTheme.light,
        home: ImplantDetailPage(implant: implant),
      );

  group('widget', () {
    testWidgets('affiche les deux actions et le bandeau lecture seule',
        (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Exporter cette fiche'), findsOneWidget);
      expect(find.text('Partager avec un professionnel'), findsOneWidget);
      expect(
        find.text(
          'Ces informations viennent de votre dossier médical. '
          'Seul votre praticien peut les modifier.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('implant_detail_readonly_notice')),
        findsOneWidget,
      );
    });

    testWidgets(
        "n'affiche pas le bloc « Suivi recommandé » si aucune donnée de suivi",
        (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_detail_follow_up_card')),
        findsNothing,
      );
    });

    testWidgets(
        'affiche le dernier contrôle formaté et le prochain en émeraude',
        (tester) async {
      await tester.pumpWidget(buildPage(_implantWithFollowUp));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_detail_follow_up_card')),
        findsOneWidget,
      );
      expect(find.text('Suivi recommandé'), findsOneWidget);
      expect(find.text('4 juillet 2026'), findsOneWidget);

      final nextControlValue = tester.widget<Text>(find.text('Mars 2027 · annuel'));
      expect(nextControlValue.style?.color, NubiaColors.brand700);
    });

    testWidgets("n'affiche pas la ligne « Prochain » si nextControl est nul",
        (tester) async {
      await tester.pumpWidget(buildPage(_implantWithLastControlOnly));
      await tester.pumpAndSettle();

      expect(find.text('4 juillet 2026'), findsOneWidget);
      expect(find.text('Prochain'), findsNothing);
    });

    testWidgets("n'affiche pas le bloc « Pose » si aucune donnée de pose",
        (tester) async {
      await tester.pumpWidget(buildPage(_implantNoPose));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_detail_placement_card')),
        findsNothing,
      );
    });

    testWidgets('affiche le bloc « Pose » avec les quatre lignes au mot près',
        (tester) async {
      await tester.pumpWidget(buildPage(_implantWithPlacement));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_detail_placement_card')),
        findsOneWidget,
      );
      expect(find.text('Pose'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('12 mars 2026'), findsOneWidget);
      expect(find.text('Praticien'), findsOneWidget);
      expect(find.text('Dr Marc Lefèvre'), findsOneWidget);
      expect(find.text('Cabinet'), findsOneWidget);
      expect(find.text('Nubia Opéra, Paris 2ᵉ'), findsOneWidget);
      expect(find.text('Prothèse'), findsOneWidget);
      expect(find.text('Couronne céramo-métallique'), findsOneWidget);
    });

    testWidgets(
        "n'affiche que la ligne « Date » si les autres champs de pose sont nuls",
        (tester) async {
      await tester.pumpWidget(buildPage(_implantWithPlacementDateOnly));
      await tester.pumpAndSettle();

      expect(find.text('12 mars 2026'), findsOneWidget);
      expect(find.text('Praticien'), findsNothing);
      expect(find.text('Cabinet'), findsNothing);
      expect(find.text('Prothèse'), findsNothing);
    });

    testWidgets(
        'affiche le hero avec la vignette FDI, le nom anatomique et '
        'fabricant · modèle', (tester) async {
      await tester.pumpWidget(buildPage(_implantWithHero));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('implant_detail_hero')), findsOneWidget);
      expect(find.text('36'), findsOneWidget);
      expect(find.text('FDI'), findsOneWidget);
      expect(find.text('Molaire inférieure gauche'), findsOneWidget);
      expect(find.text('Nobel Biocare · Replace Select'), findsOneWidget);
    });

    testWidgets(
        'affiche la pill « En place depuis N mois » cohérente avec '
        'placementDate', (tester) async {
      await tester.pumpWidget(buildPage(_implantWithHero));
      await tester.pumpAndSettle();

      final expectedMonths =
          NubiaDate.monthsSince(_implantWithHero.placementDate!);
      expect(find.text('En place depuis $expectedMonths mois'), findsOneWidget);
    });

    testWidgets("n'affiche pas la pill d'ancienneté si placementDate est nul",
        (tester) async {
      await tester.pumpWidget(buildPage(_implantNoPose));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.textContaining('En place depuis'), findsNothing);
    });

    testWidgets("n'affiche pas la vignette FDI si toothPosition est nul",
        (tester) async {
      await tester.pumpWidget(buildPage(_implantWithFollowUp));
      await tester.pumpAndSettle();

      expect(find.text('FDI'), findsNothing);
    });
  });

  group('cubit', () {
    ImplantDetailCubit buildCubit() => ImplantDetailCubit(export: exportUseCase);

    test('exportImplant() résout l\'URL scopée à cet implant', () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Right('https://storage.example.com/implant-1.pdf'),
      );

      final cubit = buildCubit();
      await cubit.exportImplant('implant-1');

      final state = cubit.state as ImplantDetailUrlReady;
      expect(state.url, 'https://storage.example.com/implant-1.pdf');
      expect(state.action, ImplantDetailAction.export);
      verify(() => exportUseCase(implantId: 'implant-1')).called(1);
      await cubit.close();
    });

    test('shareImplant() résout l\'URL scopée à cet implant', () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Right('https://storage.example.com/implant-1.pdf'),
      );

      final cubit = buildCubit();
      await cubit.shareImplant('implant-1');

      final state = cubit.state as ImplantDetailUrlReady;
      expect(state.action, ImplantDetailAction.share);
      verify(() => exportUseCase(implantId: 'implant-1')).called(1);
      await cubit.close();
    });

    test('échec export → état d\'erreur avec le message du repository',
        () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Left(ServerFailure(
          message: "Le lien d'export a expiré, réessayez.",
          statusCode: 410,
        )),
      );

      final cubit = buildCubit();
      await cubit.exportImplant('implant-1');

      final state = cubit.state as ImplantDetailError;
      expect(state.message, "Le lien d'export a expiré, réessayez.");
      await cubit.close();
    });

    test('reset() repasse à l\'état neutre', () async {
      when(() => exportUseCase(implantId: 'implant-1')).thenAnswer(
        (_) async => const Right('https://storage.example.com/implant-1.pdf'),
      );

      final cubit = buildCubit();
      await cubit.exportImplant('implant-1');
      cubit.reset();

      expect(cubit.state, const ImplantDetailIdle());
      await cubit.close();
    });
  });
}
