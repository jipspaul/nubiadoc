import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';

part 'quote_list_state.dart';

/// Cubit chargé de récupérer la liste de tous les devis du patient.
///
/// Un Cubit (pas un Bloc) suffit ici : le seul trigger est le chargement
/// initial + un éventuel pull-to-refresh.
@injectable
class QuoteListCubit extends Cubit<QuoteListState> {
  QuoteListCubit(this._billing) : super(const QuoteListLoading());

  final BillingRepository _billing;

  /// Charge (ou recharge) la liste des devis depuis l'API.
  Future<void> load() async {
    emit(const QuoteListLoading());
    final result = await _billing.getQuotes();
    result.fold(
      (failure) => emit(QuoteListError(failure.message)),
      (quotes) => emit(QuoteListLoaded(quotes)),
    );
  }
}
