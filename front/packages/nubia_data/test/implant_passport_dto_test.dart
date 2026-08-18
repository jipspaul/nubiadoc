import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/implant_passport/implant_passport_dto.dart';

void main() {
  group('ImplantItemDto', () {
    test('fromJson lit tous les champs détail sur un payload complet (#5330)', () {
      final dto = ImplantItemDto.fromJson({
        'id': 'implant-1',
        'brand': 'Nobel Biocare',
        'manufacturer': 'Nobel Biocare',
        'model': 'Replace Select Tapered',
        'reference': '36214',
        'dimensions': 'Ø 4,3 mm · L 11,5 mm',
        'material': 'Titane grade 4',
        'mri_compatibility': 'Compatible IRM sous conditions',
        'practitioner': 'Dr Marc Lefèvre',
        'office': 'Nubia Opéra, Paris 2e',
        'prosthesis': 'Couronne céramo-métallique',
        'last_control_date': '4 juillet 2026',
        'next_control': 'Mars 2027 · annuel',
      });

      expect(dto.id, 'implant-1');
      expect(dto.brand, 'Nobel Biocare');
      expect(dto.manufacturer, 'Nobel Biocare');
      expect(dto.model, 'Replace Select Tapered');
      expect(dto.reference, '36214');
      expect(dto.dimensions, 'Ø 4,3 mm · L 11,5 mm');
      expect(dto.material, 'Titane grade 4');
      expect(dto.mriCompatibility, 'Compatible IRM sous conditions');
      expect(dto.practitioner, 'Dr Marc Lefèvre');
      expect(dto.office, 'Nubia Opéra, Paris 2e');
      expect(dto.prosthesis, 'Couronne céramo-métallique');
      expect(dto.lastControlDate, '4 juillet 2026');
      expect(dto.nextControl, 'Mars 2027 · annuel');

      final entity = dto.toDomain();
      expect(entity.manufacturer, 'Nobel Biocare');
      expect(entity.model, 'Replace Select Tapered');
      expect(entity.reference, '36214');
      expect(entity.dimensions, 'Ø 4,3 mm · L 11,5 mm');
      expect(entity.material, 'Titane grade 4');
      expect(entity.mriCompatibility, 'Compatible IRM sous conditions');
    });

    test('fromJson tolère un payload minimal — nouveaux champs à null sans crash', () {
      final dto = ImplantItemDto.fromJson({
        'id': 'implant-2',
        'brand': 'Straumann',
      });

      expect(dto.id, 'implant-2');
      expect(dto.brand, 'Straumann');
      expect(dto.manufacturer, isNull);
      expect(dto.model, isNull);
      expect(dto.reference, isNull);
      expect(dto.dimensions, isNull);
      expect(dto.material, isNull);
      expect(dto.mriCompatibility, isNull);

      final entity = dto.toDomain();
      expect(entity.brand, 'Straumann');
      expect(entity.manufacturer, isNull);
      expect(entity.model, isNull);
      expect(entity.reference, isNull);
      expect(entity.dimensions, isNull);
      expect(entity.material, isNull);
      expect(entity.mriCompatibility, isNull);
    });
  });
}
