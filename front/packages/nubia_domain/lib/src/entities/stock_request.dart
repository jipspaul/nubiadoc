import 'package:equatable/equatable.dart';

/// Statuts d'une demande de stock cabinet → pharmacie.
enum StockRequestStatus { sent, accepted, rejected, fulfilled, cancelled }

/// Une ligne d'une demande de stock (jamais de donnée patient).
class StockRequestItem extends Equatable {
  final String label;
  final int quantity;
  final String? note;

  const StockRequestItem({
    required this.label,
    required this.quantity,
    this.note,
  });

  @override
  List<Object?> get props => [label, quantity, note];
}

/// Demande de stock émise par un cabinet vers une pharmacie.
class StockRequest extends Equatable {
  final String id;
  final String pharmacyId;
  final String? cabinetName;
  final List<StockRequestItem> items;
  final StockRequestStatus status;
  final String? responseNote;
  final DateTime createdAt;

  const StockRequest({
    required this.id,
    required this.pharmacyId,
    this.cabinetName,
    required this.items,
    required this.status,
    this.responseNote,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, status];
}
