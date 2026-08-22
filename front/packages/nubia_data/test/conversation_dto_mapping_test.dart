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
}
