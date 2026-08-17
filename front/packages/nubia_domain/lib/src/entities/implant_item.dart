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
  final String? practitioner;
  final String? office;
  final String? prosthesis;
  final String? material;
  final bool? mriCompatibility;

  const ImplantItem({
    required this.id,
    required this.brand,
    this.lotNumber,
    this.placementDate,
    this.toothPosition,
    this.notes,
    this.lastControlDate,
    this.nextControl,
    this.practitioner,
    this.office,
    this.prosthesis,
    this.material,
    this.mriCompatibility,
  });

  @override
  List<Object?> get props => [id];
}
