import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';

void main() {
  group('DocumentSignedUrlDto', () {
    // Régression JEL-25 : l'API GET /v1/documents/:id/download renvoie
    // `{"download_url": ...}` mais le DTO lisait `json['url']` → null →
    // « Erreur de décodage de la réponse » à l'ouverture d'un document.
    test('fromJson lit download_url (champ réel de l\'API)', () {
      final dto = DocumentSignedUrlDto.fromJson({
        'download_url': 'https://storage.example.com/abc?token=x',
        'expires_at': '2026-07-13T13:10:51Z',
      });
      expect(dto.url, 'https://storage.example.com/abc?token=x');
    });

    test('fromJson accepte encore le champ legacy url', () {
      final dto = DocumentSignedUrlDto.fromJson({'url': 'https://x/y'});
      expect(dto.url, 'https://x/y');
    });
  });
}
