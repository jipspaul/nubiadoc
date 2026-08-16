import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Fenêtre d'échéance retenue pour un devis « expirant cette semaine »
/// (#5377) : envoyé au patient, pas encore signé, avec une date d'expiration
/// dans les 7 prochains jours — même fenêtre que le badge du rail
/// (`RailBadgesCubit`, #5388) pour que les deux compteurs restent cohérents.
const expiringQuoteWindow = Duration(days: 7);

sealed class ExpiringQuotesSummaryState extends Equatable {
  const ExpiringQuotesSummaryState();
}

class ExpiringQuotesSummaryLoading extends ExpiringQuotesSummaryState {
  const ExpiringQuotesSummaryLoading();

  @override
  List<Object?> get props => [];
}

class ExpiringQuotesSummaryError extends ExpiringQuotesSummaryState {
  const ExpiringQuotesSummaryError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class ExpiringQuotesSummaryLoaded extends ExpiringQuotesSummaryState {
  const ExpiringQuotesSummaryLoaded({required this.quotes});

  /// Devis envoyés, non signés, expirant dans la fenêtre — triés par date
  /// d'expiration croissante (le plus urgent en premier).
  final List<CabinetQuote> quotes;

  @override
  List<Object?> get props => [quotes];
}

/// Ligne « devis qui expirent » du panneau « À traiter maintenant »
/// (#5377) : devis envoyés dont l'expiration tombe dans la semaine en cours.
/// Chargement indépendant du `DashboardBloc`, même découpage que
/// `WaitingRoomSummaryCubit`/`PatientMessagesSummaryCubit`.
class ExpiringQuotesSummaryCubit extends Cubit<ExpiringQuotesSummaryState>
    with SafeEmitMixin<ExpiringQuotesSummaryState> {
  ExpiringQuotesSummaryCubit({required ListCabinetQuotesUseCase listQuotes})
      : _listQuotes = listQuotes,
        super(const ExpiringQuotesSummaryLoading());

  final ListCabinetQuotesUseCase _listQuotes;

  Future<void> load() async {
    safeEmit(const ExpiringQuotesSummaryLoading());
    final now = DateTime.now();
    final result = await _listQuotes();
    result.fold(
      (failure) =>
          safeEmit(ExpiringQuotesSummaryError(message: failure.message)),
      (quotes) {
        final expiring = quotes
            .where(
              (q) =>
                  q.status == CabinetQuoteStatus.sent &&
                  q.expiresAt != null &&
                  q.expiresAt!.isAfter(now) &&
                  q.expiresAt!.isBefore(now.add(expiringQuoteWindow)),
            )
            .toList()
          ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));
        safeEmit(ExpiringQuotesSummaryLoaded(quotes: expiring));
      },
    );
  }
}
