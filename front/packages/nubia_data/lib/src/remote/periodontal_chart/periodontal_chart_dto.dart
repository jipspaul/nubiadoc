import 'package:nubia_domain/src/entities/periodontal_chart.dart';

class ToothSiteDepthsDto {
  final int? mv;
  final int? v;
  final int? dv;
  final int? dl;
  final int? l;
  final int? ml;

  const ToothSiteDepthsDto(
      {this.mv, this.v, this.dv, this.dl, this.l, this.ml});

  factory ToothSiteDepthsDto.fromJson(Map<String, dynamic> json) =>
      ToothSiteDepthsDto(
        mv: json['mv'] as int?,
        v: json['v'] as int?,
        dv: json['dv'] as int?,
        dl: json['dl'] as int?,
        l: json['l'] as int?,
        ml: json['ml'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (mv != null) 'mv': mv,
        if (v != null) 'v': v,
        if (dv != null) 'dv': dv,
        if (dl != null) 'dl': dl,
        if (l != null) 'l': l,
        if (ml != null) 'ml': ml,
      };

  ToothSiteDepths toDomain() =>
      ToothSiteDepths(mv: mv, v: v, dv: dv, dl: dl, l: l, ml: ml);

  factory ToothSiteDepthsDto.fromDomain(ToothSiteDepths d) =>
      ToothSiteDepthsDto(
        mv: d.mv,
        v: d.v,
        dv: d.dv,
        dl: d.dl,
        l: d.l,
        ml: d.ml,
      );
}

class PeriodontalChartDto {
  final Map<String, ToothSiteDepthsDto> sites;
  final Map<String, double> indices;
  final String measuredAt;

  const PeriodontalChartDto({
    required this.sites,
    required this.indices,
    required this.measuredAt,
  });

  factory PeriodontalChartDto.fromJson(Map<String, dynamic> json) {
    final sitesJson = json['sites'] as Map<String, dynamic>? ?? const {};
    final indicesJson = json['indices'] as Map<String, dynamic>? ?? const {};
    return PeriodontalChartDto(
      sites: sitesJson.map(
        (k, v) => MapEntry(
          k,
          ToothSiteDepthsDto.fromJson(v as Map<String, dynamic>),
        ),
      ),
      indices: indicesJson.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      measuredAt: json['measured_at'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'sites': sites.map((k, v) => MapEntry(k, v.toJson())),
        'indices': indices,
      };

  PeriodontalChart toDomain() => PeriodontalChart(
        sites: sites.map((k, v) => MapEntry(k, v.toDomain())),
        indices: indices,
        measuredAt: DateTime.parse(measuredAt),
      );
}
