import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/scheduling/appointment_dto.dart';
import 'package:nubia_data/src/remote/auth/auth_dto.dart';
import 'package:nubia_data/src/remote/account/account_dto.dart';
import 'package:nubia_data/src/remote/quotes_api.dart';
import 'package:nubia_data/src/remote/payments_api.dart';

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

  group('PatientAccountDto (GET /v1/me response)', () {
    test('fromJson désérialise le profil du porteur du token', () {
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
}
