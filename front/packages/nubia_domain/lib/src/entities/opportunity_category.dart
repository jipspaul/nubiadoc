import 'package:equatable/equatable.dart';

/// Une opportunité individuelle au sein d'une [OpportunityCategory].
/// `amountCents`/`sinceDays`/`quoteId` absents selon la catégorie (ex.
/// anniversaire n'a ni montant ni devis). Source : `GET
/// /v1/cabinet/opportunities` (#7213/#7214).
class OpportunityItem extends Equatable {
  final String kind;
  final String patientId;
  final String? patientName;
  final int? amountCents;
  final int? sinceDays;
  final String? quoteId;

  const OpportunityItem({
    required this.kind,
    required this.patientId,
    this.patientName,
    this.amountCents,
    this.sinceDays,
    this.quoteId,
  });

  @override
  List<Object?> get props => [kind, patientId, quoteId, amountCents, sinceDays];
}

/// Une catégorie d'opportunités du widget « opportunités du moment »
/// (#7213, DP-F1.b) avec son compteur et son total — une entrée par
/// catégorie même vide (`count: 0`). Source : `GET
/// /v1/cabinet/opportunities` (#7214).
class OpportunityCategory extends Equatable {
  final String kind;
  final int count;
  final int totalAmountCents;
  final List<OpportunityItem> items;

  const OpportunityCategory({
    required this.kind,
    required this.count,
    required this.totalAmountCents,
    required this.items,
  });

  @override
  List<Object?> get props => [kind, count, totalAmountCents, items];
}
