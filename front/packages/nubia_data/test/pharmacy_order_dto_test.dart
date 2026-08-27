import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

void main() {
  group('PharmacyOrderDto.lines (#4996)', () {
    final baseJson = {
      'id': 'o1',
      'pharmacy_id': 'p1',
      'prescription_id': 'rx1',
      'status': 'received',
      'received_at': '2026-08-01T10:00:00Z',
      'updated_at': '2026-08-01T10:05:00Z',
    };

    test('lines[] absent → liste vide, pas d’erreur de parsing', () {
      final order = PharmacyOrderDto.fromJson(baseJson).toDomain();

      expect(order.lines, isEmpty);
      expect(order.lineCount, isNull);
    });

    test(
        'lines[] présent → mappé vers PrescriptionItem, même modèle que côté '
        'pharmacien (GetPharmacyOrderPrescriptionUseCase)', () {
      final order = PharmacyOrderDto.fromJson({
        ...baseJson,
        'lines': [
          {
            'label': 'Amoxicilline 1 g',
            'form': 'comprimé',
            'posology': '1 matin et soir',
            'duration': '7 jours',
            'quantity': '14 comprimés',
          },
        ],
      }).toDomain();

      expect(order.lines, hasLength(1));
      expect(order.lines.single, isA<PrescriptionItem>());
      expect(order.lines.single.label, 'Amoxicilline 1 g');
      expect(order.lines.single.posology, '1 matin et soir');
      // line_count absent côté back → dérivé de la longueur de lines[].
      expect(order.lineCount, 1);
    });
  });
}
