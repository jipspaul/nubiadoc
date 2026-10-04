import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/admin_membres/members_access_cubit.dart';
import 'package:app_secretariat/pro_config.dart';
import 'package:app_secretariat/session/pro_auth_cubit.dart';

class _MockMembersRepository extends Mock implements MembersRepository {}

class _MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

void main() {
  final admin = Member(
    id: 'me',
    cabinetId: 'c1',
    firstName: 'Alice',
    lastName: 'Admin',
    email: 'alice@example.com',
    role: MemberRole.admin,
    isActive: true,
    joinedAt: DateTime(2026, 1, 1),
  );

  final secretary = Member(
    id: 'me',
    cabinetId: 'c1',
    firstName: 'Sophie',
    lastName: 'Martin',
    email: 'sophie@example.com',
    role: MemberRole.secretary,
    isActive: true,
    joinedAt: DateTime(2026, 1, 1),
  );

  // --- MembersAccessCubit : signal de rôle (#7925, GET /members n'est plus
  // gardée depuis #7351 — le rôle se lit désormais dans l'entrée de
  // l'appelant au sein de la liste retournée, plus dans le status code).
  group('MembersAccessCubit', () {
    late _MockMembersRepository repo;
    late ListMembersUseCase listMembers;

    setUp(() {
      repo = _MockMembersRepository();
      listMembers = ListMembersUseCase(repo);
    });

    test('canManageMembers est vrai tant que le rôle est inconnu', () {
      final cubit = MembersAccessCubit(listMembers);
      expect(cubit.state, MembersAccess.unknown);
      expect(cubit.canManageMembers, isTrue);
    });

    blocTest<MembersAccessCubit, MembersAccess>(
      'probe 200, rôle admin dans la liste : accès accordé (secrétaire-admin)',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right([admin]));
        return MembersAccessCubit(listMembers);
      },
      act: (cubit) => cubit.probe('me'),
      expect: () => [MembersAccess.granted],
      verify: (cubit) => expect(cubit.canManageMembers, isTrue),
    );

    blocTest<MembersAccessCubit, MembersAccess>(
      'probe 200, rôle secretary dans la liste : accès refusé → onglet masqué',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right([secretary]));
        return MembersAccessCubit(listMembers);
      },
      act: (cubit) => cubit.probe('me'),
      expect: () => [MembersAccess.denied],
      verify: (cubit) => expect(cubit.canManageMembers, isFalse),
    );

    blocTest<MembersAccessCubit, MembersAccess>(
      'probe 200, appelant absent de la liste : accès accordé (pas de verrou sur ambiguïté)',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right([secretary]));
        return MembersAccessCubit(listMembers);
      },
      act: (cubit) => cubit.probe('introuvable'),
      expect: () => [MembersAccess.granted],
    );

    blocTest<MembersAccessCubit, MembersAccess>(
      'probe 403 : accès refusé (token obsolète/malformé) → onglet masqué',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => Left(const ServerFailure(
            message: 'Accès réservé aux administrateurs du cabinet.',
            statusCode: 403,
          )),
        );
        return MembersAccessCubit(listMembers);
      },
      act: (cubit) => cubit.probe('me'),
      expect: () => [MembersAccess.denied],
      verify: (cubit) => expect(cubit.canManageMembers, isFalse),
    );

    blocTest<MembersAccessCubit, MembersAccess>(
      'probe erreur réseau : reste inconnu → onglet visible (pas de verrou admin)',
      build: () {
        when(() => repo.list())
            .thenAnswer((_) async => Left(const NetworkFailure()));
        return MembersAccessCubit(listMembers);
      },
      act: (cubit) => cubit.probe('me'),
      expect: () => <MembersAccess>[],
      verify: (cubit) => expect(cubit.canManageMembers, isTrue),
    );
  });

  // --- Sonde différée post-auth (#7941, résidu de #7936/#7931) --------------
  // Reproduit le câblage de `SecretariatShell` (dashboard_page.dart) : sur une
  // URL directe, ce shell est construit AVANT que `ProAuthCubit.restore()`
  // n'ait résolu `GET /v1/me`, donc avec un `AuthState` encore non-authentifié
  // — `create` ne doit alors PAS sonder avec le `userId` placeholder, et le
  // `BlocListener` doit rattraper la sonde dès que l'état réel arrive.
  group('MembersAccessCubit — sonde différée post-auth (#7941)', () {
    late _MockMembersRepository repo;
    late ListMembersUseCase listMembers;
    late _MockProAuthCubit authCubit;
    late StreamController<AuthState> authStates;

    final secretary = Member(
      id: 'a0000000-0000-0000-0000-0000000000a3',
      cabinetId: 'c1',
      firstName: 'Sonia',
      lastName: 'Accueil',
      email: 'sonia.accueil@cabinet-lyon.test',
      role: MemberRole.secretary,
      isActive: true,
      joinedAt: DateTime(2026, 1, 1),
    );

    const authenticated = AuthAuthenticated(AuthSession(
      kind: UserKind.pro,
      userId: 'a0000000-0000-0000-0000-0000000000a3',
      role: ProConfig.role,
    ));

    setUp(() {
      repo = _MockMembersRepository();
      listMembers = ListMembersUseCase(repo);
      when(() => repo.list()).thenAnswer((_) async => Right([secretary]));
      authCubit = _MockProAuthCubit();
      authStates = StreamController<AuthState>.broadcast();
    });

    tearDown(() => authStates.close());

    Widget buildHarness() => MultiBlocProvider(
          providers: [
            BlocProvider<ProAuthCubit>.value(value: authCubit),
            BlocProvider<MembersAccessCubit>(
              create: (_) {
                final cubit = MembersAccessCubit(listMembers);
                final state = authCubit.state;
                if (state is AuthAuthenticated) {
                  cubit.probe(state.session.userId);
                }
                return cubit;
              },
            ),
          ],
          child: BlocListener<ProAuthCubit, AuthState>(
            listenWhen: (_, state) => state is AuthAuthenticated,
            listener: (context, state) => context
                .read<MembersAccessCubit>()
                .probe((state as AuthAuthenticated).session.userId),
            // `BlocProvider` est lazy (#7941 côté test) : sans lecture de
            // [MembersAccessCubit] pendant le build, `create` ne s'exécute
            // qu'au premier accès — ici on reproduit la lecture immédiate que
            // fait `SecretariatShell._buildShell` dans l'app réelle.
            child: Builder(
              builder: (context) {
                context.watch<MembersAccessCubit>();
                return const SizedBox.shrink();
              },
            ),
          ),
        );

    testWidgets(
        'auth pas encore résolue au montage : pas de sonde placeholder, '
        'puis sonde correcte (→ denied) dès que `GET /me` résout',
        (tester) async {
      whenListen(authCubit, authStates.stream, initialState: const AuthUnknown());
      await tester.pumpWidget(MaterialApp(home: buildHarness()));
      await tester.pump();

      final context = tester.element(find.byType(SizedBox));
      // Pas de sonde avec le placeholder 'me' : l'accès reste `unknown`.
      expect(
        BlocProvider.of<MembersAccessCubit>(context).state,
        MembersAccess.unknown,
      );

      authStates.add(authenticated);
      await tester.pumpAndSettle();

      expect(
        BlocProvider.of<MembersAccessCubit>(context).state,
        MembersAccess.denied,
      );
    });

    testWidgets('auth déjà résolue au montage : sonde immédiate (→ denied)',
        (tester) async {
      whenListen(authCubit, authStates.stream, initialState: authenticated);
      await tester.pumpWidget(MaterialApp(home: buildHarness()));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SizedBox));
      expect(
        BlocProvider.of<MembersAccessCubit>(context).state,
        MembersAccess.denied,
      );
    });
  });

  // --- ProConfig.shellConfigFor : filtrage de la nav -------------------------
  group('ProConfig.shellConfigFor', () {
    test('canManageMembers=true : conserve l\'entrée « Membres »', () {
      final config = ProConfig.shellConfigFor(
          canManageMembers: true, canViewAuditLog: true);
      expect(
        config.destinations.where((d) => d.route == ProConfig.membersRoute),
        isNotEmpty,
      );
      expect(config.destinations.length,
          ProConfig.shellConfig.destinations.length);
    });

    test('canManageMembers=false : masque l\'entrée « Membres »', () {
      final config = ProConfig.shellConfigFor(
          canManageMembers: false, canViewAuditLog: true);
      expect(
        config.destinations.where((d) => d.route == ProConfig.membersRoute),
        isEmpty,
      );
    });

    test('canManageMembers=false : masque aussi l\'entrée « Secrétariats »',
        () {
      // #5156 : /admin-secretariats partage le même rôle admin strict que
      // /admin-membres (ProAdminClaims côté back) et se gate donc via le
      // même signal. #7178 : /reprise-donnees (ProAdminClaims aussi) rejoint
      // ce même signal.
      final config = ProConfig.shellConfigFor(
          canManageMembers: false, canViewAuditLog: true);
      expect(
        config.destinations
            .where((d) => d.route == ProConfig.secretariatsRoute),
        isEmpty,
      );
      expect(
        config.destinations
            .where((d) => d.route == ProConfig.dataImportRoute),
        isEmpty,
      );
      // Trois destinations retirées (Membres + Secrétariats + Reprise de
      // données) : pas de trou d'index.
      expect(config.destinations.length,
          ProConfig.shellConfig.destinations.length - 3);
    });

    test('canManageMembers=true : conserve l\'entrée « Secrétariats »', () {
      final config = ProConfig.shellConfigFor(
          canManageMembers: true, canViewAuditLog: true);
      expect(
        config.destinations
            .where((d) => d.route == ProConfig.secretariatsRoute),
        isNotEmpty,
      );
    });

    test(
        'canManageMembers=false : préserve les autres destinations et l\'ordre',
        () {
      final base = ProConfig.shellConfig.destinations
          .where((d) =>
              d.route != ProConfig.membersRoute &&
              d.route != ProConfig.secretariatsRoute &&
              d.route != ProConfig.dataImportRoute)
          .map((d) => d.route)
          .toList();
      final filtered = ProConfig.shellConfigFor(
              canManageMembers: false, canViewAuditLog: true)
          .destinations
          .map((d) => d.route)
          .toList();
      expect(filtered, base);
    });
  });

  // --- Rendu ProShell : l'onglet « Membres » disparaît -----------------------
  group('ProShell — entrée « Membres » gated', () {
    const session = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProConfig.role,
    );

    Widget buildShell({required bool canManageMembers}) => MaterialApp(
          theme: NubiaTheme.light,
          home: shell.ProShell(
            config: ProConfig.shellConfigFor(
              canManageMembers: canManageMembers,
              canViewAuditLog: true,
            ),
            session: session,
          ),
        );

    // Surface haute : la nav complète (10 entrées) tient sans overflow du rail.
    testWidgets(
        'secrétaire-admin : « Membres » et « Secrétariats » visibles dans la nav '
        'une fois le groupe « Réglages du cabinet » déplié (#5139, replié par '
        'défaut)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildShell(canManageMembers: true));
      await tester.pumpAndSettle();
      expect(find.text('Membres'), findsNothing);
      expect(find.text('Secrétariats'), findsNothing);

      // Rail compact (>9 destinations, #4153) : le libellé de l'en-tête
      // n'est peint (opacité) que pour l'entrée sélectionnée — on tape sur
      // son chevron, toujours visible, plutôt que sur le texte du groupe.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text('Membres'), findsWidgets);
      expect(find.text('Secrétariats'), findsWidgets);
    });

    testWidgets(
        'secrétaire simple : « Membres » et « Secrétariats » absents (pas d\'impasse 403)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildShell(canManageMembers: false));
      await tester.pumpAndSettle();
      expect(find.text('Membres'), findsNothing);
      expect(find.text('Secrétariats'), findsNothing);
      // Les autres destinations restent présentes.
      expect(find.text('Agenda'), findsWidgets);
    });
  });
}
