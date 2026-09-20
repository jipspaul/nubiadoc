import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Ordre d'urgence décroissant des niveaux d'alerte de
/// `ComplianceItem.alertLevel` (#7169/#7170) — le plus urgent en premier.
const List<String> complianceAlertUrgencyOrder = [
  'overdue',
  'due_j7',
  'due_j30',
];

int _urgencyRank(String? alertLevel) {
  final index = complianceAlertUrgencyOrder.indexOf(alertLevel ?? '');
  return index == -1 ? complianceAlertUrgencyOrder.length : index;
}

sealed class ComplianceAlertsSummaryState extends Equatable {
  const ComplianceAlertsSummaryState();
}

class ComplianceAlertsSummaryLoading extends ComplianceAlertsSummaryState {
  const ComplianceAlertsSummaryLoading();

  @override
  List<Object?> get props => [];
}

class ComplianceAlertsSummaryError extends ComplianceAlertsSummaryState {
  const ComplianceAlertsSummaryError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class ComplianceAlertsSummaryLoaded extends ComplianceAlertsSummaryState {
  const ComplianceAlertsSummaryLoaded({required this.alertingItems});

  /// Items non clôturés portant une alerte (`échu`/`J-7`/`J-30`), triés du
  /// plus urgent au moins urgent puis par échéance croissante.
  final List<ComplianceItem> alertingItems;

  @override
  List<Object?> get props => [alertingItems];
}

/// Carte « Alertes conformité » du tableau de bord (#7169) : items de
/// l'échéancier ARS/DMSM échus ou approchant l'échéance (J-7/J-30).
/// Chargement indépendant du `DashboardBloc`, même découpage que
/// `ExpiringQuotesSummaryCubit`.
class ComplianceAlertsSummaryCubit extends Cubit<ComplianceAlertsSummaryState>
    with SafeEmitMixin<ComplianceAlertsSummaryState> {
  ComplianceAlertsSummaryCubit({required ListComplianceItemsUseCase listItems})
      : _listItems = listItems,
        super(const ComplianceAlertsSummaryLoading());

  final ListComplianceItemsUseCase _listItems;

  Future<void> load() async {
    safeEmit(const ComplianceAlertsSummaryLoading());
    final result = await _listItems();
    result.fold(
      (failure) =>
          safeEmit(ComplianceAlertsSummaryError(message: failure.message)),
      (items) {
        final alerting = items.where((i) => i.hasAlert).toList()
          ..sort((a, b) {
            final urgency =
                _urgencyRank(a.alertLevel).compareTo(_urgencyRank(b.alertLevel));
            return urgency != 0 ? urgency : a.dueDate.compareTo(b.dueDate);
          });
        safeEmit(ComplianceAlertsSummaryLoaded(alertingItems: alerting));
      },
    );
  }
}
