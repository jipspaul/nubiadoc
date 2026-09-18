//! #6780 (QA-20260909-1) — un patient qui n'a pas encore d'odontogramme ni
//! de bilan parodontal reçoit de l'API `updated_at: null` /
//! `measured_at: null` (contrat documenté dans `api/src/dental_chart.rs`
//! et `api/src/periodontal_chart.rs`). Le décodage doit produire un modèle
//! valide « vierge », pas un `TypeError` avalé en `ParseFailure`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/dental_chart/dental_chart_dto.dart';
import 'package:nubia_data/src/remote/periodontal_chart/periodontal_chart_dto.dart';

/// Passe par `jsonDecode` comme Dio : les corps ci-dessous sont copiés
/// verbatim des réponses `200` de l'API live citées dans l'issue.
Map<String, dynamic> body(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

void main() {
  group('DentalChartDto — patient sans odontogramme (#6780)', () {
    test('décode `{"teeth":{},"updated_at":null}` en chart vierge', () {
      final dto = DentalChartDto.fromJson(
        body('{"teeth":{},"updated_at":null}'),
      );

      expect(dto.teeth, isEmpty);
      expect(dto.updatedAt, isNull);

      final chart = dto.toDomain();
      expect(chart.teeth, isEmpty);
      expect(chart.updatedAt, isNull);
      expect(chart.isBlank, isTrue);
    });

    test('décode un JSON sans clé `updated_at` ni `teeth`', () {
      final chart = DentalChartDto.fromJson(body('{}')).toDomain();

      expect(chart.teeth, isEmpty);
      expect(chart.updatedAt, isNull);
    });

    test('conserve la date quand elle est renseignée', () {
      final chart = DentalChartDto.fromJson(body(
        '{"teeth":{"11":{"status":"carie"}},'
        '"updated_at":"2026-09-09T00:05:15.405894+00:00"}',
      )).toDomain();

      expect(chart.teeth['11']?.status, 'carie');
      expect(chart.updatedAt, DateTime.utc(2026, 9, 9, 0, 5, 15, 405, 894));
      expect(chart.isBlank, isFalse);
    });

    test('toJson n\'envoie que `teeth` (le PUT refuse les champs inconnus)',
        () {
      final json = DentalChartDto.fromJson(body(
        '{"teeth":{"11":{"status":"sain"}},"updated_at":null}',
      )).toJson();

      expect(json.keys, ['teeth']);
    });
  });

  group('PeriodontalChartDto — patient sans bilan (#6780)', () {
    test(
        'décode `{"sites":{},"indices":{},"measured_at":null}` en bilan vierge',
        () {
      final dto = PeriodontalChartDto.fromJson(
        body('{"sites":{},"indices":{},"measured_at":null}'),
      );

      expect(dto.sites, isEmpty);
      expect(dto.indices, isEmpty);
      expect(dto.measuredAt, isNull);

      final chart = dto.toDomain();
      expect(chart.sites, isEmpty);
      expect(chart.indices, isEmpty);
      expect(chart.measuredAt, isNull);
      expect(chart.isBlank, isTrue);
    });

    test('décode un JSON sans aucune clé', () {
      final chart = PeriodontalChartDto.fromJson(body('{}')).toDomain();

      expect(chart.sites, isEmpty);
      expect(chart.indices, isEmpty);
      expect(chart.measuredAt, isNull);
    });

    test('conserve la date et les valeurs quand elles sont renseignées', () {
      final chart = PeriodontalChartDto.fromJson(body(
        '{"sites":{"11":{"mv":3,"v":2}},"indices":{"plaque":12},'
        '"measured_at":"2026-09-09T00:05:15+00:00"}',
      )).toDomain();

      expect(chart.sites['11']?.mv, 3);
      expect(chart.sites['11']?.dl, isNull);
      expect(chart.indices['plaque'], 12.0);
      expect(chart.measuredAt, DateTime.utc(2026, 9, 9, 0, 5, 15));
      expect(chart.isBlank, isFalse);
    });

    test('toJson n\'envoie que `sites` et `indices`', () {
      final json = PeriodontalChartDto.fromJson(
        body('{"sites":{},"indices":{},"measured_at":null}'),
      ).toJson();

      expect(json.keys, ['sites', 'indices']);
    });
  });
}
