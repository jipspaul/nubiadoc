import 'package:nubia_domain/src/entities/notification_preferences.dart';

class NotificationPreferencesDto {
  // Channels
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;

  // Event types
  final bool appointments;
  final bool documents;
  final bool messages;
  final bool payments;
  final bool prevention;

  /// Heures calmes (#5313) : aucun champ `notification_preference` n'existe
  /// encore côté API pour cette plage horaire. Ni lu depuis le GET, ni
  /// envoyé au PATCH — porté ici uniquement pour que [toDomain]/[fromDomain]
  /// restent symétriques ; la persistance réelle attend le support API.
  final bool quietHours;

  const NotificationPreferencesDto({
    required this.pushEnabled,
    required this.emailEnabled,
    required this.smsEnabled,
    required this.appointments,
    required this.documents,
    required this.messages,
    required this.payments,
    required this.prevention,
    this.quietHours = true,
  });

  /// Un type d'événement (topic) n'a pas de champ booléen unique côté API :
  /// chaque topic a 1-3 canaux (`email_x`/`push_x`[/`sms_x`]). Un interrupteur
  /// de catégorie est considéré "actif" seulement si TOUS ses canaux le sont
  /// (#3829 — avant ce fix, `appointments`/`documents`/`payments`/`prevention`
  /// étaient des clés inventées, absentes du contrat API, silencieusement
  /// droppées par serde côté PATCH et jamais renvoyées par le GET).
  static bool _allTrue(Map<String, dynamic> json, List<String> keys) =>
      keys.every((k) => (json[k] as bool?) ?? true);

  factory NotificationPreferencesDto.fromJson(Map<String, dynamic> json) =>
      NotificationPreferencesDto(
        pushEnabled: json['push_rdv'] as bool? ?? true,
        emailEnabled: json['email_rdv'] as bool? ?? true,
        smsEnabled: json['sms_rdv'] as bool? ?? true,
        appointments: _allTrue(json, ['push_rdv', 'email_rdv', 'sms_rdv']),
        documents: _allTrue(json, ['email_documents', 'push_documents']),
        messages: _allTrue(json, ['email_messagerie', 'push_messagerie']),
        payments: _allTrue(json, ['email_paiement', 'push_paiement']),
        prevention: _allTrue(json, ['email_rappels', 'push_rappels']),
      );

  Map<String, dynamic> toJson() => {
        'push_rdv': pushEnabled && appointments,
        'email_rdv': emailEnabled && appointments,
        'sms_rdv': smsEnabled && appointments,
        'email_documents': documents,
        'push_documents': documents,
        'email_messagerie': messages,
        'push_messagerie': messages,
        'email_paiement': payments,
        'push_paiement': payments,
        'email_rappels': prevention,
        'push_rappels': prevention,
      };

  NotificationPreferences toDomain() => NotificationPreferences(
        pushEnabled: pushEnabled,
        emailEnabled: emailEnabled,
        smsEnabled: smsEnabled,
        appointments: appointments,
        documents: documents,
        messages: messages,
        payments: payments,
        prevention: prevention,
        quietHours: quietHours,
      );

  factory NotificationPreferencesDto.fromDomain(
    NotificationPreferences prefs,
  ) =>
      NotificationPreferencesDto(
        pushEnabled: prefs.pushEnabled,
        emailEnabled: prefs.emailEnabled,
        smsEnabled: prefs.smsEnabled,
        appointments: prefs.appointments,
        documents: prefs.documents,
        messages: prefs.messages,
        payments: prefs.payments,
        prevention: prefs.prevention,
        quietHours: prefs.quietHours,
      );
}
