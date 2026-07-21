import 'package:equatable/equatable.dart';

/// 6 profondeurs de sondage (mm) par dent — sites standard (mésio-
/// vestibulaire, vestibulaire, disto-vestibulaire, disto-lingual/palatin,
/// lingual/palatin, mésio-lingual/palatin). #4106.
class ToothSiteDepths extends Equatable {
  final int? mv;
  final int? v;
  final int? dv;
  final int? dl;
  final int? l;
  final int? ml;

  const ToothSiteDepths({this.mv, this.v, this.dv, this.dl, this.l, this.ml});

  bool get isEmpty =>
      mv == null &&
      v == null &&
      dv == null &&
      dl == null &&
      l == null &&
      ml == null;

  ToothSiteDepths copyWith({
    int? mv,
    int? v,
    int? dv,
    int? dl,
    int? l,
    int? ml,
  }) =>
      ToothSiteDepths(
        mv: mv ?? this.mv,
        v: v ?? this.v,
        dv: dv ?? this.dv,
        dl: dl ?? this.dl,
        l: l ?? this.l,
        ml: ml ?? this.ml,
      );

  @override
  List<Object?> get props => [mv, v, dv, dl, l, ml];
}

/// Bilan parodontal (#4105/#4106). `sites` : clé = code FDI dentition
/// permanente ("11".."48"), valeur = 6 profondeurs de sondage.
///
/// `indices` : paires nom→valeur libres — aucun référentiel unique
/// n'existe pour les indices parodontaux (cf. migration 0179,
/// `api/src/periodontal_chart.rs`), saisie dynamique côté écran plutôt
/// qu'un vocabulaire fermé comme `dental_chart`.
class PeriodontalChart extends Equatable {
  final Map<String, ToothSiteDepths> sites;
  final Map<String, double> indices;
  final DateTime measuredAt;

  const PeriodontalChart({
    required this.sites,
    required this.indices,
    required this.measuredAt,
  });

  @override
  List<Object?> get props => [sites, indices, measuredAt];
}
