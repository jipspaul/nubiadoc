import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/messaging/messaging_dto.dart';
import 'package:nubia_domain/nubia_domain.dart';

void main() {
  // #5285 : le type d'interlocuteur (cabinet vs pharmacie) doit être mappé
  // depuis le champ `type` du contrat `GET /v1/conversations` pour permettre
  // au front de distinguer pictogramme/teinte dans la liste des conversations.
  group('ConversationDto.toDomain — interlocutorType', () {
    test('type "pharmacy" est mappé sur ConversationInterlocutorType.pharmacy',
        () {
      final dto = ConversationDto.fromJson({
        'id': 'conv-1',
        'cabinet_id': 'cab-1',
        'cabinet_name': 'Pharmacie du Théâtre',
        'unread_count': 0,
        'type': 'pharmacy',
      });

      expect(
        dto.toDomain().interlocutorType,
        ConversationInterlocutorType.pharmacy,
      );
    });

    test('type "cabinet" est mappé sur ConversationInterlocutorType.cabinet',
        () {
      final dto = ConversationDto.fromJson({
        'id': 'conv-2',
        'cabinet_id': 'cab-2',
        'cabinet_name': 'Cabinet Nubia Opéra',
        'unread_count': 0,
        'type': 'cabinet',
      });

      expect(
        dto.toDomain().interlocutorType,
        ConversationInterlocutorType.cabinet,
      );
    });

    test('type absent (ancien payload) retombe sur cabinet', () {
      final dto = ConversationDto.fromJson({
        'id': 'conv-3',
        'cabinet_id': 'cab-3',
        'cabinet_name': 'Cabinet Nubia Opéra',
        'unread_count': 0,
      });

      expect(
        dto.toDomain().interlocutorType,
        ConversationInterlocutorType.cabinet,
      );
    });
  });

  // #5275 : nom + rôle de l'émetteur, affichés en tête de bulle côté
  // app_patient — doivent survivre au mapping DTO -> domaine.
  group('MessageDto.toDomain — authorName/authorRole (#5275)', () {
    test('author_name et author_role sont mappés depuis le contrat', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'conversation_id': 'conv-1',
        'sender': 'cabinet',
        'body': 'Gardez la zone au frais 48h.',
        'created_at': '2026-06-18T09:00:00Z',
        'author_name': 'Dr Amélie Rousseau',
        'author_role': 'Praticien',
      });

      final message = dto.toDomain();
      expect(message.authorName, 'Dr Amélie Rousseau');
      expect(message.authorRole, 'Praticien');
    });

    test('author_name absent (relance secrétariat) retombe sur author_role',
        () {
      final dto = MessageDto.fromJson({
        'id': 'msg-2',
        'conversation_id': 'conv-1',
        'sender': 'cabinet',
        'body': 'Votre devis DEV-2041 vous a été envoyé.',
        'created_at': '2026-06-18T09:05:00Z',
        'author_role': 'Secrétariat',
      });

      final message = dto.toDomain();
      expect(message.authorName, isNull);
      expect(message.authorRole, 'Secrétariat');
    });

    test('ancien payload sans author_name/author_role reste valide', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-3',
        'conversation_id': 'conv-1',
        'sender': 'patient',
        'body': 'Merci docteur',
        'created_at': '2026-06-18T09:10:00Z',
      });

      final message = dto.toDomain();
      expect(message.authorName, isNull);
      expect(message.authorRole, isNull);
    });
  });
}
