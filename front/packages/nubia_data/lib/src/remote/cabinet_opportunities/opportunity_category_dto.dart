import 'package:nubia_domain/src/entities/opportunity_category.dart';
import 'package:nubia_data/src/remote/cabinet_opportunities/opportunity_item_dto.dart';

class OpportunityCategoryDto {
  final String kind;
  final int count;
  final int totalAmountCents;
  final List<OpportunityItemDto> items;

  const OpportunityCategoryDto({
    required this.kind,
    required this.count,
    required this.totalAmountCents,
    required this.items,
  });

  factory OpportunityCategoryDto.fromJson(Map<String, dynamic> json) =>
      OpportunityCategoryDto(
        kind: json['kind'] as String,
        count: json['count'] as int,
        totalAmountCents: json['total_amount_cents'] as int,
        items: (json['items'] as List<dynamic>)
            .map((e) => OpportunityItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  OpportunityCategory toDomain() => OpportunityCategory(
        kind: kind,
        count: count,
        totalAmountCents: totalAmountCents,
        items: items.map((i) => i.toDomain()).toList(),
      );
}
