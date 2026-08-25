import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/cabinet_team_messages/cabinet_team_messages_dto.dart';
import 'package:nubia_domain/nubia_domain.dart';

void main() {
  group('CabinetTeamMessageDto (#5131 — référence à un objet du produit)', () {
    test('fromJson sans reference → reference domaine nulle', () {
      final dto = CabinetTeamMessageDto.fromJson({
        'id': 'm1',
        'sender_id': 'u1',
        'sender_name': 'Dr Martin',
        'body': 'Réunion à 12h30.',
        'created_at': '2026-01-01T09:30:00Z',
      });

      expect(dto.reference, isNull);
      expect(dto.toDomain().reference, isNull);
    });

    test('fromJson avec reference patient → mappée sur le domaine', () {
      final dto = CabinetTeamMessageDto.fromJson({
        'id': 'm2',
        'sender_id': 'u1',
        'sender_name': 'Dr Martin',
        'body': 'Peux-tu reprogrammer le labo ?',
        'created_at': '2026-01-01T10:00:00Z',
        'reference': {
          'type': 'lab_work_order',
          'target_id': 'lwo1',
          'title': 'Couronne céramo-métallique · dent 26',
          'subtitle': 'Labo Kléber · à programmer',
        },
      });

      final reference = dto.toDomain().reference;
      expect(reference, isNotNull);
      expect(reference!.type, CabinetTeamMessageReferenceType.labWorkOrder);
      expect(reference.targetId, 'lwo1');
      expect(reference.title, 'Couronne céramo-métallique · dent 26');
      expect(reference.subtitle, 'Labo Kléber · à programmer');
    });

    test('fromJson avec type de référence inconnu → domaine nul (tolérant)',
        () {
      final dto = CabinetTeamMessageDto.fromJson({
        'id': 'm3',
        'sender_id': 'u1',
        'sender_name': 'Dr Martin',
        'body': 'Message',
        'created_at': '2026-01-01T10:00:00Z',
        'reference': {
          'type': 'unknown_future_type',
          'target_id': 'x1',
          'title': 'Titre',
          'subtitle': 'Sous-titre',
        },
      });

      expect(dto.toDomain().reference, isNull);
    });
  });

  group('CabinetTeamMessageDto (#5130 — épinglage)', () {
    test('fromJson sans champs d\'épinglage → non épinglé par défaut', () {
      final dto = CabinetTeamMessageDto.fromJson({
        'id': 'm1',
        'sender_id': 'u1',
        'sender_name': 'Dr Martin',
        'body': 'Réunion à 12h30.',
        'created_at': '2026-01-01T09:30:00Z',
      });

      expect(dto.toDomain().pinned, isFalse);
      expect(dto.toDomain().pinnedBy, isNull);
      expect(dto.toDomain().pinnedAt, isNull);
    });

    test('fromJson avec épinglage → mappé sur le domaine', () {
      final dto = CabinetTeamMessageDto.fromJson({
        'id': 'm4',
        'sender_id': 'u1',
        'sender_name': 'Dr A. Rousseau',
        'body': 'Fermeture exceptionnelle le vendredi 15 août.',
        'created_at': '2026-08-02T09:00:00Z',
        'pinned': true,
        'pinned_by': 'u1',
        'pinned_at': '2026-08-02T09:00:00Z',
      });

      final message = dto.toDomain();
      expect(message.pinned, isTrue);
      expect(message.pinnedBy, 'u1');
      expect(message.pinnedAt, DateTime.parse('2026-08-02T09:00:00Z'));
    });
  });

  group('CabinetTeamMessageDto (#5129 — mention d\'un membre)', () {
    test('fromJson sans mentions → liste vide par défaut', () {
      final dto = CabinetTeamMessageDto.fromJson({
        'id': 'm1',
        'sender_id': 'u1',
        'sender_name': 'Dr Martin',
        'body': 'Réunion à 12h30.',
        'created_at': '2026-01-01T09:30:00Z',
      });

      expect(dto.toDomain().mentions, isEmpty);
    });

    test('fromJson avec mentions → mappées sur le domaine', () {
      final dto = CabinetTeamMessageDto.fromJson({
        'id': 'm5',
        'sender_id': 'u1',
        'sender_name': 'Dr Martin',
        'body': '@Sarah tu peux la contacter ?',
        'created_at': '2026-01-01T09:30:00Z',
        'mentions': ['Sarah'],
      });

      expect(dto.toDomain().mentions, ['Sarah']);
    });
  });
}
