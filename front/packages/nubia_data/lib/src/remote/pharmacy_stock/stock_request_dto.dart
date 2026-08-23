import 'package:nubia_data/src/remote/pharmacy_directory/pharmacy_dto.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';

class StockRequestDto {
  final String id;
  final String pharmacyId;

  /// Champs pharmacie résolue — pas encore exposés par le back (#5192),
  /// parsés défensivement pour être prêts dès qu'ils existeront.
  final String? pharmacyName;
  final String? pharmacyAddress;
  final String? pharmacyPhone;
  final String? cabinetName;
  final List<Map<String, dynamic>> items;
  final String status;
  final String? responseNote;
  final String createdAt;
  final String? fulfilledAt;

  const StockRequestDto({
    required this.id,
    required this.pharmacyId,
    this.pharmacyName,
    this.pharmacyAddress,
    this.pharmacyPhone,
    this.cabinetName,
    required this.items,
    required this.status,
    this.responseNote,
    required this.createdAt,
    this.fulfilledAt,
  });

  factory StockRequestDto.fromJson(Map<String, dynamic> json) =>
      StockRequestDto(
        id: json['id'] as String,
        pharmacyId: json['pharmacy_id'] as String? ?? '',
        pharmacyName: json['pharmacy_name'] as String?,
        pharmacyAddress: PharmacyDto.formatAddress(json['pharmacy_address']),
        pharmacyPhone: json['pharmacy_phone'] as String?,
        cabinetName: json['cabinet_name'] as String?,
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        status: json['status'] as String? ?? 'sent',
        responseNote: json['response_note'] as String?,
        createdAt: json['created_at'] as String? ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        fulfilledAt: json['fulfilled_at'] as String?,
      );

  StockRequest toDomain() => StockRequest(
        id: id,
        pharmacyId: pharmacyId,
        pharmacy: pharmacyName != null
            ? Pharmacy(
                id: pharmacyId,
                name: pharmacyName!,
                address: pharmacyAddress,
                phone: pharmacyPhone,
              )
            : null,
        cabinetName: cabinetName,
        items: items
            .map(
              (item) => StockRequestItem(
                label: item['label'] as String? ?? '',
                quantity: (item['qty'] ?? item['quantity']) as int? ?? 1,
                note: item['note'] as String?,
                availability: _parseAvailability(item),
              ),
            )
            .toList(),
        status: _parseStatus(status),
        responseNote: responseNote,
        createdAt: DateTime.parse(createdAt),
        fulfilledAt: fulfilledAt != null ? DateTime.parse(fulfilledAt!) : null,
      );

  static StockItemAvailability? _parseAvailability(
    Map<String, dynamic> item,
  ) {
    final status = item['availability_status'] as String?;
    switch (status) {
      case 'in_stock':
        return const StockItemAvailability(
          status: StockItemAvailabilityStatus.inStock,
        );
      case 'limited':
        return StockItemAvailability(
          status: StockItemAvailabilityStatus.limited,
          quantityAvailable: item['available_qty'] as int?,
        );
      case 'out_of_stock':
        return const StockItemAvailability(
          status: StockItemAvailabilityStatus.outOfStock,
        );
      default:
        return null;
    }
  }

  static StockRequestStatus _parseStatus(String value) {
    switch (value) {
      case 'accepted':
        return StockRequestStatus.accepted;
      case 'rejected':
        return StockRequestStatus.rejected;
      case 'fulfilled':
        return StockRequestStatus.fulfilled;
      case 'cancelled':
        return StockRequestStatus.cancelled;
      case 'sent':
      default:
        return StockRequestStatus.sent;
    }
  }
}
