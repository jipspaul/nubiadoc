import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class SendToPharmacyState extends Equatable {
  const SendToPharmacyState();

  @override
  List<Object?> get props => [];
}

class SendToPharmacyLoading extends SendToPharmacyState {
  const SendToPharmacyLoading();
}

/// Prêt : [pharmacy] = destinataire courant (pharmacie déclarée du patient
/// par défaut, null si aucune), modifiable via le picker.
class SendToPharmacyReady extends SendToPharmacyState {
  const SendToPharmacyReady({this.pharmacy, this.sending = false});

  final Pharmacy? pharmacy;
  final bool sending;

  bool get canSend => pharmacy != null && !sending;

  @override
  List<Object?> get props => [pharmacy, sending];
}

class SendToPharmacySent extends SendToPharmacyState {
  const SendToPharmacySent(this.pharmacy);

  final Pharmacy pharmacy;

  @override
  List<Object?> get props => [pharmacy];
}

class SendToPharmacyError extends SendToPharmacyState {
  const SendToPharmacyError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Envoi d'une ordonnance signée à une pharmacie, depuis la confirmation de
/// signature. La pharmacie déclarée du patient est présélectionnée
/// (GET /v1/cabinet/patients/{id}/pharmacy).
class SendToPharmacyCubit extends Cubit<SendToPharmacyState> {
  SendToPharmacyCubit({
    required GetPatientPharmacyUseCase getPatientPharmacy,
    required SendPrescriptionToPharmacyUseCase sendToPharmacy,
  })  : _getPatientPharmacy = getPatientPharmacy,
        _sendToPharmacy = sendToPharmacy,
        super(const SendToPharmacyLoading());

  final GetPatientPharmacyUseCase _getPatientPharmacy;
  final SendPrescriptionToPharmacyUseCase _sendToPharmacy;

  Future<void> load(String patientId) async {
    emit(const SendToPharmacyLoading());
    final result = await _getPatientPharmacy(patientId);
    result.fold(
      // L'envoi reste possible même si la présélection échoue.
      (_) => emit(const SendToPharmacyReady()),
      (pharmacy) => emit(SendToPharmacyReady(pharmacy: pharmacy)),
    );
  }

  void selectPharmacy(Pharmacy pharmacy) {
    final current = state;
    if (current is SendToPharmacyReady && !current.sending) {
      emit(SendToPharmacyReady(pharmacy: pharmacy));
    }
  }

  Future<void> send(String prescriptionId) async {
    final current = state;
    if (current is! SendToPharmacyReady || !current.canSend) return;

    final pharmacy = current.pharmacy!;
    emit(SendToPharmacyReady(pharmacy: pharmacy, sending: true));
    final result = await _sendToPharmacy(
      prescriptionId: prescriptionId,
      pharmacyId: pharmacy.id,
    );
    result.fold(
      (failure) => emit(SendToPharmacyError(failure.message)),
      (_) => emit(SendToPharmacySent(pharmacy)),
    );
  }
}
