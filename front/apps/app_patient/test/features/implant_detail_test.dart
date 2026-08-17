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

const _implantWithDeviceIdentification = ImplantItem(
  id: 'implant-4',
  brand: 'Implant molaire 36',
  manufacturer: 'Nobel Biocare',
  model: 'Replace Select Tapered',
  reference: '36214',
  lotNumber: 'NB-4471-22A',
  dimensions: 'Ø 4,3 mm · L 11,5 mm',
  material: 'Titane grade 4',
);

const _implantWithReferenceOnly = ImplantItem(
  id: 'implant-5',
  brand: 'Nobel Biocare',
  reference: '36214',
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

    testWidgets(
        "n'affiche pas le bloc « Identification du dispositif » si aucune "
        'donnée du dispositif', (tester) async {
      await tester.pumpWidget(buildPage(_implantWithFollowUp));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_detail_device_identification_card')),
        findsNothing,
      );
    });

    testWidgets(
        'affiche le bloc « Identification du dispositif » avec les six '
        'libellés, référence et n° de lot en mono', (tester) async {
      await tester.pumpWidget(buildPage(_implantWithDeviceIdentification));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_detail_device_identification_card')),
        findsOneWidget,
      );
      expect(find.text('Identification du dispositif'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2), findsOneWidget);

      expect(find.text('Fabricant'), findsOneWidget);
      expect(find.text('Nobel Biocare'), findsOneWidget);
      expect(find.text('Modèle'), findsOneWidget);
      expect(find.text('Replace Select Tapered'), findsOneWidget);
      expect(find.text('Référence'), findsOneWidget);
      expect(find.text('N° de lot'), findsOneWidget);
      expect(find.text('Dimensions'), findsOneWidget);
      expect(find.text('Ø 4,3 mm · L 11,5 mm'), findsOneWidget);
      expect(find.text('Matériau'), findsOneWidget);
      expect(find.text('Titane grade 4'), findsOneWidget);

      final reference = tester.widget<Text>(find.text('36214'));
      expect(reference.style?.fontFamily, 'monospace');
      final lotNumber = tester.widget<Text>(find.text('NB-4471-22A'));
      expect(lotNumber.style?.fontFamily, 'monospace');
    });

    testWidgets(
        "n'affiche que les lignes renseignées dans le bloc "
        '« Identification du dispositif »', (tester) async {
      await tester.pumpWidget(buildPage(_implantWithReferenceOnly));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('implant_detail_device_identification_card')),
        findsOneWidget,
      );
      expect(find.text('Référence'), findsOneWidget);
      expect(find.text('Fabricant'), findsNothing);
      expect(find.text('Modèle'), findsNothing);
      expect(find.text('N° de lot'), findsNothing);
      expect(find.text('Dimensions'), findsNothing);
      expect(find.text('Matériau'), findsNothing);
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
