import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/admin_membres/members_access_cubit.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockMembersRepository extends Mock implements MembersRepository {}

void main() {
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

  // --- MembersAccessCubit : signal de rôle (403) -----------------------------
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
      'probe 200 : accès accordé (secrétaire-admin)',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right(members));
        return MembersAccessCubit(listMembers);
      },
      act: (cubit) => cubit.probe(),
      expect: () => [MembersAccess.granted],
      verify: (cubit) => expect(cubit.canManageMembers, isTrue),
    );

    blocTest<MembersAccessCubit, MembersAccess>(
      'probe 403 : accès refusé (secrétaire simple) → onglet masqué',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => Left(const ServerFailure(
            message: 'Accès réservé aux administrateurs du cabinet.',
            statusCode: 403,
          )),
        );
        return MembersAccessCubit(listMembers);
      },
      act: (cubit) => cubit.probe(),
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
      act: (cubit) => cubit.probe(),
      expect: () => <MembersAccess>[],
      verify: (cubit) => expect(cubit.canManageMembers, isTrue),
    );
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
      // Une seule destination retirée : pas de trou d'index.
      expect(config.destinations.length,
          ProConfig.shellConfig.destinations.length - 1);
    });

    test(
        'canManageMembers=false : préserve les autres destinations et l\'ordre',
        () {
      final base = ProConfig.shellConfig.destinations
          .where((d) => d.route != ProConfig.membersRoute)
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
    testWidgets('secrétaire-admin : « Membres » visible dans la nav',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildShell(canManageMembers: true));
      await tester.pumpAndSettle();
      expect(find.text('Membres'), findsWidgets);
    });

    testWidgets('secrétaire simple : « Membres » absent (pas d\'impasse 403)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildShell(canManageMembers: false));
      await tester.pumpAndSettle();
      expect(find.text('Membres'), findsNothing);
      // Les autres destinations restent présentes.
      expect(find.text('Agenda'), findsWidgets);
      expect(find.text('Secrétariats'), findsWidgets);
    });
  });
}
