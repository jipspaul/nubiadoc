import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class SendPrescriptionState extends Equatable {
  const SendPrescriptionState();

  @override
  List<Object?> get props => [];
}

class SendPrescriptionLoading extends SendPrescriptionState {
  const SendPrescriptionLoading();
}

/// Prêt à envoyer : ordonnances éligibles + pharmacie présélectionnée
/// (la pharmacie déclarée du patient par défaut, modifiable).
class SendPrescriptionReady extends SendPrescriptionState {
  const SendPrescriptionReady({
    required this.prescriptions,
    this.selectedPrescription,
    this.pharmacy,
    this.submitting = false,
  });

  final List<PatientPrescription> prescriptions;
  final PatientPrescription? selectedPrescription;
  final Pharmacy? pharmacy;
  final bool submitting;

  bool get canSubmit =>
      selectedPrescription != null && pharmacy != null && !submitting;

  SendPrescriptionReady copyWith({
    List<PatientPrescription>? prescriptions,
    PatientPrescription? selectedPrescription,
    Pharmacy? pharmacy,
    bool? submitting,
  }) =>
      SendPrescriptionReady(
        prescriptions: prescriptions ?? this.prescriptions,
        selectedPrescription: selectedPrescription ?? this.selectedPrescription,
        pharmacy: pharmacy ?? this.pharmacy,
        submitting: submitting ?? this.submitting,
      );

  @override
  List<Object?> get props =>
      [prescriptions, selectedPrescription, pharmacy, submitting];
}

class SendPrescriptionSuccess extends SendPrescriptionState {
  const SendPrescriptionSuccess(this.order);

  final PharmacyOrder order;

  @override
  List<Object?> get props => [order];
}

class SendPrescriptionError extends SendPrescriptionState {
  const SendPrescriptionError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Transmission d'une ordonnance signée à une pharmacie (création de la
/// commande click-and-collect).
class SendPrescriptionCubit extends Cubit<SendPrescriptionState> {
  SendPrescriptionCubit({
    required ListMyPrescriptionsUseCase listPrescriptions,
    required GetMyPharmacyUseCase getMyPharmacy,
    required CreatePharmacyOrderUseCase createOrder,
  })  : _listPrescriptions = listPrescriptions,
        _getMyPharmacy = getMyPharmacy,
        _createOrder = createOrder,
        super(const SendPrescriptionLoading());

  final ListMyPrescriptionsUseCase _listPrescriptions;
  final GetMyPharmacyUseCase _getMyPharmacy;
  final CreatePharmacyOrderUseCase _createOrder;

  /// [prescriptionId] présélectionne l'ordonnance d'une commande refusée
  /// que le patient renvoie à une autre pharmacie (#5351).
  Future<void> load({String? prescriptionId}) async {
    emit(const SendPrescriptionLoading());
    final prescriptionsResult = await _listPrescriptions();
    final pharmacyResult = await _getMyPharmacy();

    prescriptionsResult.fold(
      (failure) => emit(SendPrescriptionError(failure.message)),
      (prescriptions) {
        final eligible = prescriptions
            .where((prescription) => prescription.canBeSentToPharmacy)
            .toList();
        final pharmacy =
            pharmacyResult.fold<Pharmacy?>((_) => null, (value) => value);
        PatientPrescription? preselected;
        if (prescriptionId != null) {
          for (final prescription in eligible) {
            if (prescription.id == prescriptionId) {
              preselected = prescription;
              break;
            }
          }
        }
        emit(SendPrescriptionReady(
          prescriptions: eligible,
          selectedPrescription:
              preselected ?? (eligible.length == 1 ? eligible.first : null),
          pharmacy: pharmacy,
        ));
      },
    );
  }

  void selectPrescription(PatientPrescription prescription) {
    final current = state;
    if (current is SendPrescriptionReady) {
      emit(current.copyWith(selectedPrescription: prescription));
    }
  }

  void selectPharmacy(Pharmacy pharmacy) {
    final current = state;
    if (current is SendPrescriptionReady) {
      emit(current.copyWith(pharmacy: pharmacy));
    }
  }

  Future<void> submit() async {
    final current = state;
    if (current is! SendPrescriptionReady || !current.canSubmit) return;

    emit(current.copyWith(submitting: true));
    final result = await _createOrder(
      prescriptionId: current.selectedPrescription!.id,
      pharmacyId: current.pharmacy!.id,
    );
    result.fold(
      (failure) => emit(SendPrescriptionError(failure.message)),
      (order) => emit(SendPrescriptionSuccess(order)),
    );
  }
}
