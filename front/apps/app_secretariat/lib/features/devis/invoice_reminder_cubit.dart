import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class InvoiceReminderState extends Equatable {
  const InvoiceReminderState();
}

class InvoiceReminderLoading extends InvoiceReminderState {
  const InvoiceReminderLoading();

  @override
  List<Object?> get props => [];
}

class InvoiceReminderError extends InvoiceReminderState {
  const InvoiceReminderError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class InvoiceReminderLoaded extends InvoiceReminderState {
  const InvoiceReminderLoaded({
    required this.history,
    this.sending = false,
    this.sendError,
  });

  /// Trié `sent_at DESC` par le back (la plus récente en tête).
  final List<InvoiceReminder> history;
  final bool sending;
  final String? sendError;

  InvoiceReminderLoaded copyWith({
    List<InvoiceReminder>? history,
    bool? sending,
    String? sendError,
  }) =>
      InvoiceReminderLoaded(
        history: history ?? this.history,
        sending: sending ?? this.sending,
        sendError: sendError,
      );

  @override
  List<Object?> get props => [history, sending, sendError];
}

/// Bouton « Relancer le patient » + historique des relances (#7205), sur le
/// détail d'une facture (devis signé échu) côté secrétariat/praticien.
/// Chargement indépendant de [DevisBloc] — même découpage que
/// `ExpiringQuotesSummaryCubit`/`AuditLogAccessCubit`.
class InvoiceReminderCubit extends Cubit<InvoiceReminderState>
    with SafeEmitMixin<InvoiceReminderState> {
  InvoiceReminderCubit({
    required ListInvoiceRemindersUseCase listReminders,
    required SendInvoiceReminderUseCase sendReminder,
  })  : _listReminders = listReminders,
        _sendReminder = sendReminder,
        super(const InvoiceReminderLoading());

  final ListInvoiceRemindersUseCase _listReminders;
  final SendInvoiceReminderUseCase _sendReminder;

  Future<void> load(String invoiceId) async {
    safeEmit(const InvoiceReminderLoading());
    final result = await _listReminders(invoiceId);
    result.fold(
      (failure) => safeEmit(InvoiceReminderError(message: failure.message)),
      (history) => safeEmit(InvoiceReminderLoaded(history: history)),
    );
  }

  Future<void> send(String invoiceId) async {
    final current = state;
    if (current is! InvoiceReminderLoaded || current.sending) return;

    safeEmit(current.copyWith(sending: true, sendError: null));
    final result = await _sendReminder(invoiceId);
    final failure = result.fold((f) => f, (_) => null);
    if (failure != null) {
      safeEmit(current.copyWith(sending: false, sendError: failure.message));
      return;
    }
    // Recharge l'historique plutôt que d'insérer localement une entrée
    // devinée : le back décide seul du/des canal(aux) réellement délivrés
    // (push puis e-mail, potentiellement 0 à 2 lignes selon le compte
    // patient, cf. `invoice_reminder.rs`).
    await load(invoiceId);
  }
}
