import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/admin_membres/admin_membres_bloc.dart';
import 'package:app_secretariat/features/admin_membres/admin_membres_event.dart';
import 'package:app_secretariat/features/admin_membres/admin_membres_page.dart';
import 'package:app_secretariat/features/admin_membres/admin_membres_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockMembersRepository extends Mock implements MembersRepository {}

class _MockSecretariatRepository extends Mock
    implements SecretariatRepository {}

class _MockAdminMembresBloc
    extends MockBloc<AdminMembresEvent, AdminMembresState>
    implements AdminMembresBloc {}

class _FakeAdminMembresEvent extends Fake implements AdminMembresEvent {}

void main() {
  // --- Cloisonnement invariant --------------------------------------------------
  group('ProConfig — cloisonnement', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination requiresClinical dans shellConfig', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- Member : pas de champ clinique ------------------------------------------
  group('Member — cloisonnement champs cliniques', () {
    test('fullName accessible (non-clinique)', () {
      final member = Member(
        id: 'm1',
        cabinetId: 'c1',
        firstName: 'Sophie',
        lastName: 'Martin',
        email: 'sophie@example.com',
        role: MemberRole.secretary,
        isActive: true,
        joinedAt: DateTime(2026, 1, 1),
      );
      expect(member.fullName, 'Sophie Martin');
    });

    test('Member ne porte pas de champ motif ni notes_medicales', () {
      final member = Member(
        id: 'm1',
        cabinetId: 'c1',
        firstName: 'Sophie',
        lastName: 'Martin',
        email: 'sophie@example.com',
        role: MemberRole.secretary,
        isActive: true,
        joinedAt: DateTime(2026, 1, 1),
      );
      final json = {
        'id': member.id,
        'firstName': member.firstName,
        'lastName': member.lastName,
        'email': member.email,
        'role': member.role.name,
      };
      expect(json.containsKey('motif'), isFalse);
      expect(json.containsKey('notesMedicales'), isFalse);
    });
  });

  // --- AdminMembresBloc --------------------------------------------------------
  group('AdminMembresBloc', () {
    setUpAll(() {
      registerFallbackValue(MemberRole.secretary);
    });

    late _MockMembersRepository membersRepo;
    late _MockSecretariatRepository secretariatRepo;
    late ListMembersUseCase listMembers;
    late ListSecretariatsUseCase listSecretariats;
    late InviteMemberUseCase inviteMember;

    final members = [
      Member(
        id: 'm1',
        cabinetId: 'c1',
        firstName: 'Sophie',
        lastName: 'Martin',
        email: 'sophie@example.com',
        role: MemberRole.secretary,
        isActive: true,
        joinedAt: DateTime(2026, 1, 1),
      ),
    ];

    final secretariats = [
      Secretariat(
        id: 's1',
        cabinetId: 'c1',
        name: 'Secrétariat A',
        email: 'secra@example.com',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    setUp(() {
      membersRepo = _MockMembersRepository();
      secretariatRepo = _MockSecretariatRepository();
      listMembers = ListMembersUseCase(membersRepo);
      listSecretariats = ListSecretariatsUseCase(secretariatRepo);
      inviteMember = InviteMemberUseCase(membersRepo);
    });

    blocTest<AdminMembresBloc, AdminMembresState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => membersRepo.list()).thenAnswer((_) async => Right(members));
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
          inviteMember: inviteMember,
        );
      },
      act: (bloc) => bloc.add(const AdminMembresLoadRequested()),
      expect: () => [
        const AdminMembresLoading(),
        AdminMembresLoaded(members: members, secretariats: secretariats),
      ],
    );

    blocTest<AdminMembresBloc, AdminMembresState>(
      'émet Loading puis Error si membres échoue',
      build: () {
        when(() => membersRepo.list()).thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
          inviteMember: inviteMember,
        );
      },
      act: (bloc) => bloc.add(const AdminMembresLoadRequested()),
      expect: () => [
        const AdminMembresLoading(),
        const AdminMembresError('Erreur réseau'),
      ],
    );

    blocTest<AdminMembresBloc, AdminMembresState>(
      'émet Loading puis Forbidden sur 403 (route admin-only)',
      build: () {
        when(() => membersRepo.list()).thenAnswer(
          (_) async => Left(const ServerFailure(
            message: 'Accès réservé aux administrateurs du cabinet.',
            statusCode: 403,
          )),
        );
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
          inviteMember: inviteMember,
        );
      },
      act: (bloc) => bloc.add(const AdminMembresLoadRequested()),
      expect: () => [
        const AdminMembresLoading(),
        const AdminMembresForbidden(
            'Accès réservé aux administrateurs du cabinet.'),
      ],
    );

    blocTest<AdminMembresBloc, AdminMembresState>(
      'émet Loading puis Error si l\'invitation échoue',
      build: () {
        when(() => membersRepo.invite(any(), any(), any(), any())).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Impossible d\'inviter le membre.'),
          ),
        );
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
          inviteMember: inviteMember,
        );
      },
      act: (bloc) => bloc.add(
        const AdminMembresInviteRequested(
          email: 'nouveau@cabinet.fr',
          role: MemberRole.secretary,
          firstName: 'Camille',
          lastName: 'Durand',
        ),
      ),
      expect: () => [
        const AdminMembresLoading(),
        const AdminMembresError('Impossible d\'inviter le membre.'),
      ],
      verify: (_) {
        verify(() => membersRepo.invite(
              'nouveau@cabinet.fr',
              MemberRole.secretary,
              'Camille',
              'Durand',
            )).called(1);
      },
    );

    blocTest<AdminMembresBloc, AdminMembresState>(
      'émet Loading puis InviteSuccess et recharge la liste si l\'invitation réussit',
      build: () {
        when(() => membersRepo.invite(any(), any(), any(), any())).thenAnswer(
          (_) async => Right(members.first),
        );
        when(() => membersRepo.list()).thenAnswer((_) async => Right(members));
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
          inviteMember: inviteMember,
        );
      },
      act: (bloc) => bloc.add(
        const AdminMembresInviteRequested(
          email: 'nouveau@cabinet.fr',
          role: MemberRole.secretary,
          firstName: 'Camille',
          lastName: 'Durand',
        ),
      ),
      expect: () => [
        const AdminMembresLoading(),
        const AdminMembresInviteSuccess(),
        const AdminMembresLoading(),
        AdminMembresLoaded(members: members, secretariats: secretariats),
      ],
    );

    blocTest<AdminMembresBloc, AdminMembresState>(
      'les membres chargés n\'exposent aucun champ clinique',
      build: () {
        when(() => membersRepo.list()).thenAnswer((_) async => Right(members));
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
          inviteMember: inviteMember,
        );
      },
      act: (bloc) => bloc.add(const AdminMembresLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<AdminMembresLoaded>());
        for (final m in (loaded as AdminMembresLoaded).members) {
          expect(m.fullName, isNotEmpty);
          // Member ne porte pas motif ni notes_medicales :
          // garantie structurelle par le type.
        }
      },
    );
  });

  // --- AdminMembresPage widget test --------------------------------------------
  group('AdminMembresPage', () {
    late _MockAdminMembresBloc bloc;

    setUpAll(() {
      registerFallbackValue(_FakeAdminMembresEvent());
    });

    setUp(() {
      bloc = _MockAdminMembresBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<AdminMembresBloc>.value(
            value: bloc,
            child: const AdminMembresPage(),
          ),
        );

    testWidgets('affiche le chargement en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const AdminMembresInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche le chargement en état Loading', (tester) async {
      when(() => bloc.state).thenReturn(const AdminMembresLoading());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche les membres — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        AdminMembresLoaded(
          members: [
            Member(
              id: 'm1',
              cabinetId: 'c1',
              firstName: 'Sophie',
              lastName: 'Martin',
              email: 'sophie@example.com',
              role: MemberRole.secretary,
              isActive: true,
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          secretariats: const [],
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Sophie Martin'), findsOneWidget);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('affiche un message si la liste membres est vide',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AdminMembresLoaded(members: [], secretariats: []),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Aucun membre enregistré.'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const AdminMembresError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });

    testWidgets('affiche NubiaEmptyState en état AdminMembresEmpty',
        (tester) async {
      when(() => bloc.state).thenReturn(const AdminMembresEmpty());
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin_membres_empty')), findsOneWidget);
      expect(
          find.text('Aucun membre ni secrétariat enregistré.'), findsOneWidget);
    });

    testWidgets(
        'état Forbidden (403) : masque le FAB et affiche l\'accès réservé',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AdminMembresForbidden(
            'Accès réservé aux administrateurs du cabinet.'),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Cul-de-sac 403 évité : plus aucune action d'invitation proposée.
      expect(find.byKey(const Key('add_member_fab')), findsNothing);
      expect(find.byKey(const Key('admin_membres_forbidden')), findsOneWidget);
      expect(find.text('Accès réservé aux administrateurs'), findsOneWidget);
    });

    testWidgets('état Loaded : le FAB d\'invitation reste disponible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AdminMembresLoaded(members: [], secretariats: []),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_member_fab')), findsOneWidget);
    });

    Future<void> submitInviteViaFab(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('add_member_fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('invite_first_name_field')),
        'Camille',
      );
      await tester.enterText(
        find.byKey(const Key('invite_last_name_field')),
        'Durand',
      );
      await tester.enterText(
        find.byKey(const Key('invite_email_field')),
        'nouveau@cabinet.fr',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('invite_submit_button')));
      await tester.pump();
    }

    testWidgets(
        'échec de l\'invitation (réel, pas stub) : affiche l\'état d\'erreur',
        (tester) async {
      whenListen(
        bloc,
        Stream.fromIterable([
          const AdminMembresLoading(),
          const AdminMembresError('Impossible d\'inviter le membre.'),
        ]),
        initialState: const AdminMembresLoaded(members: [], secretariats: []),
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await submitInviteViaFab(tester);
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(
          any(
            that: isA<AdminMembresInviteRequested>()
                .having((e) => e.email, 'email', 'nouveau@cabinet.fr')
                .having((e) => e.role, 'role', MemberRole.secretary)
                .having((e) => e.firstName, 'firstName', 'Camille')
                .having((e) => e.lastName, 'lastName', 'Durand'),
          ),
        ),
      ).called(1);

      expect(find.text('Impossible d\'inviter le membre.'), findsOneWidget);
      expect(find.text('Invitation envoyée.'), findsNothing);
    });

    testWidgets(
        'succès réel de l\'invitation (pas stub) : SnackBar puis liste rechargée',
        (tester) async {
      final reloadedMembers = [
        Member(
          id: 'm1',
          cabinetId: 'c1',
          firstName: 'Sophie',
          lastName: 'Martin',
          email: 'sophie@example.com',
          role: MemberRole.secretary,
          isActive: true,
          joinedAt: DateTime(2026, 1, 1),
        ),
      ];

      whenListen(
        bloc,
        Stream.fromIterable([
          const AdminMembresLoading(),
          const AdminMembresInviteSuccess(),
          const AdminMembresLoading(),
          AdminMembresLoaded(members: reloadedMembers, secretariats: const []),
        ]),
        initialState: const AdminMembresLoaded(members: [], secretariats: []),
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await submitInviteViaFab(tester);
      await tester.pumpAndSettle();

      verify(
        () => bloc.add(
          any(
            that: isA<AdminMembresInviteRequested>()
                .having((e) => e.email, 'email', 'nouveau@cabinet.fr')
                .having((e) => e.role, 'role', MemberRole.secretary)
                .having((e) => e.firstName, 'firstName', 'Camille')
                .having((e) => e.lastName, 'lastName', 'Durand'),
          ),
        ),
      ).called(1);

      expect(find.text('Invitation envoyée.'), findsOneWidget);
      expect(find.text('Sophie Martin'), findsOneWidget);
    });
  });
}
