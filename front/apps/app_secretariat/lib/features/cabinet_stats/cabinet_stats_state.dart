import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetStatsState {
  const CabinetStatsState();
}

class CabinetStatsLoading extends CabinetStatsState {
  const CabinetStatsLoading();

  @override
  bool operator ==(Object other) => other is CabinetStatsLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class CabinetStatsLoaded extends CabinetStatsState {
  const CabinetStatsLoaded(
    this.activity,
    this.billing, {
    this.activityForbidden = false,
  });

  final List<CabinetActivityStat> activity;
  final CabinetBillingStats billing;

  /// #6369 — `stats/activity` a répondu 403 (réservé aux praticiens,
  /// RBAC #4592) : distinct d'une activité réellement vide, pour que l'écran
  /// ne présente pas un refus de permission comme un fait métier.
  final bool activityForbidden;

  @override
  bool operator ==(Object other) =>
      other is CabinetStatsLoaded &&
      other.billing == billing &&
      other.activityForbidden == activityForbidden &&
      other.activity.length == activity.length &&
      List.generate(
        activity.length,
        (i) => other.activity[i] == activity[i],
      ).every((b) => b);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(activity), billing, activityForbidden);
}

class CabinetStatsError extends CabinetStatsState {
  const CabinetStatsError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is CabinetStatsError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
