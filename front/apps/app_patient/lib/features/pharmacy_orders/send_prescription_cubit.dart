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
    this.submitError,
  });

  final List<PatientPrescription> prescriptions;
  final PatientPrescription? selectedPrescription;
  final Pharmacy? pharmacy;
  final bool submitting;

  /// Échec ponctuel d'un `submit()` (ex. 409 `already_ordered`) — capté par
  /// un `BlocListener` (SnackBar), ne remplace pas la liste (#7140, même
  /// règle que #7119 pour « Mes ordonnances »).
  final String? submitError;

  bool get canSubmit =>
      selectedPrescription != null && pharmacy != null && !submitting;

  /// [submitError] n'a pas de valeur par défaut héritée : tout nouvel appel
  /// efface l'erreur transitoire précédente sauf si explicitement fournie.
  SendPrescriptionReady copyWith({
    List<PatientPrescription>? prescriptions,
    PatientPrescription? selectedPrescription,
    Pharmacy? pharmacy,
    bool? submitting,
    String? submitError,
  }) =>
      SendPrescriptionReady(
        prescriptions: prescriptions ?? this.prescriptions,
        selectedPrescription: selectedPrescription ?? this.selectedPrescription,
        pharmacy: pharmacy ?? this.pharmacy,
        submitting: submitting ?? this.submitting,
        submitError: submitError,
      );

  @override
  List<Object?> get props =>
      [prescriptions, selectedPrescription, pharmacy, submitting, submitError];
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
    required ListPatientPharmacyOrdersUseCase listPharmacyOrders,
    required GetMyPharmacyUseCase getMyPharmacy,
    required CreatePharmacyOrderUseCase createOrder,
  })  : _listPrescriptions = listPrescriptions,
        _listPharmacyOrders = listPharmacyOrders,
        _getMyPharmacy = getMyPharmacy,
        _createOrder = createOrder,
        super(const SendPrescriptionLoading());

  final ListMyPrescriptionsUseCase _listPrescriptions;
  final ListPatientPharmacyOrdersUseCase _listPharmacyOrders;
  final GetMyPharmacyUseCase _getMyPharmacy;
  final CreatePharmacyOrderUseCase _createOrder;

  /// Statuts de commande qui bloquent une re-transmission côté API — miroir
  /// de `orders.rs::create_account_order` (index unique partiel 0124 pour
  /// received/preparing/ready, vérification `picked_up` explicite) (#7140).
  static const _blockingOrderStatuses = {
    PharmacyOrderStatus.received,
    PharmacyOrderStatus.preparing,
    PharmacyOrderStatus.ready,
    PharmacyOrderStatus.pickedUp,
  };

  /// [prescriptionId] présélectionne l'ordonnance d'une commande refusée
  /// que le patient renvoie à une autre pharmacie (#5351).
  Future<void> load({String? prescriptionId}) async {
    emit(const SendPrescriptionLoading());
    final prescriptionsResult = await _listPrescriptions();
    final ordersResult = await _listPharmacyOrders();
    final pharmacyResult = await _getMyPharmacy();

    prescriptionsResult.fold(
      (failure) => emit(SendPrescriptionError(failure.message)),
      (prescriptions) {
        // GET /v1/account/prescriptions ne dit pas si une ordonnance `sent`
        // a une commande active/déjà retirée qui la rend non re-commandable
        // (#7140) — on croise avec les commandes du patient, déjà chargées
        // pour l'écran « Mes commandes ».
        final blockedPrescriptionIds = ordersResult.fold(
          (_) => const <String>{},
          (orders) => orders
              .where((order) => _blockingOrderStatuses.contains(order.status))
              .map((order) => order.prescriptionId)
              .toSet(),
        );
        final eligible = prescriptions
            .where((prescription) =>
                prescription.canBeSentToPharmacy &&
                !blockedPrescriptionIds.contains(prescription.id))
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

  /// Consomme l'erreur transitoire une fois affichée (SnackBar) pour ne pas
  /// la rejouer si l'état est reconstruit (#7140).
  void dismissSubmitError() {
    final current = state;
    if (current is SendPrescriptionReady) {
      emit(current.copyWith());
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
      // Un échec ponctuel (ex. 409 already_ordered) ne doit pas effacer la
      // liste/sélection/pharmacie déjà chargées (#7140, même règle que
      // #7119) : on reste sur `current`, juste annoté de l'erreur.
      (failure) => emit(current.copyWith(submitError: failure.message)),
      (order) => emit(SendPrescriptionSuccess(order)),
    );
  }
}
