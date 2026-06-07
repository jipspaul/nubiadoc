import 'package:equatable/equatable.dart';

/// Catégories de documents du coffre-fort patient (US-3.5.1, rubriques 3+11).
enum VaultCategory {
  quote,
  invoice,
  prescription,
  xray,
  cbct,
  photo,
  report,
  instructions,
}

/// Retourne le libellé affichable d'une [VaultCategory].
String vaultCategoryLabel(VaultCategory? category) {
  switch (category) {
    case null:
      return 'Tous';
    case VaultCategory.quote:
      return 'Devis';
    case VaultCategory.invoice:
      return 'Factures';
    case VaultCategory.prescription:
      return 'Ordonnances';
    case VaultCategory.xray:
      return 'Radios';
    case VaultCategory.cbct:
      return 'CBCT';
    case VaultCategory.photo:
      return 'Photos';
    case VaultCategory.report:
      return 'CR';
    case VaultCategory.instructions:
      return 'Consignes';
  }
}

/// Document du coffre-fort patient.
class VaultDocument extends Equatable {
  const VaultDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.date,
  });

  final String id;
  final String name;
  final VaultCategory category;
  final DateTime date;

  @override
  List<Object?> get props => [id];
}

/// Données mock — 8 documents, 1 par catégorie.
final List<VaultDocument> kVaultMockDocuments = [
  VaultDocument(
    id: 'v-001',
    name: 'Devis implant mandibulaire',
    category: VaultCategory.quote,
    date: DateTime(2026, 1, 10),
  ),
  VaultDocument(
    id: 'v-002',
    name: 'Facture pose prothèse',
    category: VaultCategory.invoice,
    date: DateTime(2026, 2, 14),
  ),
  VaultDocument(
    id: 'v-003',
    name: 'Ordonnance amoxicilline',
    category: VaultCategory.prescription,
    date: DateTime(2026, 3, 5),
  ),
  VaultDocument(
    id: 'v-004',
    name: 'Radiographie panoramique',
    category: VaultCategory.xray,
    date: DateTime(2026, 3, 20),
  ),
  VaultDocument(
    id: 'v-005',
    name: 'CBCT secteur 3',
    category: VaultCategory.cbct,
    date: DateTime(2026, 4, 8),
  ),
  VaultDocument(
    id: 'v-006',
    name: 'Photos avant traitement',
    category: VaultCategory.photo,
    date: DateTime(2026, 4, 22),
  ),
  VaultDocument(
    id: 'v-007',
    name: 'Compte-rendu consultation',
    category: VaultCategory.report,
    date: DateTime(2026, 5, 3),
  ),
  VaultDocument(
    id: 'v-008',
    name: 'Consignes post-opératoires',
    category: VaultCategory.instructions,
    date: DateTime(2026, 5, 17),
  ),
];
