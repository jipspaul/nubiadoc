import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class OrderDetailState extends Equatable {
  const OrderDetailState();

  @override
  List<Object?> get props => [];
}

class OrderDetailLoading extends OrderDetailState {
  const OrderDetailLoading();
}

class OrderDetailLoaded extends OrderDetailState {
  const OrderDetailLoaded(
    this.order, {
    this.items = const [],
    this.actionInProgress = false,
    this.preparedLineIndices = const {},
    this.actionError,
  });

  final PharmacyOrder order;

  /// Lignes de l'ordonnance (molécule, posologie, quantité…) — dégradation
  /// douce : vide si leur lecture échoue, le PDF reste le recours.
  final List<PrescriptionItem> items;

  /// Une transition est en cours (bouton en loading, double-tap bloqué).
  final bool actionInProgress;

  /// Index des lignes cochées « préparée » — garde-fou d'interface pour le
  /// compteur « X sur N préparées » qui conditionne preparing → ready (le
  /// serveur reste l'autorité, 409 remonté en erreur).
  final Set<int> preparedLineIndices;

  /// Échec d'une transition (accepter/prête/refuser) : signalé en SnackBar,
  /// sans jamais remplacer la commande déjà chargée (#7922) — contrairement
  /// à [OrderDetailError], réservé à l'échec du chargement initial.
  final String? actionError;

  @override
  List<Object?> get props =>
      [order, items, actionInProgress, preparedLineIndices, actionError];
}

/// L'URL signée du PDF est prête — la page l'ouvre puis revient à Loaded.
class OrderDetailDocumentReady extends OrderDetailState {
  const OrderDetailDocumentReady(this.order, this.url);

  final PharmacyOrder order;
  final String url;

  @override
  List<Object?> get props => [order, url];
}

class OrderDetailError extends OrderDetailState {
  const OrderDetailError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
