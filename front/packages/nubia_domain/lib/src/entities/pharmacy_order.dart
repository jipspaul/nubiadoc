import 'package:equatable/equatable.dart';

/// Statuts d'une commande click-and-collect.
///
/// Cycle nominal : received → preparing → ready → pickedUp.
/// Terminaux : pickedUp, rejected (pharmacien, motif requis),
/// cancelled (patient, uniquement depuis received/preparing).
enum PharmacyOrderStatus {
  received,
  preparing,
  ready,
  pickedUp,
  rejected,
  cancelled;

  /// Transitions autorisées — miroir de la machine à états serveur
  /// (le serveur reste l'autorité : transition illégale → 409).
  bool canTransitionTo(PharmacyOrderStatus next) {
    switch (this) {
      case PharmacyOrderStatus.received:
        return next == PharmacyOrderStatus.preparing ||
            next == PharmacyOrderStatus.rejected ||
            next == PharmacyOrderStatus.cancelled;
      case PharmacyOrderStatus.preparing:
        return next == PharmacyOrderStatus.ready ||
            next == PharmacyOrderStatus.cancelled;
      case PharmacyOrderStatus.ready:
        return next == PharmacyOrderStatus.pickedUp;
      case PharmacyOrderStatus.pickedUp:
      case PharmacyOrderStatus.rejected:
      case PharmacyOrderStatus.cancelled:
        return false;
    }
  }

  bool get isTerminal =>
      this == PharmacyOrderStatus.pickedUp ||
      this == PharmacyOrderStatus.rejected ||
      this == PharmacyOrderStatus.cancelled;
}

/// Commande click-and-collect liée à une ordonnance.
///
/// Entité partagée entre la vue pharmacie (patientDisplayName renseigné)
/// et la vue patient (pharmacyName renseigné).
class PharmacyOrder extends Equatable {
  final String id;
  final String pharmacyId;
  final String? pharmacyName;
  final String? patientDisplayName;

  /// Référence courte affichable (ex. `CMD-4821`, colonne contexte #4926) —
  /// `null` tant que le contrat back ne l'expose pas.
  final String? orderRef;
  final String? prescriberName;
  final String? prescriberPractice;
  final String prescriptionId;
  final PharmacyOrderStatus status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;
  final int? lineCount;

  /// Ventilation facturation (fournie par le back, cf. #4063 côté patient) —
  /// null tant qu'aucun devis n'est facturé sur la commande : le bloc
  /// facturation ne s'affiche alors pas (#4888).
  final int? billingTotalCents;
  final int? billingAmoShareCents;
  final int? billingAmcShareCents;
  final int? billingPatientShareCents; // « à encaisser »

  const PharmacyOrder({
    required this.id,
    required this.pharmacyId,
    this.pharmacyName,
    this.patientDisplayName,
    this.orderRef,
    this.prescriberName,
    this.prescriberPractice,
    required this.prescriptionId,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.readyAt,
    this.pickedUpAt,
    this.lineCount,
    this.billingTotalCents,
    this.billingAmoShareCents,
    this.billingAmcShareCents,
    this.billingPatientShareCents,
  });

  /// Le QR de retrait n'existe que pour une commande prête.
  bool get canShowPickupCode => status == PharmacyOrderStatus.ready;

  /// Le bloc facturation ne s'affiche que si le back a renseigné les 4
  /// montants (pas de calcul front — #4888).
  bool get hasBillingSummary =>
      billingTotalCents != null &&
      billingAmoShareCents != null &&
      billingAmcShareCents != null &&
      billingPatientShareCents != null;

  @override
  List<Object?> get props => [id, status, updatedAt];
}
