import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

void main() {
  group('PharmacyOrderDto', () {
    test('fromJson nominal + toDomain', () {
      final dto = PharmacyOrderDto.fromJson({
        'id': 'o1',
        'pharmacy_id': 'p1',
        'pharmacy_name': 'Pharmacie du Port',
        'patient_display_name': 'Jean D.',
        'prescription_id': 'rx1',
        'status': 'preparing',
        'received_at': '2026-07-01T10:00:00Z',
        'updated_at': '2026-07-01T11:00:00Z',
      });
      final order = dto.toDomain();

      expect(order.id, 'o1');
      expect(order.status, PharmacyOrderStatus.preparing);
      expect(order.pharmacyName, 'Pharmacie du Port');
      expect(order.patientDisplayName, 'Jean D.');
      expect(order.updatedAt, DateTime.utc(2026, 7, 1, 11));
      expect(order.readyAt, isNull);
    });

    test('champs manquants → valeurs défensives', () {
      final order = PharmacyOrderDto.fromJson({'id': 'o2'}).toDomain();

      expect(order.status, PharmacyOrderStatus.received);
      expect(order.pharmacyId, '');
      expect(order.prescriptionId, '');
      // updatedAt retombe sur createdAt.
      expect(order.updatedAt, order.createdAt);
    });

    test('statut inconnu → received (défensif)', () {
      expect(
        PharmacyOrderDto.parseStatus('nouveau_statut_back'),
        PharmacyOrderStatus.received,
      );
    });

    test('statusToApi couvre tous les statuts (aller-retour)', () {
      for (final status in PharmacyOrderStatus.values) {
        expect(
          PharmacyOrderDto.parseStatus(PharmacyOrderDto.statusToApi(status)),
          status,
        );
      }
    });
  });

  group('PharmacyDto', () {
    test('address jsonb → chaîne formatée', () {
      final dto = PharmacyDto.fromJson({
        'id': 'p1',
        'raison_sociale': 'Pharmacie Centrale',
        'address': {
          'line1': '3 rue Haute',
          'postal_code': '75011',
          'city': 'Paris'
        },
        'distance_m': 850,
      });

      expect(dto.name, 'Pharmacie Centrale');
      expect(dto.address, '3 rue Haute, 75011, Paris');
      expect(dto.toDomain().distanceKm, 0.85);
    });

    test('address chaîne acceptée, champs manquants tolérés', () {
      final dto = PharmacyDto.fromJson({
        'id': 'p2',
        'name': 'Pharmacie B',
        'address': '12 avenue du Sud',
      });
      expect(dto.address, '12 avenue du Sud');
      expect(dto.distanceM, isNull);
    });
  });

  group('StockRequestDto', () {
    test('items jsonb → StockRequestItem, statut mappé', () {
      final request = StockRequestDto.fromJson({
        'id': 's1',
        'pharmacy_id': 'p1',
        'items': [
          {'label': 'Compresses', 'qty': 10, 'note': 'stériles'},
          {'label': 'Sérum phy', 'quantity': 2},
        ],
        'status': 'accepted',
        'created_at': '2026-07-01T10:00:00Z',
      }).toDomain();

      expect(request.items, hasLength(2));
      expect(request.items.first.quantity, 10);
      expect(request.items.last.quantity, 2);
      expect(request.status, StockRequestStatus.accepted);
      expect(request.items.first.availability, isNull);
    });

    test('availability_status jsonb → StockItemAvailability', () {
      final items = StockRequestDto.fromJson({
        'id': 's1',
        'pharmacy_id': 'p1',
        'items': [
          {'label': 'Compresses', 'qty': 10, 'availability_status': 'in_stock'},
          {
            'label': 'Gants nitrile',
            'qty': 5,
            'availability_status': 'limited',
            'available_qty': 2,
          },
          {'label': 'Masques', 'qty': 3, 'availability_status': 'out_of_stock'},
          {'label': 'Compresses B', 'qty': 4},
        ],
        'status': 'sent',
        'created_at': '2026-07-01T10:00:00Z',
      }).toDomain().items;

      expect(
          items[0].availability!.status, StockItemAvailabilityStatus.inStock);
      expect(
          items[1].availability!.status, StockItemAvailabilityStatus.limited);
      expect(items[1].availability!.quantityAvailable, 2);
      expect(items[2].availability!.status,
          StockItemAvailabilityStatus.outOfStock);
      expect(items[3].availability, isNull);
    });
  });

  group('PharmacyQuoteDto', () {
    test('items + total + statut', () {
      final quote = PharmacyQuoteDto.fromJson({
        'id': 'q1',
        'pharmacy_id': 'p1',
        'order_id': 'o1',
        'items': [
          {'label': 'Antalgique', 'qty': 2, 'unit_price_cents': 350},
        ],
        'total_cents': 700,
        'status': 'sent',
        'created_at': '2026-07-01T10:00:00Z',
        'sent_at': '2026-07-01T10:05:00Z',
      }).toDomain();

      expect(quote.items.single.totalCents, 700);
      expect(quote.totalCents, 700);
      expect(quote.status, PharmacyQuoteStatus.sent);
      expect(quote.isDecidable, isTrue);
      expect(quote.orderId, 'o1');
    });
  });
}
