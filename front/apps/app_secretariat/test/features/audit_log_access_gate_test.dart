//! Tests : `AuditLogAccessCubit` (signal de rôle 403, #4155) et le filtrage
//! de nav correspondant dans `ProConfig.shellConfigFor`. Même convention que
//! `members_access_gate_test.dart` (#3468).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/audit_log/audit_log_access_cubit.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockAuditLogRepository extends Mock implements AuditLogRepository {}

void main() {
  group('AuditLogAccessCubit', () {
    late _MockAuditLogRepository repo;
    late GetAuditLogUseCase getAuditLog;

    setUp(() {
      repo = _MockAuditLogRepository();
      getAuditLog = GetAuditLogUseCase(repo);
      registerFallbackValue(DateTime(2026));
    });

    test('canViewAuditLog est vrai tant que le rôle est inconnu', () {
      final cubit = AuditLogAccessCubit(getAuditLog);
      expect(cubit.state, AuditLogAccess.unknown);
      expect(cubit.canViewAuditLog, isTrue);
    });

    blocTest<AuditLogAccessCubit, AuditLogAccess>(
      'probe 200 : accès accordé (admin/manager)',
      build: () {
        when(() => repo.getAuditLog(
                from: any(named: 'from'),
                to: any(named: 'to'),
                entity: any(named: 'entity')))
            .thenAnswer((_) async => const Right([]));
        return AuditLogAccessCubit(getAuditLog);
      },
      act: (cubit) => cubit.probe(),
      expect: () => [AuditLogAccess.granted],
      verify: (cubit) => expect(cubit.canViewAuditLog, isTrue),
    );

    blocTest<AuditLogAccessCubit, AuditLogAccess>(
      'probe 403 : accès refusé (secretary/practitioner) → onglet masqué',
      build: () {
        when(() => repo.getAuditLog(
                from: any(named: 'from'),
                to: any(named: 'to'),
                entity: any(named: 'entity')))
            .thenAnswer((_) async => Left(const ServerFailure(
                  message: 'Accès réservé aux administrateurs du cabinet.',
                  statusCode: 403,
                )));
        return AuditLogAccessCubit(getAuditLog);
      },
      act: (cubit) => cubit.probe(),
      expect: () => [AuditLogAccess.denied],
      verify: (cubit) => expect(cubit.canViewAuditLog, isFalse),
    );

    blocTest<AuditLogAccessCubit, AuditLogAccess>(
      'probe erreur réseau : reste inconnu → onglet visible',
      build: () {
        when(() => repo.getAuditLog(
                from: any(named: 'from'),
                to: any(named: 'to'),
                entity: any(named: 'entity')))
            .thenAnswer((_) async => Left(const NetworkFailure()));
        return AuditLogAccessCubit(getAuditLog);
      },
      act: (cubit) => cubit.probe(),
      expect: () => <AuditLogAccess>[],
      verify: (cubit) => expect(cubit.canViewAuditLog, isTrue),
    );
  });

  group('ProConfig.shellConfigFor — journal d\'accès', () {
    test('canViewAuditLog=false : masque l\'entrée « Journal d\'accès »', () {
      final config = ProConfig.shellConfigFor(
          canManageMembers: true, canViewAuditLog: false);
      expect(
        config.destinations.where((d) => d.route == ProConfig.auditLogRoute),
        isEmpty,
      );
      expect(config.destinations.length,
          ProConfig.shellConfig.destinations.length - 1);
    });

    test(
        'canManageMembers=false et canViewAuditLog=false : masque les trois '
        'entrées admin', () {
      final config = ProConfig.shellConfigFor(
          canManageMembers: false, canViewAuditLog: false);
      expect(
        config.destinations.where((d) =>
            d.route == ProConfig.membersRoute ||
            d.route == ProConfig.secretariatsRoute ||
            d.route == ProConfig.auditLogRoute),
        isEmpty,
      );
      // Membres + Secrétariats (#5156, même signal canManageMembers) +
      // Journal d'accès.
      expect(config.destinations.length,
          ProConfig.shellConfig.destinations.length - 3);
    });
  });
}
