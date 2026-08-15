//! Test widget : encart « Actes de la séance » (#4952) — badge compteur
//! d'en-tête et pied « Total des actes enregistrés », même valeur que le
//! « Total séance » de la barre d'identité (#3402).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_page.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

class MockGetActsUseCase extends Mock implements GetActsUseCase {}

class MockFavoriteActsUseCase extends Mock implements FavoriteActsUseCase {}

const _sessionWithActs = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [
    ClinicalAct(
      id: 'act1',
      ccamCode: 'HBGD036',
      label: 'Détartrage deux arcades',
      amountCents: 100000,
    ),
    ClinicalAct(
      id: 'act2',
      ccamCode: 'HBMD028',
      label: 'Soin conservateur',
      amountCents: 46000,
    ),
    ClinicalAct(
      id: 'act3',
      ccamCode: 'HBQK389',
      label: 'Consultation de contrôle',
      amountCents: 0,
    ),
  ],
);

const _sessionWithoutActs = ClinicalSession(
  id: 's2',
  appointmentId: 'a2',
  status: 'in_progress',
  acts: [],
);

void main() {
  late MockConsultationCliniqueBloc bloc;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
    final favoriteActs = MockFavoriteActsUseCase();
    when(() => favoriteActs.list()).thenAnswer((_) async => []);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildBody(ClinicalSession session) {
    when(() => bloc.state)
        .thenReturn(ConsultationCliniqueLoaded(session: session));
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: ConsultationCliniqueLoaded(session: session),
    );
    return MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<ConsultationCliniqueBloc>.value(
          value: bloc,
          child: ConsultationCliniqueBody(consultationId: session.id),
        ),
      ),
    );
  }

  testWidgets(
      'en-tête « Actes de la séance » affiche un badge = nombre d\'actes',
      (tester) async {
    await tester.pumpWidget(buildBody(_sessionWithActs));
    await tester.pump();

    expect(find.text('Actes de la séance'), findsOneWidget);
    final badgeFinder =
        find.byKey(const Key('consultation_acts_count_badge'));
    expect(badgeFinder, findsOneWidget);
    expect(
      find.descendant(of: badgeFinder, matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets(
      'le pied affiche « Total des actes enregistrés » = somme des montants '
      '= Total séance de la barre', (tester) async {
    await tester.pumpWidget(buildBody(_sessionWithActs));
    await tester.pump();

    // 100000 + 46000 + 0 = 146000 centimes = 1 460,00 €.
    final expectedTotal =
        formatQuoteCents(146000, alwaysShowDecimals: true);

    final footerFinder = find.byKey(const Key('consultation_acts_total'));
    expect(footerFinder, findsOneWidget);
    expect(
      find.descendant(
          of: footerFinder,
          matching: find.text('Total des actes enregistrés')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: footerFinder, matching: find.text(expectedTotal)),
      findsOneWidget,
    );

    final sessionTotalFinder =
        find.byKey(const Key('consultation_session_total'));
    expect(
      find.descendant(of: sessionTotalFinder, matching: find.text(expectedTotal)),
      findsOneWidget,
    );
  });

  testWidgets(
      'aucun acte → état vide conservé, pas de pied de total, badge à 0',
      (tester) async {
    await tester.pumpWidget(buildBody(_sessionWithoutActs));
    await tester.pump();

    expect(find.byKey(const Key('consultation_empty')), findsOneWidget);
    expect(find.byKey(const Key('consultation_acts_total')), findsNothing);
    final badgeFinder =
        find.byKey(const Key('consultation_acts_count_badge'));
    expect(
      find.descendant(of: badgeFinder, matching: find.text('0')),
      findsOneWidget,
    );
  });
}
