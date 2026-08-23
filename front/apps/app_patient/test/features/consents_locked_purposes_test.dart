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
  // #5205 — soins et data_processing (base légale du service) doivent être
  // présentées comme non modifiables (bascule verrouillée), pas au même
  // rang qu'une finalité librement révocable comme le marketing.
  const consents = [
    Consent(purpose: 'soins', granted: true),
    Consent(purpose: 'data_processing', granted: true),
    Consent(purpose: 'marketing', granted: false),
  ];

  Future<MockConsentsCubit> pumpConsentsPage(WidgetTester tester) async {
    final cubit = MockConsentsCubit();
    whenListen(
      cubit,
      const Stream<ConsentsState>.empty(),
      initialState: const ConsentsLoaded(consents),
    );
    when(() => cubit.load()).thenAnswer((_) async {});
    when(() => cubit.toggle(any(), any())).thenAnswer((_) async {});

    GetIt.instance.registerFactory<ConsentsCubit>(() => cubit);
    addTearDown(() => GetIt.instance.reset());

    tester.view.physicalSize = const Size(800, 2400);
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
    return cubit;
  }

  testWidgets(
      'écran Consentements : soins et data_processing sont dans la section '
      '« Nécessaire au service » avec leur base légale', (tester) async {
    await pumpConsentsPage(tester);

    expect(find.byKey(const Key('consents_locked_section')), findsOneWidget);
    expect(find.text('Nécessaire au service'), findsOneWidget);
    expect(find.text('Non modifiable'), findsOneWidget);

    expect(find.text('Requis pour être soigné'), findsOneWidget);
    expect(find.text('Base légale : exécution du contrat'), findsOneWidget);

    final soinsSwitch = tester.widget<Switch>(
      find.byKey(const Key('consent_soins')),
    );
    expect(soinsSwitch.value, isTrue);
    expect(soinsSwitch.onChanged, isNull);

    final dataProcessingSwitch = tester.widget<Switch>(
      find.byKey(const Key('consent_data_processing')),
    );
    expect(dataProcessingSwitch.value, isTrue);
    expect(dataProcessingSwitch.onChanged, isNull);
  });

  testWidgets(
      'écran Consentements : taper la bascule verrouillée ne déclenche '
      'aucun appel toggle()', (tester) async {
    final cubit = await pumpConsentsPage(tester);

    await tester.tap(find.byKey(const Key('consent_soins')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('consent_data_processing')));
    await tester.pump();

    verifyNever(() => cubit.toggle(any(), any()));
  });

  testWidgets(
      'écran Consentements : les autres finalités restent basculables',
      (tester) async {
    final cubit = await pumpConsentsPage(tester);

    expect(find.byKey(const Key('consent_marketing')), findsOneWidget);
    final marketingSwitch = tester.widget<Switch>(
      find.byKey(const Key('consent_marketing')),
    );
    expect(marketingSwitch.onChanged, isNotNull);

    await tester.tap(find.byKey(const Key('consent_marketing')));
    await tester.pump();

    verify(() => cubit.toggle('marketing', true)).called(1);
  });
}
