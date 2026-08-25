// #5259 — modèle domaine des invitations « proche » adulte : état,
// canal, périmètre accordé, révocation. DependentRelationship (enfant/
// conjoint/autre) est conservé — seul son traitement diffère.
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('AccessRequest', () {
    test('égalité par id, comme Dependent', () {
      const a = AccessRequest(
        id: 'ar-1',
        firstName: 'Jean',
        lastName: 'Dupont',
        relationship: DependentRelationship.conjoint,
        status: AccessRequestStatus.envoyee,
        channel: AccessRequestChannel.email,
      );
      const b = AccessRequest(
        id: 'ar-1',
        firstName: 'Autre',
        lastName: 'Nom',
        relationship: DependentRelationship.autre,
        status: AccessRequestStatus.acceptee,
        channel: AccessRequestChannel.sms,
      );

      expect(a, equals(b));
    });

    test('porte le périmètre accordé, le canal et la date de révocation',
        () {
      final revokedAt = DateTime.utc(2026, 8, 1);
      final request = AccessRequest(
        id: 'ar-2',
        firstName: 'Marie',
        lastName: 'Martin',
        relationship: DependentRelationship.autre,
        status: AccessRequestStatus.refusee,
        channel: AccessRequestChannel.sms,
        grantedScope: const {AccessRight.rendezVous, AccessRight.documents},
        revokedAt: revokedAt,
      );

      expect(request.channel, AccessRequestChannel.sms);
      expect(
        request.grantedScope,
        {AccessRight.rendezVous, AccessRight.documents},
      );
      expect(request.revokedAt, revokedAt);
      expect(request.displayName, 'Marie Martin');
    });

    test('les 4 états couvrent envoyée/acceptée/refusée/expirée', () {
      expect(AccessRequestStatus.values, hasLength(4));
      expect(
        AccessRequestStatus.values,
        containsAll(const [
          AccessRequestStatus.envoyee,
          AccessRequestStatus.acceptee,
          AccessRequestStatus.refusee,
          AccessRequestStatus.expiree,
        ]),
      );
    });

    test('DependentRelationship reste enfant/conjoint/autre', () {
      expect(DependentRelationship.values, hasLength(3));
      expect(
        DependentRelationship.values,
        containsAll(const [
          DependentRelationship.enfant,
          DependentRelationship.conjoint,
          DependentRelationship.autre,
        ]),
      );
    });
  });
}
