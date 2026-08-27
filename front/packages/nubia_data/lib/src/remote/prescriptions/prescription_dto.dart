import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/entities/prescription_template.dart';

class PrescriptionItemDto {
  final String label;
  final String? form;
  final String posology;
  final String duration;
  final String quantity;
  final String? nonSubstitutionReason;
  final bool nonRenouvelable;

  const PrescriptionItemDto({
    required this.label,
    this.form,
    required this.posology,
    required this.duration,
    required this.quantity,
    this.nonSubstitutionReason,
    this.nonRenouvelable = false,
  });

  factory PrescriptionItemDto.fromJson(Map<String, dynamic> json) =>
      PrescriptionItemDto(
        label: json['label'] as String,
        form: json['form'] as String?,
        posology: json['posology'] as String,
        duration: json['duration'] as String,
        quantity: json['quantity'] as String? ?? '',
        nonSubstitutionReason: json['non_substitution_reason'] as String?,
        nonRenouvelable: json['non_renouvelable'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        if (form != null) 'form': form,
        'posology': posology,
        'duration': duration,
        'quantity': quantity,
        if (nonSubstitutionReason != null)
          'non_substitution_reason': nonSubstitutionReason,
        'non_renouvelable': nonRenouvelable,
      };

  PrescriptionItem toDomain() => PrescriptionItem(
        label: label,
        form: form,
        posology: posology,
        duration: duration,
        quantity: quantity,
        nonSubstitutionReason: nonSubstitutionReason,
        nonRenouvelable: nonRenouvelable,
      );

  static PrescriptionItemDto fromDomain(PrescriptionItem item) =>
      PrescriptionItemDto(
        label: item.label,
        form: item.form,
        posology: item.posology,
        duration: item.duration,
        quantity: item.quantity,
        nonSubstitutionReason: item.nonSubstitutionReason,
        nonRenouvelable: item.nonRenouvelable,
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

  factory PrescriptionDto.fromJson(Map<String, dynamic> json) =>
      PrescriptionDto(
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
        status: switch (status) {
          'signed' => PrescriptionStatus.signed,
          'sent' => PrescriptionStatus.sent,
          _ => PrescriptionStatus.draft,
        },
        createdAt: DateTime.parse(createdAt),
      );
}

class PrescriptionTemplateDto {
  final String id;
  final String label;
  final List<PrescriptionItem> items;
  final bool isGlobal;

  const PrescriptionTemplateDto({
    required this.id,
    required this.label,
    required this.items,
    required this.isGlobal,
  });

  /// Contrat réel (`prescription_templates.rs`) : `items` est un tableau
  /// jsonb libre côté back (`{label, form, posology, duration, quantity}`),
  /// `quantity` peut être `null` — repli sur chaîne vide plutôt qu'un cast
  /// qui planterait sur un modèle sans quantité renseignée.
  factory PrescriptionTemplateDto.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return PrescriptionTemplateDto(
      id: json['id'] as String,
      label: json['label'] as String,
      isGlobal: json['is_global'] as bool? ?? false,
      items: rawItems.map((e) {
        final m = e as Map<String, dynamic>;
        return PrescriptionItem(
          label: m['label'] as String? ?? '',
          form: m['form'] as String?,
          posology: m['posology'] as String? ?? '',
          duration: m['duration'] as String? ?? '',
          quantity: m['quantity'] as String? ?? '',
        );
      }).toList(),
    );
  }

  PrescriptionTemplate toDomain() => PrescriptionTemplate(
        id: id,
        label: label,
        items: items,
        isGlobal: isGlobal,
      );
}
