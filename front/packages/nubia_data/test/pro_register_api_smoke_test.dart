import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/auth/pro_register_api.dart';

void main() {
  group('ProRegisterResponseDto — fromJson (smoke POST /v1/pro/register)', () {
    test('désérialise la réponse complète', () {
      final json = {
        'account_id': 'user-42',
        'cabinet_id': 'cab-7',
        'provider_id': 'prov-3',
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.test.sig',
      };
      final dto = ProRegisterResponseDto.fromJson(json);
      expect(dto.accountId, 'user-42');
      expect(dto.cabinetId, 'cab-7');
      expect(dto.providerId, 'prov-3');
      expect(dto.accessToken, 'eyJhbGciOiJIUzI1NiJ9.test.sig');
    });

    test('lève si un champ obligatoire est absent', () {
      final json = {
        'account_id': 'user-42',
        'cabinet_id': 'cab-7',
        // provider_id manquant
        'access_token': 'tok',
      };
      expect(() => ProRegisterResponseDto.fromJson(json), throwsA(anything));
    });
  });
}
