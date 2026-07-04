import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/scheduling/appointment_dto.dart';
import 'package:nubia_data/src/remote/auth/auth_dto.dart';
import 'package:nubia_data/src/remote/account/account_dto.dart';
import 'package:nubia_data/src/remote/dashboard/dashboard_dto.dart';
import 'package:nubia_data/src/remote/quotes_api.dart';
import 'package:nubia_data/src/remote/payments_api.dart';
import 'package:nubia_data/src/remote/search/search_dto.dart';
import 'package:nubia_data/src/remote/notifications/notification_dto.dart';
import 'package:nubia_data/src/remote/messaging/messaging_dto.dart';
import 'package:nubia_data/src/remote/billing/billing_dto.dart';

void main() {
  group('AppointmentDto (POST /v1/appointments/:id/cancel response)', () {
    test('fromJson désérialise un RDV annulé', () {
      final json = {
        'id': 'appt-1',
        'cabinet_id': 'cab-1',
        'practitioner_name': 'Dr Martin',
        'practitioner_specialty': 'Dentiste',
        'starts_at': '2026-07-01T09:00:00Z',
        'duration_minutes': 30,
        'motif': 'Détartrage',
        'status': 'cancelled',
        'type': 'in_person',
      };
      final dto = AppointmentDto.fromJson(json);
      expect(dto.id, 'appt-1');
      expect(dto.status, 'cancelled');
    });
  });

  group('PatientAccountDto', () {
    test('fromJson désérialise un profil patient complet (forme account)', () {
      final json = {
        'id': 'user-42',
        'first_name': 'Camille',
        'last_name': 'Dupont',
        'email': 'camille@example.com',
        'phone': '+33612345678',
        'date_of_birth': '1990-05-15',
      };
      final dto = PatientAccountDto.fromJson(json);
      expect(dto.id, 'user-42');
      expect(dto.email, 'camille@example.com');
      expect(dto.phone, '+33612345678');
    });

    // Non-régression #3100/#3022 : le vrai contrat de GET /v1/me est
    // MeResponse {user_id, email, kind, account_id, memberships} — l'ancien
    // parsing attendait {id, first_name, …} et jetait, faisant retomber
    // AuthCubit.restore() en Unauthenticated après signup.
    test('fromMeJson désérialise le contrat réel de GET /v1/me (patient)', () {
      final json = {
        'user_id': 'b3b0c8e2-0000-0000-0000-000000000001',
        'email': 'camille@example.com',
        'kind': 'patient',
        'account_id': 'a1a0c8e2-0000-0000-0000-000000000002',
        'memberships': <dynamic>[],
      };
      final dto = PatientAccountDto.fromMeJson(json);
      expect(dto.id, 'a1a0c8e2-0000-0000-0000-000000000002');
      expect(dto.email, 'camille@example.com');
    });

    test('fromMeJson retombe sur user_id quand account_id est null (pro)', () {
      final json = {
        'user_id': 'b3b0c8e2-0000-0000-0000-000000000001',
        'email': 'pro@example.com',
        'kind': 'pro',
        'account_id': null,
        'memberships': <dynamic>[],
      };
      final dto = PatientAccountDto.fromMeJson(json);
      expect(dto.id, 'b3b0c8e2-0000-0000-0000-000000000001');
    });
  });

  group('AccountDto (GET /v1/account response)', () {
    test('fromJson désérialise les coordonnées du compte patient', () {
      final json = {
        'id': 'acc-7',
        'first_name': 'Alex',
        'last_name': 'Moreau',
        'email': 'alex@example.com',
        'phone': null,
        'date_of_birth': null,
      };
      final dto = AccountDto.fromJson(json);
      expect(dto.id, 'acc-7');
      expect(dto.firstName, 'Alex');
      expect(dto.phone, isNull);
    });
  });

  group('QuoteSignDto (POST /v1/quotes/:id/sign response)', () {
    test('fromJson désérialise une réponse de signature eIDAS Yousign', () {
      final json = {
        'signature_id': 'sig-abc-123',
        'provider': 'yousign',
        'redirect_url': 'https://yousign.com/procedure/abc',
        'embed_token': null,
      };
      final dto = QuoteSignDto.fromJson(json);
      expect(dto.signatureId, 'sig-abc-123');
      expect(dto.provider, 'yousign');
      expect(dto.redirectUrl, 'https://yousign.com/procedure/abc');
      expect(dto.embedToken, isNull);
    });
  });

  group('PaymentIntentDto (POST /v1/payments/intent response)', () {
    test('fromJson désérialise un PaymentIntent Stripe', () {
      final json = {
        'payment_id': 'pi-stripe-xyz',
        'client_secret': 'pi_xyz_secret_abc',
      };
      final dto = PaymentIntentDto.fromJson(json);
      expect(dto.paymentId, 'pi-stripe-xyz');
      expect(dto.clientSecret, 'pi_xyz_secret_abc');
    });
  });

  group('DashboardDto (GET /v1/dashboard)', () {
    test(
        'fromJson désérialise un patient avec données (next_appointment, to_sign, to_pay)',
        () {
      final json = {
        'next_appointment': {
          'appointment_id': 'appt-abc',
          'starts_at': '2026-08-01T10:00:00Z',
          'status': 'confirmed',
        },
        'to_sign': [
          {'quote_id': 'q-1', 'amount_cents': 12000},
          {'quote_id': 'q-2', 'amount_cents': 8000},
        ],
        'to_pay': [
          {'payment_id': 'pay-1', 'amount_cents': 5000},
        ],
        'unread_messages': 3,
        'reminders': 1,
      };
      final dto = DashboardDto.fromJson(json);
      expect(dto.upcomingAppointments, 1);
      expect(dto.documentsToSign, 2);
      expect(dto.pendingPaymentsCents, 5000);
      expect(dto.unreadMessages, 3);
      expect(dto.pendingQuestionnaires, 1);
      final domain = dto.toDomain();
      expect(domain.upcomingAppointments, 1);
      expect(domain.documentsToSign, 2);
      expect(domain.pendingPaymentsCents, 5000);
    });

    test('fromJson désérialise un patient sans données (null / listes vides)',
        () {
      final json = {
        'next_appointment': null,
        'to_sign': [],
        'to_pay': [],
        'unread_messages': 0,
        'reminders': 0,
      };
      final dto = DashboardDto.fromJson(json);
      expect(dto.upcomingAppointments, 0);
      expect(dto.documentsToSign, 0);
      expect(dto.pendingPaymentsCents, 0);
      expect(dto.unreadMessages, 0);
      expect(dto.pendingQuestionnaires, 0);
    });
  });

  group('ProviderResultDto (GET /v1/search/providers → data[])', () {
    test('parse le contrat réel : provider_id, distance_m, geo', () {
      final json = {
        'provider_id': 'f0000000-0000-0000-0000-0000000000f1',
        'display_name': 'Dr Hugo Marin',
        'specialty': 'Chirurgie dentaire',
        'sector': '1',
        'distance_m': 2500.0,
        'next_slot_at': '2026-07-04T09:00:00Z',
        'rating_avg': 4.6,
        'geo': {'lat': 45.758, 'lng': 4.835},
        'is_listed': true,
      };
      final dto = ProviderResultDto.fromJson(json);
      final domain = dto.toDomain();
      expect(domain.id, 'f0000000-0000-0000-0000-0000000000f1');
      expect(domain.specialty, 'Chirurgie dentaire');
      expect(domain.distanceKm, closeTo(2.5, 1e-9));
      expect(domain.lat, closeTo(45.758, 1e-9));
      expect(domain.lng, closeTo(4.835, 1e-9));
      expect(domain.hasLocation, isTrue);
      expect(domain.ratingAvg, 4.6);
    });

    test('specialty null → libellé de repli, pas de geo → hasLocation false',
        () {
      final dto = ProviderResultDto.fromJson({
        'provider_id': 'p1',
        'display_name': 'Cabinet X',
        'is_listed': true,
      });
      final domain = dto.toDomain();
      expect(domain.specialty, 'Praticien');
      expect(domain.hasLocation, isFalse);
    });
  });

  group('ParsedSearchDto (POST /v1/search/parse)', () {
    test('parse query structurée + interpretation + source', () {
      final dto = ParsedSearchDto.fromJson({
        'query': {
          'q': 'dentiste',
          'specialty': 'Chirurgie dentaire',
          'place': 'Bastille',
          'near': 'Paris',
          'sector': '1',
          'available': true,
          'teleconsult': false,
        },
        'interpretation': 'Dentiste secteur 1 près de Bastille',
        'source': 'llm',
      });
      final domain = dto.toDomain();
      expect(domain.query.q, 'dentiste');
      expect(domain.query.specialty, 'Chirurgie dentaire');
      expect(domain.query.sector, '1');
      expect(domain.query.available, isTrue);
      expect(domain.query.teleconsult, isFalse);
      expect(domain.interpretation, 'Dentiste secteur 1 près de Bastille');
      expect(domain.source, 'llm');
    });

    test('champs absents → valeurs de repli (q vide, source keywords)', () {
      final dto = ParsedSearchDto.fromJson({'query': {}});
      final domain = dto.toDomain();
      expect(domain.query.q, '');
      expect(domain.query.specialty, isNull);
      expect(domain.interpretation, '');
      expect(domain.source, 'keywords');
    });
  });

  group('SlotDto.fromAvailabilityJson (GET /providers/:id/availability)', () {
    test('parse slot_id/starts_at/ends_at', () {
      final dto = SlotDto.fromAvailabilityJson({
        'slot_id': 's1',
        'starts_at': '2026-07-04T09:00:00Z',
        'ends_at': '2026-07-04T09:30:00Z',
        'motif': null,
      });
      final slot = dto.toDomain();
      expect(slot.id, 's1');
      expect(slot.isAvailable, isTrue);
    });
  });

  group('Contrats réels vérifiés sur env déployé (QA)', () {
    test('NotificationDto : kind→type, is_read→read, pas de body', () {
      final dto = NotificationDto.fromJson({
        'id': 'n1',
        'kind': 'rdv_rappel',
        'title': 'Rappel RDV',
        'is_read': false,
        'created_at': '2026-06-02T18:00:00Z',
      });
      final d = dto.toDomain();
      expect(d.title, 'Rappel RDV');
      expect(d.read, isFalse);
      expect(d.body, '');
    });

    test('MessageDto : body→text, created_at→sentAt, conversationId injecté',
        () {
      final dto = MessageDto.fromJson({
        'id': 'm1',
        'body': 'Bonjour',
        'sender': 'patient',
        'created_at': '2026-07-02T09:45:54Z',
        'read_at': null,
      }, conversationId: 'c1');
      final m = dto.toDomain();
      expect(m.text, 'Bonjour');
      expect(m.conversationId, 'c1');
      expect(m.sender.toString(), contains('patient'));
    });

    test('ConversationDto : liste résumé (cabinet_name, unread_count)', () {
      final dto = ConversationDto.fromJson({
        'id': 'c1',
        'cabinet_id': 'cab',
        'cabinet_name': 'Cabinet Lyon',
        'last_message_at': '2026-07-02T09:45:54Z',
        'unread_count': 0,
      });
      final c = dto.toDomain();
      expect(c.cabinetName, 'Cabinet Lyon');
      expect(c.unreadCount, 0);
      expect(c.lastMessage, isNull);
    });

    test('QuoteDto.fromSummaryJson : liste devis (total_amount_cents)', () {
      final q = QuoteDto.fromSummaryJson({
        'id': 'q1',
        'status': 'signed',
        'total_amount_cents': 38000,
        'currency': 'EUR',
        'created_at': '2026-07-03T06:15:29Z',
      }).toDomain();
      expect(q.totalCents, 38000);
      expect(q.status.toString(), contains('signed'));
      expect(q.items, isEmpty);
    });

    test('QuoteDto.fromJson : détail avec items unit_amount_cents/amo_part',
        () {
      final q = QuoteDto.fromJson({
        'id': 'q1',
        'status': 'signed',
        'total_amount_cents': 38000,
        'created_at': '2026-07-03T06:15:29Z',
        'signed_at': '2026-07-03T06:15:29Z',
        'items': [
          {
            'id': 'i1',
            'label': 'Composite',
            'ccam_code': null,
            'tooth': null,
            'unit_amount_cents': 30000,
            'amo_part_cents': 10000,
            'amc_part_cents': 5000
          },
        ],
      }).toDomain();
      expect(q.items, hasLength(1));
      expect(q.items.first.totalCents, 30000);
      expect(q.items.first.patientShareCents, 15000); // 30000-10000-5000
    });
  });
}
