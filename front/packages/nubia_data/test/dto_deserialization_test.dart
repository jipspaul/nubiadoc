import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/scheduling/appointment_dto.dart';
import 'package:nubia_data/src/remote/auth/auth_dto.dart';
import 'package:nubia_data/src/remote/account/account_dto.dart';
import 'package:nubia_data/src/remote/dashboard/dashboard_dto.dart';
import 'package:nubia_data/src/remote/quotes_api.dart';
import 'package:nubia_data/src/remote/payments_api.dart';
import 'package:nubia_data/src/remote/search/search_dto.dart';

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
    test('fromJson désérialise un patient avec données (next_appointment, to_sign, to_pay)', () {
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

    test('fromJson désérialise un patient sans données (null / listes vides)', () {
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

    test('specialty null → libellé de repli, pas de geo → hasLocation false', () {
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
}
