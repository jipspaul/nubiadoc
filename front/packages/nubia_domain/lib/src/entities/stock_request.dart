import 'package:equatable/equatable.dart';

import 'pharmacy.dart';

/// Statuts d'une demande de stock cabinet → pharmacie.
enum StockRequestStatus { sent, accepted, rejected, fulfilled, cancelled }

/// État de disponibilité d'une ligne de demande de stock, côté pharmacie.
enum StockItemAvailabilityStatus { inStock, limited, outOfStock }

/// Disponibilité d'une ligne, exposée par l'API pharmacie (jamais côté
/// cabinet, qui l'ignore à la création).
class StockItemAvailability extends Equatable {
  final StockItemAvailabilityStatus status;
  final int? quantityAvailable;

  const StockItemAvailability({
    required this.status,
    this.quantityAvailable,
  });

  @override
  List<Object?> get props => [status, quantityAvailable];
}

/// Une ligne d'une demande de stock (jamais de donnée patient).
class StockRequestItem extends Equatable {
  final String label;
  final int quantity;
  final String? note;
  final StockItemAvailability? availability;

  const StockRequestItem({
    required this.label,
    required this.quantity,
    this.note,
    this.availability,
  });

  @override
  List<Object?> get props => [label, quantity, note, availability];
}

/// Demande de stock émise par un cabinet vers une pharmacie.
class StockRequest extends Equatable {
  final String id;
  final String pharmacyId;

  /// Pharmacie destinataire résolue (nom, adresse, téléphone) — `null` tant
  /// que le back ne la renvoie pas ; l'UI retombe alors sur [pharmacyId].
  final Pharmacy? pharmacy;
  final String? cabinetName;
  final List<StockRequestItem> items;
  final StockRequestStatus status;
  final String? responseNote;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final DateTime? fulfilledAt;

  const StockRequest({
    required this.id,
    required this.pharmacyId,
    this.pharmacy,
    this.cabinetName,
    required this.items,
    required this.status,
    this.responseNote,
    required this.createdAt,
    this.respondedAt,
    this.fulfilledAt,
  });

  @override
  List<Object?> get props => [id, status];
}
