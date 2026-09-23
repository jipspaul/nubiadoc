import 'package:nubia_domain/src/entities/lab_price_list_item.dart';

class LabPriceListItemDto {
  final String id;
  final String labName;
  final String itemLabel;
  final String itemCode;
  final int priceCents;
  final String validFrom;

  const LabPriceListItemDto({
    required this.id,
    required this.labName,
    required this.itemLabel,
    required this.itemCode,
    required this.priceCents,
    required this.validFrom,
  });

  factory LabPriceListItemDto.fromJson(Map<String, dynamic> json) =>
      LabPriceListItemDto(
        id: json['id'] as String,
        labName: json['lab_name'] as String,
        itemLabel: json['item_label'] as String,
        itemCode: json['item_code'] as String,
        priceCents: json['price_cents'] as int,
        validFrom: json['valid_from'] as String,
      );

  LabPriceListItem toDomain() => LabPriceListItem(
        id: id,
        labName: labName,
        itemLabel: itemLabel,
        itemCode: itemCode,
        priceCents: priceCents,
        validFrom: validFrom,
      );
}
