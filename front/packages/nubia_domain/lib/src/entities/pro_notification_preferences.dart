import 'package:equatable/equatable.dart';

/// Préférences de notification réglables pour un user pro (praticien,
/// secrétariat, pharmacien, infirmier) — `GET/PATCH /v1/me/notification-preferences`.
///
/// Un interrupteur par catégorie in-app + un interrupteur email pour les
/// catégories qui le supportent (rdv/messagerie/devis). Défaut : in-app ON,
/// email OFF (cf. `user_notification_preference`, migration 0246).
class ProNotificationPreferences extends Equatable {
  final bool inappRdv;
  final bool inappMessagerie;
  final bool inappDevis;
  final bool inappStock;
  final bool inappLabo;
  final bool inappVisites;

  final bool emailRdv;
  final bool emailMessagerie;
  final bool emailDevis;

  final bool pushRdv;
  final bool pushMessagerie;
  final bool pushDevis;
  final bool pushStock;
  final bool pushLabo;
  final bool pushVisites;

  const ProNotificationPreferences({
    required this.inappRdv,
    required this.inappMessagerie,
    required this.inappDevis,
    required this.inappStock,
    required this.inappLabo,
    required this.inappVisites,
    required this.emailRdv,
    required this.emailMessagerie,
    required this.emailDevis,
    required this.pushRdv,
    required this.pushMessagerie,
    required this.pushDevis,
    required this.pushStock,
    required this.pushLabo,
    required this.pushVisites,
  });

  /// Défauts avant le premier chargement (miroir des défauts serveur).
  const ProNotificationPreferences.defaults()
      : inappRdv = true,
        inappMessagerie = true,
        inappDevis = true,
        inappStock = true,
        inappLabo = true,
        inappVisites = true,
        emailRdv = false,
        emailMessagerie = false,
        emailDevis = false,
        pushRdv = true,
        pushMessagerie = true,
        pushDevis = true,
        pushStock = true,
        pushLabo = true,
        pushVisites = true;

  ProNotificationPreferences copyWith({
    bool? inappRdv,
    bool? inappMessagerie,
    bool? inappDevis,
    bool? inappStock,
    bool? inappLabo,
    bool? inappVisites,
    bool? emailRdv,
    bool? emailMessagerie,
    bool? emailDevis,
    bool? pushRdv,
    bool? pushMessagerie,
    bool? pushDevis,
    bool? pushStock,
    bool? pushLabo,
    bool? pushVisites,
  }) {
    return ProNotificationPreferences(
      inappRdv: inappRdv ?? this.inappRdv,
      inappMessagerie: inappMessagerie ?? this.inappMessagerie,
      inappDevis: inappDevis ?? this.inappDevis,
      inappStock: inappStock ?? this.inappStock,
      inappLabo: inappLabo ?? this.inappLabo,
      inappVisites: inappVisites ?? this.inappVisites,
      emailRdv: emailRdv ?? this.emailRdv,
      emailMessagerie: emailMessagerie ?? this.emailMessagerie,
      emailDevis: emailDevis ?? this.emailDevis,
      pushRdv: pushRdv ?? this.pushRdv,
      pushMessagerie: pushMessagerie ?? this.pushMessagerie,
      pushDevis: pushDevis ?? this.pushDevis,
      pushStock: pushStock ?? this.pushStock,
      pushLabo: pushLabo ?? this.pushLabo,
      pushVisites: pushVisites ?? this.pushVisites,
    );
  }

  @override
  List<Object?> get props => [
        inappRdv,
        inappMessagerie,
        inappDevis,
        inappStock,
        inappLabo,
        inappVisites,
        emailRdv,
        emailMessagerie,
        emailDevis,
        pushRdv,
        pushMessagerie,
        pushDevis,
        pushStock,
        pushLabo,
        pushVisites,
      ];
}
