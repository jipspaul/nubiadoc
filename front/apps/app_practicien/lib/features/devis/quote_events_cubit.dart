import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class QuoteEventsState extends Equatable {
  const QuoteEventsState();
}

class QuoteEventsLoading extends QuoteEventsState {
  const QuoteEventsLoading();

  @override
  List<Object?> get props => [];
}

class QuoteEventsError extends QuoteEventsState {
  const QuoteEventsError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class QuoteEventsLoaded extends QuoteEventsState {
  const QuoteEventsLoaded({required this.events});

  /// Trié `at ASC` par le back.
  final List<QuoteEvent> events;

  @override
  List<Object?> get props => [events];
}

/// Timeline du bloc « Suivi » du détail devis (#7175). Chargement
/// indépendant de [DevisBloc] — même découpage que `InvoiceReminderCubit`.
class QuoteEventsCubit extends Cubit<QuoteEventsState>
    with SafeEmitMixin<QuoteEventsState> {
  QuoteEventsCubit({required ListCabinetQuoteEventsUseCase listEvents})
      : _listEvents = listEvents,
        super(const QuoteEventsLoading());

  final ListCabinetQuoteEventsUseCase _listEvents;

  Future<void> load(String quoteId) async {
    safeEmit(const QuoteEventsLoading());
    final result = await _listEvents(quoteId);
    result.fold(
      (failure) => safeEmit(QuoteEventsError(message: failure.message)),
      (events) => safeEmit(QuoteEventsLoaded(events: events)),
    );
  }
}
