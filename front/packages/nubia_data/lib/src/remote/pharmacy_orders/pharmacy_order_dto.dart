import 'package:nubia_data/src/remote/pharmacy_directory/pharmacy_dto.dart';
import 'package:nubia_data/src/remote/prescriptions/prescription_dto.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';

class PharmacyOrderDto {
  final String id;
  final String pharmacyId;
  final String? pharmacyName;
  final String? pharmacyAddress;
  final String? pharmacyPhone;
  final String? patientDisplayName;
  final String? orderRef;
  final String? prescriberName;
  final String? prescriberPractice;
  final String prescriptionId;
  final String status;
  final String? rejectionReason;
  final String createdAt;
  final String? updatedAt;
  final String? readyAt;
  final String? pickedUpAt;

  /// Fenêtre de conservation du retrait — champ backend pas encore exposé,
  /// parsé défensivement pour être prêt dès qu'il existera (#5348).
  final String? pickupDeadline;
  final int? lineCount;

  /// Même contrat que `GET /pharmacy/orders/:id/items` côté pharmacien
  /// (#5349), exposé aussi par `GET /account/orders/:id` depuis #5644 —
  /// seule source de vérité posologie entre les deux vues (#4996). `lines[]`
  /// absent → liste vide, la carte « Votre ordonnance » ne s'affiche pas.
  final List<PrescriptionItemDto> lines;
  final int? billingTotalCents;
  final int? billingAmoShareCents;
  final int? billingAmcShareCents;
  final int? billingPatientShareCents;

  const PharmacyOrderDto({
    required this.id,
    required this.pharmacyId,
    this.pharmacyName,
    this.pharmacyAddress,
    this.pharmacyPhone,
    this.patientDisplayName,
    this.orderRef,
    this.prescriberName,
    this.prescriberPractice,
    required this.prescriptionId,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    this.updatedAt,
    this.readyAt,
    this.pickedUpAt,
    this.pickupDeadline,
    this.lineCount,
    this.lines = const [],
    this.billingTotalCents,
    this.billingAmoShareCents,
    this.billingAmcShareCents,
    this.billingPatientShareCents,
  });

  factory PharmacyOrderDto.fromJson(Map<String, dynamic> json) =>
      PharmacyOrderDto(
        id: json['id'] as String,
        pharmacyId: json['pharmacy_id'] as String? ?? '',
        pharmacyName: json['pharmacy_name'] as String?,
        pharmacyAddress: PharmacyDto.formatAddress(json['pharmacy_address']),
        pharmacyPhone: json['pharmacy_phone'] as String?,
        patientDisplayName: json['patient_display_name'] as String?,
        orderRef: json['order_ref'] as String?,
        prescriberName: json['prescriber_name'] as String?,
        prescriberPractice: json['prescriber_practice'] as String?,
        prescriptionId: json['prescription_id'] as String? ?? '',
        status: json['status'] as String? ?? 'received',
        rejectionReason: json['rejection_reason'] as String?,
        createdAt: (json['received_at'] ?? json['created_at']) as String? ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        updatedAt: json['updated_at'] as String?,
        readyAt: json['ready_at'] as String?,
        pickedUpAt: json['picked_up_at'] as String?,
        pickupDeadline: json['pickup_deadline'] as String?,
        lineCount:
            json['line_count'] as int? ?? (json['lines'] as List?)?.length,
        lines: (json['lines'] as List?)
                ?.map((e) =>
                    PrescriptionItemDto.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        billingTotalCents: (json['billing_total_cents'] as num?)?.toInt(),
        billingAmoShareCents:
            (json['billing_amo_share_cents'] as num?)?.toInt(),
        billingAmcShareCents:
            (json['billing_amc_share_cents'] as num?)?.toInt(),
        billingPatientShareCents:
            (json['billing_patient_share_cents'] as num?)?.toInt(),
      );

  PharmacyOrder toDomain() {
    final created = DateTime.parse(createdAt);
    return PharmacyOrder(
      id: id,
      pharmacyId: pharmacyId,
      pharmacyName: pharmacyName,
      pharmacyAddress: pharmacyAddress,
      pharmacyPhone: pharmacyPhone,
      patientDisplayName: patientDisplayName,
      orderRef: orderRef,
      prescriberName: prescriberName,
      prescriberPractice: prescriberPractice,
      prescriptionId: prescriptionId,
      status: parseStatus(status),
      rejectionReason: rejectionReason,
      createdAt: created,
      updatedAt: updatedAt != null ? DateTime.parse(updatedAt!) : created,
      readyAt: readyAt != null ? DateTime.parse(readyAt!) : null,
      pickedUpAt: pickedUpAt != null ? DateTime.parse(pickedUpAt!) : null,
      pickupDeadline:
          pickupDeadline != null ? DateTime.parse(pickupDeadline!) : null,
      lineCount: lineCount,
      lines: lines.map((e) => e.toDomain()).toList(),
      billingTotalCents: billingTotalCents,
      billingAmoShareCents: billingAmoShareCents,
      billingAmcShareCents: billingAmcShareCents,
      billingPatientShareCents: billingPatientShareCents,
    );
  }

  /// Statut inconnu → received (défensif : un nouveau statut back ne doit
  /// pas faire planter l'app, la commande reste visible en entrée de file).
  static PharmacyOrderStatus parseStatus(String value) {
    switch (value) {
      case 'preparing':
        return PharmacyOrderStatus.preparing;
      case 'ready':
        return PharmacyOrderStatus.ready;
      case 'picked_up':
        return PharmacyOrderStatus.pickedUp;
      case 'rejected':
        return PharmacyOrderStatus.rejected;
      case 'cancelled':
        return PharmacyOrderStatus.cancelled;
      case 'received':
      default:
        return PharmacyOrderStatus.received;
    }
  }

  static String statusToApi(PharmacyOrderStatus status) {
    switch (status) {
      case PharmacyOrderStatus.received:
        return 'received';
      case PharmacyOrderStatus.preparing:
        return 'preparing';
      case PharmacyOrderStatus.ready:
        return 'ready';
      case PharmacyOrderStatus.pickedUp:
        return 'picked_up';
      case PharmacyOrderStatus.rejected:
        return 'rejected';
      case PharmacyOrderStatus.cancelled:
        return 'cancelled';
    }
  }
}
