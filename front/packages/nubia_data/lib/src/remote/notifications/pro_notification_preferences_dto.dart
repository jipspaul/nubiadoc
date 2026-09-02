import 'package:nubia_domain/src/entities/pro_notification_preferences.dart';

/// Mappe 1:1 le contrat `GET/PATCH /v1/me/notification-preferences` (#6257) —
/// contrairement à [NotificationPreferencesDto], chaque catégorie a déjà un
/// champ booléen unique côté API, pas de reconstruction par canal nécessaire.
class ProNotificationPreferencesDto {
  final bool inappRdv;
  final bool inappMessagerie;
  final bool inappDevis;
  final bool inappStock;
  final bool inappLabo;
  final bool inappVisites;
  final bool emailRdv;
  final bool emailMessagerie;
  final bool emailDevis;

  const ProNotificationPreferencesDto({
    required this.inappRdv,
    required this.inappMessagerie,
    required this.inappDevis,
    required this.inappStock,
    required this.inappLabo,
    required this.inappVisites,
    required this.emailRdv,
    required this.emailMessagerie,
    required this.emailDevis,
  });

  factory ProNotificationPreferencesDto.fromJson(Map<String, dynamic> json) =>
      ProNotificationPreferencesDto(
        inappRdv: json['inapp_rdv'] as bool? ?? true,
        inappMessagerie: json['inapp_messagerie'] as bool? ?? true,
        inappDevis: json['inapp_devis'] as bool? ?? true,
        inappStock: json['inapp_stock'] as bool? ?? true,
        inappLabo: json['inapp_labo'] as bool? ?? true,
        inappVisites: json['inapp_visites'] as bool? ?? true,
        emailRdv: json['email_rdv'] as bool? ?? false,
        emailMessagerie: json['email_messagerie'] as bool? ?? false,
        emailDevis: json['email_devis'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'inapp_rdv': inappRdv,
        'inapp_messagerie': inappMessagerie,
        'inapp_devis': inappDevis,
        'inapp_stock': inappStock,
        'inapp_labo': inappLabo,
        'inapp_visites': inappVisites,
        'email_rdv': emailRdv,
        'email_messagerie': emailMessagerie,
        'email_devis': emailDevis,
      };

  ProNotificationPreferences toDomain() => ProNotificationPreferences(
        inappRdv: inappRdv,
        inappMessagerie: inappMessagerie,
        inappDevis: inappDevis,
        inappStock: inappStock,
        inappLabo: inappLabo,
        inappVisites: inappVisites,
        emailRdv: emailRdv,
        emailMessagerie: emailMessagerie,
        emailDevis: emailDevis,
      );

  factory ProNotificationPreferencesDto.fromDomain(
    ProNotificationPreferences prefs,
  ) =>
      ProNotificationPreferencesDto(
        inappRdv: prefs.inappRdv,
        inappMessagerie: prefs.inappMessagerie,
        inappDevis: prefs.inappDevis,
        inappStock: prefs.inappStock,
        inappLabo: prefs.inappLabo,
        inappVisites: prefs.inappVisites,
        emailRdv: prefs.emailRdv,
        emailMessagerie: prefs.emailMessagerie,
        emailDevis: prefs.emailDevis,
      );
}
