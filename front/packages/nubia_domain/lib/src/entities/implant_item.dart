import 'package:equatable/equatable.dart';

/// Un implant du passeport implantaire patient (#4142). Source :
/// `GET /v1/implant-passport`.
class ImplantItem extends Equatable {
  final String id;
  final String brand;
  final String? lotNumber;
  final String? placementDate;
  final String? toothPosition;
  final String? notes;
  final String? lastControlDate;
  final String? nextControl;
  final String? manufacturer;
  final String? model;
  final String? reference;
  final String? dimensions;
  final String? material;

  const ImplantItem({
    required this.id,
    required this.brand,
    this.lotNumber,
    this.placementDate,
    this.toothPosition,
    this.notes,
    this.lastControlDate,
    this.nextControl,
    this.manufacturer,
    this.model,
    this.reference,
    this.dimensions,
    this.material,
  });

  @override
  List<Object?> get props => [id];
}
