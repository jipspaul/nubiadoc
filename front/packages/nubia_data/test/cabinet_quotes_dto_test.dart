import 'package:flutter_test/flutter_test.dart';

import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_data/src/remote/cabinet_quotes/cabinet_quotes_dto.dart';

void main() {
  group('CabinetQuoteDto — signed_at sur la projection LISTE (#6938)', () {
    test(
        'devis signé, JSON forme GET /v1/cabinet/quotes (sans items) → '
        'signedAt non nul côté domaine', () {
      final dto = CabinetQuoteDto.fromJson(const {
        'id': 'quote-1',
        'quote_ref': 'DEV-0701',
        'cabinet_id': 'cabinet-1',
        'patient_id': 'patient-1',
        'patient_name': 'Marc Dubois',
        'total_amount': 1865,
        'patient_share_cents': 1865,
        'status': 'signed',
        'created_at': '2026-09-13T09:00:00Z',
        'signed_at': '2026-09-13T10:30:00Z',
        'deposit_paid': false,
      });

      final quote = dto.toDomain();
      expect(quote.status, CabinetQuoteStatus.signed);
      expect(quote.signedAt, DateTime.parse('2026-09-13T10:30:00Z'));
    });

    test('signed_at absent du JSON → signedAt null, pas de crash', () {
      final dto = CabinetQuoteDto.fromJson(const {
        'id': 'quote-2',
        'quote_ref': 'DEV-0698',
        'cabinet_id': 'cabinet-1',
        'patient_id': 'patient-1',
        'patient_name': 'Marc Dubois',
        'total_amount': 3665,
        'patient_share_cents': 3665,
        'status': 'sent',
        'created_at': '2026-09-12T09:00:00Z',
      });

      expect(dto.toDomain().signedAt, isNull);
    });
  });
}
