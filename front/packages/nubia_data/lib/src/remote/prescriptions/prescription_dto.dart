import 'package:nubia_domain/src/entities/medication_reference.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/entities/prescription_template.dart';

class MedicationReferenceDto {
  final String id;
  final String dci;
  final String galenicForm;
  final String therapeuticClass;

  const MedicationReferenceDto({
    required this.id,
    required this.dci,
    required this.galenicForm,
    required this.therapeuticClass,
  });

  factory MedicationReferenceDto.fromJson(Map<String, dynamic> json) =>
      MedicationReferenceDto(
        id: json['id'] as String,
        dci: json['dci'] as String,
        galenicForm: json['galenic_form'] as String? ?? '',
        therapeuticClass: json['therapeutic_class'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'dci': dci,
        'galenic_form': galenicForm,
        'therapeutic_class': therapeuticClass,
      };

  MedicationReference toDomain() => MedicationReference(
        id: id,
        dci: dci,
        galenicForm: galenicForm,
        therapeuticClass: therapeuticClass,
      );

  static MedicationReferenceDto fromDomain(MedicationReference ref) =>
      MedicationReferenceDto(
        id: ref.id,
        dci: ref.dci,
        galenicForm: ref.galenicForm,
        therapeuticClass: ref.therapeuticClass,
      );
}

class StructuredPosologyDto {
  final double dose;
  final double frequencyPerDay;
  final int durationInDays;

  const StructuredPosologyDto({
    required this.dose,
    required this.frequencyPerDay,
    required this.durationInDays,
  });

  factory StructuredPosologyDto.fromJson(Map<String, dynamic> json) =>
      StructuredPosologyDto(
        dose: (json['dose'] as num).toDouble(),
        frequencyPerDay: (json['frequency_per_day'] as num).toDouble(),
        durationInDays: json['duration_in_days'] as int,
      );

  Map<String, dynamic> toJson() => {
        'dose': dose,
        'frequency_per_day': frequencyPerDay,
        'duration_in_days': durationInDays,
      };

  StructuredPosology toDomain() => StructuredPosology(
        dose: dose,
        frequencyPerDay: frequencyPerDay,
        durationInDays: durationInDays,
      );

  static StructuredPosologyDto fromDomain(StructuredPosology posology) =>
      StructuredPosologyDto(
        dose: posology.dose,
        frequencyPerDay: posology.frequencyPerDay,
        durationInDays: posology.durationInDays,
      );
}

class PrescriptionItemDto {
  final String label;
  final String? form;
  final MedicationReferenceDto? productReference;
  final String posology;
  final String duration;
  final String quantity;
  final StructuredPosologyDto? structuredPosology;
  final String? nonSubstitutionReason;
  final bool nonRenouvelable;

  const PrescriptionItemDto({
    required this.label,
    this.form,
    this.productReference,
    required this.posology,
    required this.duration,
    required this.quantity,
    this.structuredPosology,
    this.nonSubstitutionReason,
    this.nonRenouvelable = false,
  });

  /// `product_reference` est absent des lignes historiques : rétro-
  /// compatibilité DTO, on retombe sur `null` (texte libre uniquement).
  factory PrescriptionItemDto.fromJson(Map<String, dynamic> json) =>
      PrescriptionItemDto(
        label: json['label'] as String,
        form: json['form'] as String?,
        productReference: json['product_reference'] != null
            ? MedicationReferenceDto.fromJson(
                json['product_reference'] as Map<String, dynamic>)
            : null,
        posology: json['posology'] as String,
        duration: json['duration'] as String,
        quantity: json['quantity'] as String? ?? '',
        structuredPosology: json['structured_posology'] != null
            ? StructuredPosologyDto.fromJson(
                json['structured_posology'] as Map<String, dynamic>)
            : null,
        nonSubstitutionReason: json['non_substitution_reason'] as String?,
        nonRenouvelable: json['non_renouvelable'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        if (form != null) 'form': form,
        if (productReference != null)
          'product_reference': productReference!.toJson(),
        'posology': posology,
        'duration': duration,
        'quantity': quantity,
        if (structuredPosology != null)
          'structured_posology': structuredPosology!.toJson(),
        if (nonSubstitutionReason != null)
          'non_substitution_reason': nonSubstitutionReason,
        'non_renouvelable': nonRenouvelable,
      };

  PrescriptionItem toDomain() => PrescriptionItem(
        label: label,
        form: form,
        productReference: productReference?.toDomain(),
        posology: posology,
        duration: duration,
        quantity: quantity,
        structuredPosology: structuredPosology?.toDomain(),
        nonSubstitutionReason: nonSubstitutionReason,
        nonRenouvelable: nonRenouvelable,
      );

  static PrescriptionItemDto fromDomain(PrescriptionItem item) =>
      PrescriptionItemDto(
        label: item.label,
        form: item.form,
        productReference: item.productReference != null
            ? MedicationReferenceDto.fromDomain(item.productReference!)
            : null,
        posology: item.posology,
        duration: item.duration,
        quantity: item.quantity,
        structuredPosology: item.structuredPosology != null
            ? StructuredPosologyDto.fromDomain(item.structuredPosology!)
            : null,
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
