//! Tests : `IncomingRequestPage`/`IncomingRequestCubit` (#5258) — actions
//! Accepter/Refuser + encart de révocation sur l'écran « Décider » côté
//! invité, carte « Ajuster avant d'accepter » (#5257) et carte
//! « Ce qu'elle pourrait faire » (#5256).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/dependents/incoming_request_cubit.dart';
import 'package:app_patient/features/dependents/incoming_request_page.dart';

class _MockAcceptAccessRequest extends Mock
    implements AcceptAccessRequestUseCase {}

class _MockRefuseAccessRequest extends Mock
    implements RefuseAccessRequestUseCase {}

const _request = AccessRequest(
  id: 'ar-1',
  firstName: 'Julie',
  lastName: 'Martin',
  relationship: DependentRelationship.conjoint,
  status: AccessRequestStatus.envoyee,
  channel: AccessRequestChannel.email,
  grantedScope: {AccessRight.rendezVous, AccessRight.documents},
);

void main() {
  late _MockAcceptAccessRequest acceptUseCase;
  late _MockRefuseAccessRequest refuseUseCase;

  setUp(() {
    acceptUseCase = _MockAcceptAccessRequest();
    refuseUseCase = _MockRefuseAccessRequest();
    GetIt.instance.registerFactory<IncomingRequestCubit>(
      () => IncomingRequestCubit(
        accept: acceptUseCase,
        refuse: refuseUseCase,
      ),
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const IncomingRequestPage(request: _request),
      );

  group('widget', () {
    testWidgets(
        'affiche l\'en-tête « Une demande d\'accès » et le hero du demandeur (#5255)',
        (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Une demande d\'accès'), findsOneWidget);
      expect(
        find.text('Vous décidez de ce que vous autorisez'),
        findsOneWidget,
      );

      expect(find.byKey(const Key('incoming_request_requester_card')),
          findsOneWidget);
      expect(find.text('JM'), findsOneWidget);
      expect(
        find.text('Julie Martin souhaite gérer votre dossier'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Elle s\'est déclarée comme votre conjointe. Si vous ne la '
          'reconnaissez pas, refusez cette demande.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('affiche les CTA Accepter/Refuser et l\'encart de révocation',
        (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('accept_access_request_button')),
          findsOneWidget);
      expect(find.text('Accepter'), findsOneWidget);
      expect(find.byKey(const Key('refuse_access_request_button')),
          findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);
      expect(find.byKey(const Key('revocation_notice')), findsOneWidget);
      expect(
        find.text(
          'Vous pourrez retirer cet accès à tout moment, depuis '
          'Profil → Mes proches. Julie en sera informé.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Accepter déclenche accept() avec le périmètre courant',
        (tester) async {
      when(() => acceptUseCase(any())).thenAnswer(
        (_) async =>
            Right(_request.copyWithStatus(AccessRequestStatus.acceptee)),
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byKey(const Key('accept_access_request_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept_access_request_button')));
      await tester.pumpAndSettle();

      verify(() => acceptUseCase('ar-1')).called(1);
      expect(find.byKey(const Key('incoming_request_outcome')), findsOneWidget);
      expect(find.text('Acceptée'), findsOneWidget);
    });

    testWidgets('Refuser déclenche refuse()', (tester) async {
      when(() => refuseUseCase(any())).thenAnswer(
        (_) async =>
            Right(_request.copyWithStatus(AccessRequestStatus.refusee)),
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byKey(const Key('refuse_access_request_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('refuse_access_request_button')));
      await tester.pumpAndSettle();

      verify(() => refuseUseCase('ar-1')).called(1);
      expect(find.text('Refusée'), findsOneWidget);
    });

    testWidgets(
        'affiche la carte « Ce qu\'elle pourrait faire » avec les 2 lignes positives et les 2 négatives',
        (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rights_summary_card')), findsOneWidget);
      expect(find.text('Ce qu\'elle pourrait faire'), findsOneWidget);

      expect(
        find.textContaining('Voir, prendre et annuler'),
        findsOneWidget,
      );
      expect(find.textContaining('vos rendez-vous'), findsOneWidget);
      expect(find.textContaining('Consulter'), findsOneWidget);
      expect(
        find.textContaining('ordonnances, devis, factures'),
        findsOneWidget,
      );
      expect(
        find.textContaining('n\'aura'),
        findsOneWidget,
      );
      expect(
        find.textContaining('accès à vos messages avec le cabinet'),
        findsOneWidget,
      );
      expect(
        find.textContaining('ne pourra'),
        findsOneWidget,
      );
      expect(
        find.textContaining('modifier vos consentements'),
        findsOneWidget,
      );

      final card = find.byKey(const Key('rights_summary_card'));
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.check_circle)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.cancel)),
        findsNWidgets(2),
      );
    });

    testWidgets(
        'affiche la carte d\'ajustement avec les deux toggles initialisés ON',
        (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adjust_scope_card')), findsOneWidget);
      expect(find.text('Ajuster avant d\'accepter'), findsOneWidget);
      expect(find.text('Mes rendez-vous'), findsOneWidget);
      expect(find.text('Mes documents'), findsOneWidget);

      final rdvToggle = tester.widget<NubiaToggle>(
          find.byKey(const Key('adjust_scope_toggle_rendez_vous')));
      final docsToggle = tester.widget<NubiaToggle>(
          find.byKey(const Key('adjust_scope_toggle_documents')));
      expect(rdvToggle.value, isTrue);
      expect(docsToggle.value, isTrue);
    });

    testWidgets(
        'basculer un toggle restreint le périmètre envoyé à l\'acceptation',
        (tester) async {
      when(() => acceptUseCase(any())).thenAnswer(
        (_) async =>
            Right(_request.copyWithStatus(AccessRequestStatus.acceptee)),
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byKey(const Key('adjust_scope_toggle_documents')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('adjust_scope_toggle_documents')));
      await tester.pumpAndSettle();

      final docsToggle = tester.widget<NubiaToggle>(
          find.byKey(const Key('adjust_scope_toggle_documents')));
      expect(docsToggle.value, isFalse);

      await tester.ensureVisible(
          find.byKey(const Key('accept_access_request_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept_access_request_button')));
      await tester.pumpAndSettle();

      verify(() => acceptUseCase('ar-1')).called(1);
    });

    testWidgets('affiche le message d\'erreur si le refus échoue',
        (tester) async {
      when(() => refuseUseCase(any()))
          .thenAnswer((_) async => const Left(NetworkFailure()));

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byKey(const Key('refuse_access_request_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('refuse_access_request_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('incoming_request_error')), findsOneWidget);
      // Les CTA restent affichés : la demande est toujours `envoyee`.
      expect(find.byKey(const Key('refuse_access_request_button')),
          findsOneWidget);
    });
  });

  group('cubit', () {
    blocTest<IncomingRequestCubit, IncomingRequestState>(
      'accept() appelle le use case avec l\'id et émet mutating puis loaded',
      build: () => IncomingRequestCubit(
        accept: acceptUseCase,
        refuse: refuseUseCase,
      )..load(_request),
      setUp: () {
        when(() => acceptUseCase('ar-1')).thenAnswer(
          (_) async =>
              Right(_request.copyWithStatus(AccessRequestStatus.acceptee)),
        );
      },
      act: (cubit) => cubit.accept({AccessRight.rendezVous}),
      expect: () => [
        isA<IncomingRequestLoaded>()
            .having((s) => s.mutating, 'mutating', true)
            .having((s) => s.scope, 'scope', {AccessRight.rendezVous}),
        isA<IncomingRequestLoaded>()
            .having((s) => s.mutating, 'mutating', false)
            .having((s) => s.request.status, 'status',
                AccessRequestStatus.acceptee),
      ],
      verify: (_) => verify(() => acceptUseCase('ar-1')).called(1),
    );

    blocTest<IncomingRequestCubit, IncomingRequestState>(
      'setScopeRight() retire/ajoute un droit du périmètre ajusté',
      build: () => IncomingRequestCubit(
        accept: acceptUseCase,
        refuse: refuseUseCase,
      )..load(_request),
      act: (cubit) => cubit
        ..setScopeRight(AccessRight.documents, false)
        ..setScopeRight(AccessRight.rendezVous, false)
        ..setScopeRight(AccessRight.rendezVous, true),
      expect: () => [
        isA<IncomingRequestLoaded>()
            .having((s) => s.scope, 'scope', {AccessRight.rendezVous}),
        isA<IncomingRequestLoaded>().having((s) => s.scope, 'scope', <AccessRight>{}),
        isA<IncomingRequestLoaded>()
            .having((s) => s.scope, 'scope', {AccessRight.rendezVous}),
      ],
    );

    blocTest<IncomingRequestCubit, IncomingRequestState>(
      'refuse() en échec garde la demande et expose errorMessage',
      build: () => IncomingRequestCubit(
        accept: acceptUseCase,
        refuse: refuseUseCase,
      )..load(_request),
      setUp: () {
        when(() => refuseUseCase('ar-1'))
            .thenAnswer((_) async => const Left(NetworkFailure()));
      },
      act: (cubit) => cubit.refuse(),
      expect: () => [
        isA<IncomingRequestLoaded>()
            .having((s) => s.mutating, 'mutating', true),
        isA<IncomingRequestLoaded>()
            .having((s) => s.mutating, 'mutating', false)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull)
            .having(
                (s) => s.request.status, 'status', AccessRequestStatus.envoyee),
      ],
    );
  });
}

extension on AccessRequest {
  AccessRequest copyWithStatus(AccessRequestStatus status) => AccessRequest(
        id: this.id,
        firstName: firstName,
        lastName: lastName,
        relationship: relationship,
        status: status,
        channel: channel,
        grantedScope: grantedScope,
        sentAt: sentAt,
        revokedAt: revokedAt,
      );
}
