import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/consents/consents_cubit.dart';
import 'package:app_patient/features/consents/consents_page.dart';

class MockConsentsCubit extends MockCubit<ConsentsState>
    implements ConsentsCubit {}

void main() {
  // #5208 — sous chaque titre de finalité, une phrase en langue claire dit
  // qui accède à quoi, pour quoi faire (le libellé seul n'informe pas).
  // Même exigence de couverture que _kConsentLabels (#3706) : les 6
  // finalités réellement émises par l'API doivent toutes avoir leur phrase,
  // testé ici en vérifiant que chacune s'affiche pour son purpose.
  testWidgets(
      'écran Consentements : chaque finalité documentée affiche sa phrase '
      "« qui accède à quoi, pour quoi faire »", (tester) async {
    const consents = [
      Consent(purpose: 'data_processing', granted: true),
      Consent(purpose: 'marketing', granted: false),
      Consent(purpose: 'soins', granted: true),
      Consent(purpose: 'partage_pharmacie', granted: false),
      Consent(purpose: 'partage_confrere', granted: false),
      Consent(purpose: 'ia_scribe', granted: false),
    ];

    final cubit = MockConsentsCubit();
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: const ConsentsLoaded(consents),
    );
    when(() => cubit.load()).thenAnswer((_) async {});

    GetIt.instance.registerFactory<ConsentsCubit>(() => cubit);
    addTearDown(() => GetIt.instance.reset());

    // Surface agrandie : la ligne méta statut daté (#5210) + la nouvelle
    // phrase de description allongent chaque carte, sinon les dernières
    // finalités sortent du cacheExtent et ne sont jamais construites.
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: ConsentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Conservation sécurisée de votre dossier chez un hébergeur agréé '
        'données de santé, en France.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Nouveautés du cabinet, offres de prévention. Sans effet sur vos '
        'rappels de rendez-vous.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Votre praticien enregistre les actes réalisés et son compte-rendu '
        'dans votre dossier médical.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Vos ordonnances sont transmises à la pharmacie que vous avez '
        'choisie, pour préparation avant votre passage.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        "Un autre praticien peut consulter votre dossier s'il vous prend "
        'en charge — second avis, urgence, remplacement.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Votre praticien peut dicter son compte-rendu ; une IA le met en '
        "forme. L'enregistrement n'est pas conservé.",
      ),
      findsOneWidget,
    );
  });

  // Une finalité non documentée ne doit pas faire planter l'écran : pas de
  // phrase affichée plutôt qu'une clé technique brute ou un texte inventé.
  testWidgets(
      'écran Consentements : une finalité inconnue n\'affiche aucune phrase',
      (tester) async {
    const consents = [
      Consent(purpose: 'purpose_non_documente', granted: false),
    ];

    final cubit = MockConsentsCubit();
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: const ConsentsLoaded(consents),
    );
    when(() => cubit.load()).thenAnswer((_) async {});

    GetIt.instance.registerFactory<ConsentsCubit>(() => cubit);
    addTearDown(() => GetIt.instance.reset());

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: ConsentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('consent_purpose_non_documente')),
    );
    expect(tile.subtitle, isNull);
  });
}
