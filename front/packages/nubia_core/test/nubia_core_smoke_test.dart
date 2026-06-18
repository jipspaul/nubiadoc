import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

void main() {
  group('proRoleFromString', () {
    test('reconnaît admin', () {
      expect(proRoleFromString('admin'), ProRole.admin);
    });

    test('reconnaît practitioner', () {
      expect(proRoleFromString('practitioner'), ProRole.practitioner);
    });

    test('reconnaît secretary', () {
      expect(proRoleFromString('secretary'), ProRole.secretary);
    });

    test('retourne unknown pour une valeur inconnue', () {
      expect(proRoleFromString('superuser'), ProRole.unknown);
    });

    test('retourne unknown pour null', () {
      expect(proRoleFromString(null), ProRole.unknown);
    });
  });

  group('AuthSession', () {
    test('crée une session patient valide', () {
      const session = AuthSession(
        kind: UserKind.patient,
        userId: 'user-abc',
        accountId: 'account-xyz',
      );
      expect(session.kind, UserKind.patient);
      expect(session.userId, 'user-abc');
      expect(session.accountId, 'account-xyz');
      expect(session.role, ProRole.unknown);
      expect(session.cabinetId, isNull);
    });

    test('crée une session pro valide', () {
      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-pro',
        role: ProRole.practitioner,
        cabinetId: 'cabinet-1',
        displayName: 'Dr. Dupont',
      );
      expect(session.kind, UserKind.pro);
      expect(session.role, ProRole.practitioner);
      expect(session.cabinetId, 'cabinet-1');
      expect(session.displayName, 'Dr. Dupont');
    });

    test('canAccessClinical est vrai pour practitioner', () {
      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-1',
        role: ProRole.practitioner,
      );
      expect(session.canAccessClinical, isTrue);
    });

    test('canAccessClinical est faux pour secretary', () {
      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-2',
        role: ProRole.secretary,
      );
      expect(session.canAccessClinical, isFalse);
    });
  });
}
