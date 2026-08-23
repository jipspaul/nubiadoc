import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ConsentsState extends Equatable {
  const ConsentsState();
  @override
  List<Object?> get props => [];
}

final class ConsentsLoading extends ConsentsState {
  const ConsentsLoading();
}

final class ConsentsLoaded extends ConsentsState {
  final List<Consent> consents;

  /// Purpose en cours d'écriture (bascule optimiste désactivée pendant l'appel).
  final String? pending;

  /// Message d'échec d'une bascule (#5215) : reste local à la ligne (SnackBar),
  /// ne remplace jamais la liste par un écran d'erreur plein écran.
  final String? toggleError;

  /// Pharmacie déclarée du patient (`GET /v1/account/pharmacy`), affichée en
  /// chip sur la carte `partage_pharmacie` (maquette design-v2, #5209).
  /// `null` si aucune pharmacie déclarée, ou si la requête échoue — jamais de
  /// nom inventé côté front.
  final String? pharmacyName;

  const ConsentsLoaded(
    this.consents, {
    this.pending,
    this.toggleError,
    this.pharmacyName,
  });
  @override
  List<Object?> get props => [consents, pending, toggleError, pharmacyName];
}

final class ConsentsError extends ConsentsState {
  final String message;
  const ConsentsError(this.message);
  @override
  List<Object?> get props => [message];
}

class ConsentsCubit extends Cubit<ConsentsState>
    with SafeEmitMixin<ConsentsState> {
  ConsentsCubit({
    required ListConsentsUseCase list,
    required SetConsentUseCase set,
    required ListPatientPharmacyOrdersUseCase listPharmacyOrders,
    required GetMyPharmacyUseCase getMyPharmacy,
  })  : _list = list,
        _set = set,
        _listPharmacyOrders = listPharmacyOrders,
        _getMyPharmacy = getMyPharmacy,
        super(const ConsentsLoading());

  final ListConsentsUseCase _list;
  final SetConsentUseCase _set;
  final ListPatientPharmacyOrdersUseCase _listPharmacyOrders;
  final GetMyPharmacyUseCase _getMyPharmacy;

  /// Référence de la commande pharmacie transmise et non honorée la plus
  /// récente (#5212, encart « commande en cours » de la feuille de retrait
  /// du partage pharmacie). `null` si aucune commande en cours, ou si le
  /// back ne l'expose pas encore (`PharmacyOrder.orderRef`) : jamais de
  /// numéro inventé côté front.
  Future<String?> pendingPharmacyOrderRef() async {
    final result = await _listPharmacyOrders();
    return result.fold((_) => null, (orders) {
      final pending = orders.where((o) => !o.status.isTerminal).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return pending.isEmpty ? null : pending.first.orderRef;
    });
  }

  /// Nom de la pharmacie déclarée (`GET /v1/account/pharmacy`, #5209).
  /// Dégrade à `null` sur échec/exception — source indépendante des
  /// consentements, ne doit jamais empêcher leur affichage.
  Future<String?> _loadPharmacyName() async {
    try {
      final result = await _getMyPharmacy();
      return result.fold((_) => null, (pharmacy) => pharmacy?.name);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    emit(const ConsentsLoading());
    final pharmacyNameFuture = _loadPharmacyName();
    final result = await _list();
    final pharmacyName = await pharmacyNameFuture;
    result.fold(
      (f) => safeEmit(ConsentsError(f.message)),
      (c) => safeEmit(ConsentsLoaded(c, pharmacyName: pharmacyName)),
    );
  }

  Future<void> toggle(String purpose, bool granted) async {
    final current = state;
    if (current is! ConsentsLoaded) return;
    emit(ConsentsLoaded(
      current.consents,
      pending: purpose,
      pharmacyName: current.pharmacyName,
    ));
    final result = await _set(purpose: purpose, granted: granted);
    await result.fold(
      // Échec d'une bascule : erreur locale à la ligne (SnackBar), la liste
      // reste affichée et la bascule revient à son état serveur — jamais de
      // NubiaErrorWidget plein écran pour l'échec d'UN consentement (#5215).
      (f) async => safeEmit(
        ConsentsLoaded(
          current.consents,
          toggleError: f.message,
          pharmacyName: current.pharmacyName,
        ),
      ),
      (_) async => load(),
    );
  }
}
