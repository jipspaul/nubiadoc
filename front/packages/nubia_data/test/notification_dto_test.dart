import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

void main() {
  group('NotificationDto', () {
    // Régression #6197 : le backend n'émet jamais les kinds bare
    // 'appointment'/'message'/'document'/'payment', mais des kinds
    // préfixés/composés (cf. api/src/notifications.rs `derive_deep_link`
    // et les appels `notify::notify_*`). L'ancien switch strict retombait
    // donc toujours sur NotificationType.other quel que soit le kind réel.
    final cases = <String, NotificationType>{
      'appointment_confirmed': NotificationType.appointment,
      'appointment_rescheduled': NotificationType.appointment,
      'appointment_motif_changed': NotificationType.appointment,
      'waiting_room_called': NotificationType.appointment,
      'waiting_list_slot_offered': NotificationType.appointment,
      'visit_status_changed': NotificationType.appointment,
      'visit_offer': NotificationType.appointment,
      'visit_request_expired': NotificationType.appointment,
      'rdv_confirmation': NotificationType.appointment,
      'recall_annual': NotificationType.appointment,
      'review_request': NotificationType.message,
      'message_received': NotificationType.message,
      'message_created': NotificationType.message,
      'lab_work_returned': NotificationType.document,
      'quote_relance': NotificationType.payment,
      'quote_received': NotificationType.payment,
      'pharmacy_quote_sent': NotificationType.payment,
      'unpaid_invoice': NotificationType.payment,
      'order_received': NotificationType.other,
      'order_status_changed': NotificationType.other,
      'pharmacy_order_preparing': NotificationType.other,
      'pharmacy_order_ready': NotificationType.other,
      'pharmacy_order_picked_up': NotificationType.other,
      'unknown_future_kind': NotificationType.other,
    };

    cases.forEach((kind, expected) {
      test('kind=$kind -> $expected', () {
        final dto = NotificationDto.fromJson({
          'id': '1',
          'kind': kind,
          'title': 'Titre',
          'is_read': false,
          'created_at': '2026-01-01T00:00:00Z',
        });

        expect(dto.toDomain().type, expected);
      });
    });

    // Régression #6280 : le kind brut doit survivre jusqu'au domaine — les
    // `NotificationRouteResolver` pro (#6264) en ont besoin pour distinguer
    // des kinds bucketés dans le même `NotificationType` (ex.
    // order_received/stock_request_received, tous deux `other`).
    test('toDomain() préserve le kind brut', () {
      final dto = NotificationDto.fromJson({
        'id': '1',
        'kind': 'stock_request_received',
        'title': 'Titre',
        'is_read': false,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(dto.toDomain().kind, 'stock_request_received');
    });

    // Régression #6376 : l'API n'émet jamais de `body` (toujours un stub
    // chiffré côté backend, cf. `api/src/notify.rs` `notify_user`), mais
    // fournit toujours `data` en clair. Sans dérivation côté client, 4
    // notifications `visit_status_changed` distinctes (`data.status` :
    // accepted/en_route/arrived/done) rendaient une ligne de détail
    // identique (vide) — indistinguables dans l'inbox patient.
    test('body absent + kind=visit_status_changed -> dérive du data.status, '
        'distingue les 4 étapes', () {
      final bodies = {
        'accepted',
        'en_route',
        'arrived',
        'done',
      }.map((status) {
        final dto = NotificationDto.fromJson({
          'id': '1',
          'kind': 'visit_status_changed',
          'title': 'Votre visite a été mise à jour',
          'data': {'visit_request_id': 'v1', 'status': status},
          'is_read': false,
          'created_at': '2026-01-01T00:00:00Z',
        });
        return dto.toDomain().body;
      }).toSet();

      // 4 statuts distincts -> 4 corps distincts, tous non vides.
      expect(bodies, hasLength(4));
      expect(bodies, everyElement(isNotEmpty));
    });

    test('body déjà fourni par l\'API -> jamais écrasé par la dérivation', () {
      final dto = NotificationDto.fromJson({
        'id': '1',
        'kind': 'visit_status_changed',
        'title': 'Titre',
        'body': 'Corps réel',
        'data': {'status': 'done'},
        'is_read': false,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(dto.toDomain().body, 'Corps réel');
    });

    // Régression #6610 : `data.status` doit survivre jusqu'au domaine pour
    // que l'UI (notifications_page.dart `_actionFor`) puisse discriminer
    // l'action affichée (ex. « Afficher mon code » réservé au statut ready).
    test('toDomain() préserve data.status', () {
      final dto = NotificationDto.fromJson({
        'id': '1',
        'kind': 'order_status_changed',
        'title': 'Titre',
        'data': {'order_id': 'o1', 'status': 'picked_up'},
        'is_read': false,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(dto.toDomain().status, 'picked_up');
    });

    test('body absent + status inconnu -> corps générique non vide', () {
      final dto = NotificationDto.fromJson({
        'id': '1',
        'kind': 'order_status_changed',
        'title': 'Titre',
        'data': {'order_id': 'o1', 'status': 'unknown_future_status'},
        'is_read': false,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(dto.toDomain().body, isNotEmpty);
    });
  });
}
