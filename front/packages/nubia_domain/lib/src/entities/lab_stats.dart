import 'package:equatable/equatable.dart';

/// Un bon de travail valorisé sur la période (#7163, DP-F19.c) : coût labo
/// vs CA facturé au patient sur la ligne de devis liée. Source :
/// `GET /v1/cabinet/lab-stats` (`by_act`).
class LabStatActItem extends Equatable {
  final String labWorkOrderId;
  final String labName;
  final String? practitionerId;
  final String? practitionerName;
  final String? toothFdi;
  final String? workNature;
  final int labCostCents;
  final int patientRevenueCents;
  final int marginCents;

  const LabStatActItem({
    required this.labWorkOrderId,
    required this.labName,
    this.practitionerId,
    this.practitionerName,
    this.toothFdi,
    this.workNature,
    required this.labCostCents,
    required this.patientRevenueCents,
    required this.marginCents,
  });

  @override
  List<Object?> get props => [
        labWorkOrderId,
        labName,
        practitionerId,
        toothFdi,
        workNature,
        labCostCents,
        patientRevenueCents,
        marginCents,
      ];
}

/// Agrégat coût labo / CA patient / marge pour un laboratoire (`by_lab`).
class LabStatByLab extends Equatable {
  final String labName;
  final int orderCount;
  final int labCostCents;
  final int patientRevenueCents;
  final int marginCents;

  const LabStatByLab({
    required this.labName,
    required this.orderCount,
    required this.labCostCents,
    required this.patientRevenueCents,
    required this.marginCents,
  });

  @override
  List<Object?> get props =>
      [labName, orderCount, labCostCents, patientRevenueCents, marginCents];
}

/// Agrégat coût labo / CA patient / marge pour un praticien (`by_practitioner`) :
/// seuls les bons rattachés à une ligne de devis avec praticien identifié y
/// figurent (cf. `cabinet_stats::get_cabinet_lab_stats` côté API).
class LabStatByPractitioner extends Equatable {
  final String practitionerId;
  final String? practitionerName;
  final int orderCount;
  final int labCostCents;
  final int patientRevenueCents;
  final int marginCents;

  const LabStatByPractitioner({
    required this.practitionerId,
    this.practitionerName,
    required this.orderCount,
    required this.labCostCents,
    required this.patientRevenueCents,
    required this.marginCents,
  });

  @override
  List<Object?> get props => [
        practitionerId,
        practitionerName,
        orderCount,
        labCostCents,
        patientRevenueCents,
        marginCents,
      ];
}

/// Coût labo / CA patient / marge, agrégés sur un mois (#7163, DP-F19.c).
/// Source : `GET /v1/cabinet/lab-stats?period=YYYY-MM`.
class LabStats extends Equatable {
  final String periodMonth;
  final int totalLabCostCents;
  final int totalPatientRevenueCents;
  final int totalMarginCents;
  final List<LabStatActItem> byAct;
  final List<LabStatByPractitioner> byPractitioner;
  final List<LabStatByLab> byLab;

  const LabStats({
    required this.periodMonth,
    required this.totalLabCostCents,
    required this.totalPatientRevenueCents,
    required this.totalMarginCents,
    required this.byAct,
    required this.byPractitioner,
    required this.byLab,
  });

  @override
  List<Object?> get props => [
        periodMonth,
        totalLabCostCents,
        totalPatientRevenueCents,
        totalMarginCents,
        byAct,
        byPractitioner,
        byLab,
      ];
}
