import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';

void main() {
  group('NotificationPreferencesDto', () {
    // Régression #3829 : les 4 interrupteurs de catégorie (Rendez-vous/
    // Documents/Paiements/Prévention) émettaient des clés inventées
    // (appointments/documents/payments/prevention) que l'API ne connaît
    // pas — serde les droppait silencieusement (200, rien persisté) et le
    // GET suivant ne les renvoyait jamais, donc fromJson retombait sur le
    // défaut `true` : les interrupteurs revenaient sur ON après rechargement.
    test('toJson émet les vrais champs API par canal, pas les clés inventées',
        () {
      const prefs = NotificationPreferencesDto(
        pushEnabled: true,
        emailEnabled: true,
        smsEnabled: true,
        appointments: false,
        documents: false,
        messages: true,
        payments: false,
        prevention: false,
      );

      final json = prefs.toJson();

      expect(json.containsKey('appointments'), isFalse);
      expect(json.containsKey('documents'), isFalse);
      expect(json.containsKey('payments'), isFalse);
      expect(json.containsKey('prevention'), isFalse);

      expect(json['push_rdv'], isFalse);
      expect(json['email_rdv'], isFalse);
      expect(json['sms_rdv'], isFalse);
      expect(json['email_documents'], isFalse);
      expect(json['push_documents'], isFalse);
      expect(json['email_messagerie'], isTrue);
      expect(json['push_messagerie'], isTrue);
      expect(json['email_paiement'], isFalse);
      expect(json['push_paiement'], isFalse);
      expect(json['email_rappels'], isFalse);
      expect(json['push_rappels'], isFalse);
    });

    test('fromJson reconstruit chaque catégorie depuis ses vrais canaux', () {
      final dto = NotificationPreferencesDto.fromJson({
        'push_rdv': true,
        'email_rdv': true,
        'sms_rdv': true,
        'email_documents': false,
        'push_documents': false,
        'email_messagerie': true,
        'push_messagerie': true,
        'email_paiement': false,
        'push_paiement': false,
        'email_rappels': false,
        'push_rappels': false,
      });

      expect(dto.appointments, isTrue);
      expect(dto.documents, isFalse);
      expect(dto.messages, isTrue);
      expect(dto.payments, isFalse);
      expect(dto.prevention, isFalse);
    });

    test('un aller-retour toJson→fromJson préserve l\'état coupé (idempotent)',
        () {
      const prefs = NotificationPreferencesDto(
        pushEnabled: true,
        emailEnabled: true,
        smsEnabled: true,
        appointments: true,
        documents: false,
        messages: true,
        payments: false,
        prevention: false,
      );

      final roundTripped = NotificationPreferencesDto.fromJson(prefs.toJson());

      expect(roundTripped.appointments, prefs.appointments);
      expect(roundTripped.documents, prefs.documents);
      expect(roundTripped.messages, prefs.messages);
      expect(roundTripped.payments, prefs.payments);
      expect(roundTripped.prevention, prefs.prevention);
    });

    // #5313 : heures calmes n'a pas encore de champ API — ne doit ni être
    // envoyé au PATCH, ni requis en lecture (le GET ne le renvoie jamais).
    test('quietHours n\'est pas envoyé au PATCH (pas de champ API)', () {
      const prefs = NotificationPreferencesDto(
        pushEnabled: true,
        emailEnabled: true,
        smsEnabled: true,
        appointments: true,
        documents: true,
        messages: true,
        payments: true,
        prevention: true,
        quietHours: false,
      );

      expect(prefs.toJson().containsKey('quietHours'), isFalse);
    });

    test('fromJson défaut quietHours à true en l\'absence de champ API', () {
      final dto = NotificationPreferencesDto.fromJson({
        'push_rdv': true,
        'email_rdv': true,
        'sms_rdv': true,
      });

      expect(dto.quietHours, isTrue);
    });
  });
}
