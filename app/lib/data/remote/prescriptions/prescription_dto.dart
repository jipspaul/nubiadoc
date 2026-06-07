import 'package:nubia_patient/domain/entities/prescription.dart';

class PrescriptionItemDto {
  final String label;
  final String? form;
  final String posology;
  final String duration;
  final String quantity;

  const PrescriptionItemDto({
    required this.label,
    this.form,
    required this.posology,
    required this.duration,
    required this.quantity,
  });

  factory PrescriptionItemDto.fromJson(Map<String, dynamic> json) =>
      PrescriptionItemDto(
        label: json['label'] as String,
        form: json['form'] as String?,
        posology: json['posology'] as String,
        duration: json['duration'] as String,
        quantity: json['quantity'] as String,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        if (form != null) 'form': form,
        'posology': posology,
        'duration': duration,
        'quantity': quantity,
      };

  PrescriptionItem toDomain() => PrescriptionItem(
        label: label,
        form: form,
        posology: posology,
        duration: duration,
        quantity: quantity,
      );

  static PrescriptionItemDto fromDomain(PrescriptionItem item) =>
      PrescriptionItemDto(
        label: item.label,
        form: item.form,
        posology: item.posology,
        duration: item.duration,
        quantity: item.quantity,
      );
}

class PrescriptionDto {
  final String id;
  final String patientId;
  final List<PrescriptionItemDto> items;
  final String status; // 'draft' | 'signed'
  final String createdAt; // ISO-8601

  const PrescriptionDto({
    required this.id,
    required this.patientId,
    required this.items,
    required this.status,
    required this.createdAt,
  });

  factory PrescriptionDto.fromJson(Map<String, dynamic> json) => PrescriptionDto(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => PrescriptionItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: json['status'] as String,
        createdAt: json['created_at'] as String,
      );

  Prescription toDomain() => Prescription(
        id: id,
        patientId: patientId,
        items: items.map((i) => i.toDomain()).toList(),
        status: status == 'signed'
            ? PrescriptionStatus.signed
            : PrescriptionStatus.draft,
        createdAt: DateTime.parse(createdAt),
      );
}
