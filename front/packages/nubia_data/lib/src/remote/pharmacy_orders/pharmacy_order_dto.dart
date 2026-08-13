import 'package:nubia_domain/src/entities/pharmacy_order.dart';

class PharmacyOrderDto {
  final String id;
  final String pharmacyId;
  final String? pharmacyName;
  final String? patientDisplayName;
  final String? prescriberName;
  final String? prescriberPractice;
  final String prescriptionId;
  final String status;
  final String? rejectionReason;
  final String createdAt;
  final String? updatedAt;
  final String? readyAt;
  final String? pickedUpAt;

  const PharmacyOrderDto({
    required this.id,
    required this.pharmacyId,
    this.pharmacyName,
    this.patientDisplayName,
    this.prescriberName,
    this.prescriberPractice,
    required this.prescriptionId,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    this.updatedAt,
    this.readyAt,
    this.pickedUpAt,
  });

  factory PharmacyOrderDto.fromJson(Map<String, dynamic> json) =>
      PharmacyOrderDto(
        id: json['id'] as String,
        pharmacyId: json['pharmacy_id'] as String? ?? '',
        pharmacyName: json['pharmacy_name'] as String?,
        patientDisplayName: json['patient_display_name'] as String?,
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
      );

  PharmacyOrder toDomain() {
    final created = DateTime.parse(createdAt);
    return PharmacyOrder(
      id: id,
      pharmacyId: pharmacyId,
      pharmacyName: pharmacyName,
      patientDisplayName: patientDisplayName,
      prescriberName: prescriberName,
      prescriberPractice: prescriberPractice,
      prescriptionId: prescriptionId,
      status: parseStatus(status),
      rejectionReason: rejectionReason,
      createdAt: created,
      updatedAt: updatedAt != null ? DateTime.parse(updatedAt!) : created,
      readyAt: readyAt != null ? DateTime.parse(readyAt!) : null,
      pickedUpAt: pickedUpAt != null ? DateTime.parse(pickedUpAt!) : null,
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
