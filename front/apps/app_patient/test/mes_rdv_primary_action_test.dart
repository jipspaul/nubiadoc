// Issue #7805 — QA-20260927-R104-5 : l'action primaire (« Questionnaire
// médical », #5264) ne doit pas dépendre du statut du RDV — `isUpcoming`
// (appointment.dart) ne mêle plus `status == confirmed` à la position
// temporelle. Sans ce fix, 73 des 79 RDV « À venir » (tous `requested`)
// perdaient l'action primaire et ne portaient plus que le menu « ⋯ », qui
// ne propose jamais le questionnaire.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_page.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';

class _MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const MesRdvLoadRequested());
  });

  late _MockMesRdvBloc mockBloc;

  setUp(() async {
    mockBloc = _MockMesRdvBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<MesRdvBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  Appointment appointment({required AppointmentStatus status}) => Appointment(
        id: 'rdv-1',
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime.now().add(const Duration(days: 5)),
        duration: const Duration(minutes: 30),
        motif: 'Détartrage',
        status: status,
      );

  Future<void> pump(WidgetTester tester, Appointment appt) async {
    final state = MesRdvLoaded(upcoming: [appt], history: const []);
    whenListen(
      mockBloc,
      Stream<MesRdvState>.fromIterable([state]).asBroadcastStream(),
      initialState: state,
    );

    final router = GoRouter(
      initialLocation: '/mes-rdv',
      routes: [
        GoRoute(path: '/mes-rdv', builder: (_, __) => const MesRdvPage()),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'RDV requested à venir : l\'action primaire "Questionnaire médical" '
      'est affichée (pas seulement pour confirmed)', (tester) async {
    await pump(tester, appointment(status: AppointmentStatus.requested));

    expect(find.byKey(const Key('questionnaire_rdv-1')), findsOneWidget);
    expect(find.text('Questionnaire médical'), findsOneWidget);
  });

  testWidgets(
      'RDV confirmed à venir : l\'action primaire "Questionnaire médical" '
      'reste affichée (non régressé)', (tester) async {
    await pump(tester, appointment(status: AppointmentStatus.confirmed));

    expect(find.byKey(const Key('questionnaire_rdv-1')), findsOneWidget);
  });

  testWidgets(
      'Issue #8028 — le CTA "Questionnaire médical" expose son propre nœud '
      'Semantics bouton, et ne fusionne pas dans la carte ancêtre',
      (tester) async {
    final handle = SemanticsBinding.instance.ensureSemantics();

    await pump(tester, appointment(status: AppointmentStatus.confirmed));

    final ctaSemantics =
        tester.getSemantics(find.byKey(const Key('questionnaire_rdv-1')));
    expect(ctaSemantics.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(ctaSemantics.label, 'Questionnaire médical');

    // Sans #8028, cette annotation fusionnait dans le nœud de la carte
    // ancêtre : celui-ci devenait lui-même `button: true` avec un
    // `aria-label` concaténant tout le texte de la carte.
    final cardSemantics = tester.getSemantics(find.byType(NubiaCard).first);
    expect(cardSemantics.getSemanticsData().flagsCollection.isButton, isFalse);
    expect(cardSemantics.label, isNot(contains('Questionnaire médical')));

    handle.dispose();
  });
}
