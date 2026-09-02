import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';

void main() {
  group('ProNotificationPreferencesDto', () {
    test('fromJson lit les 9 clés API directement (#6257)', () {
      final dto = ProNotificationPreferencesDto.fromJson({
        'inapp_rdv': false,
        'inapp_messagerie': true,
        'inapp_devis': true,
        'inapp_stock': false,
        'inapp_labo': true,
        'inapp_visites': true,
        'email_rdv': true,
        'email_messagerie': false,
        'email_devis': true,
      });

      expect(dto.inappRdv, isFalse);
      expect(dto.inappMessagerie, isTrue);
      expect(dto.inappDevis, isTrue);
      expect(dto.inappStock, isFalse);
      expect(dto.inappLabo, isTrue);
      expect(dto.inappVisites, isTrue);
      expect(dto.emailRdv, isTrue);
      expect(dto.emailMessagerie, isFalse);
      expect(dto.emailDevis, isTrue);
    });

    test('fromJson défaut in-app à true et email à false si absents', () {
      final dto = ProNotificationPreferencesDto.fromJson(const {});

      expect(dto.inappRdv, isTrue);
      expect(dto.inappMessagerie, isTrue);
      expect(dto.inappDevis, isTrue);
      expect(dto.inappStock, isTrue);
      expect(dto.inappLabo, isTrue);
      expect(dto.inappVisites, isTrue);
      expect(dto.emailRdv, isFalse);
      expect(dto.emailMessagerie, isFalse);
      expect(dto.emailDevis, isFalse);
    });

    test('toJson émet toutes les clés API', () {
      const dto = ProNotificationPreferencesDto(
        inappRdv: true,
        inappMessagerie: false,
        inappDevis: true,
        inappStock: false,
        inappLabo: true,
        inappVisites: false,
        emailRdv: false,
        emailMessagerie: true,
        emailDevis: false,
      );

      final json = dto.toJson();

      expect(json['inapp_rdv'], isTrue);
      expect(json['inapp_messagerie'], isFalse);
      expect(json['inapp_devis'], isTrue);
      expect(json['inapp_stock'], isFalse);
      expect(json['inapp_labo'], isTrue);
      expect(json['inapp_visites'], isFalse);
      expect(json['email_rdv'], isFalse);
      expect(json['email_messagerie'], isTrue);
      expect(json['email_devis'], isFalse);
    });

    test('un aller-retour toDomain→fromDomain préserve l\'état', () {
      const dto = ProNotificationPreferencesDto(
        inappRdv: false,
        inappMessagerie: true,
        inappDevis: false,
        inappStock: true,
        inappLabo: false,
        inappVisites: true,
        emailRdv: true,
        emailMessagerie: false,
        emailDevis: true,
      );

      final roundTripped =
          ProNotificationPreferencesDto.fromDomain(dto.toDomain());

      expect(roundTripped.inappRdv, dto.inappRdv);
      expect(roundTripped.inappMessagerie, dto.inappMessagerie);
      expect(roundTripped.inappDevis, dto.inappDevis);
      expect(roundTripped.inappStock, dto.inappStock);
      expect(roundTripped.inappLabo, dto.inappLabo);
      expect(roundTripped.inappVisites, dto.inappVisites);
      expect(roundTripped.emailRdv, dto.emailRdv);
      expect(roundTripped.emailMessagerie, dto.emailMessagerie);
      expect(roundTripped.emailDevis, dto.emailDevis);
    });
  });
}
