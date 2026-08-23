import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
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
  // #5214 — l'écran Consentements doit afficher en pied de liste les
  // mentions RGPD obligatoires (responsable de traitement, hébergement HDS,
  // contact DPO), avec un lien mailto: pour le DPO.
  testWidgets(
      'écran Consentements : le pied de page affiche les mentions RGPD obligatoires',
      (tester) async {
    const consents = [
      Consent(purpose: 'soins', granted: true),
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

    expect(find.byKey(const Key('consents_footer')), findsOneWidget);
    expect(find.byIcon(Icons.gavel), findsOneWidget);
    expect(
      find.textContaining('Responsable de traitement', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('hébergeur agréé HDS', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Délégué à la protection des données',
        findRichText: true,
      ),
      findsOneWidget,
    );

    final richText = tester.widget<RichText>(
      find.byKey(const Key('consents_footer_text')),
    );
    final plainText = richText.text.toPlainText();
    expect(plainText, contains('dpo@nubia.fr'));

    bool foundMailtoLink = false;
    richText.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text == 'dpo@nubia.fr' &&
          span.recognizer is TapGestureRecognizer) {
        foundMailtoLink = true;
      }
      return true;
    });
    expect(foundMailtoLink, isTrue);
  });
}
