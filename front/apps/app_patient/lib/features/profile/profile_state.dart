import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object?> get props => [];
}

final class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileLoaded extends ProfileState {
  final PatientAccount account;
  final bool biometricEnabled;
  final NotificationPreferences? notifPrefs;
  final bool phoneUpdating;
  final ProfileAccountSummary accountSummary;

  const ProfileLoaded(
    this.account, {
    this.biometricEnabled = false,
    this.notifPrefs,
    this.phoneUpdating = false,
    this.accountSummary = ProfileAccountSummary.empty,
  });

  @override
  List<Object?> get props =>
      [account, biometricEnabled, notifPrefs, phoneUpdating, accountSummary];
}

/// Valeurs courantes des tuiles « Mon compte » (#5232) : le profil devient un
/// état — chaque tuile porte sa donnée — plutôt qu'une table des matières.
/// Un champ `null` signifie « non chargé / indisponible » : la tuile s'affiche
/// alors sans valeur, chevron seul (dégradation propre).
class ProfileAccountSummary extends Equatable {
  final int? quotesToSign;
  final String? coverageLabel;
  final String? referringDoctorName;
  final int? dependentsCount;
  final int? consentsGrantedCount;
  final int? implantsCount;
  final String? pharmacyName;

  const ProfileAccountSummary({
    this.quotesToSign,
    this.coverageLabel,
    this.referringDoctorName,
    this.dependentsCount,
    this.consentsGrantedCount,
    this.implantsCount,
    this.pharmacyName,
  });

  static const empty = ProfileAccountSummary();

  // Pas d'action en attente (0) : badge masqué plutôt que « 0 à signer ».
  String? get quotesToSignLabel => (quotesToSign == null || quotesToSign == 0)
      ? null
      : '$quotesToSign à signer';

  String? get dependentsLabel => dependentsCount == null
      ? null
      : '$dependentsCount ${dependentsCount == 1 ? 'compte' : 'comptes'}';

  String? get consentsGrantedLabel => consentsGrantedCount == null
      ? null
      : '$consentsGrantedCount '
          '${consentsGrantedCount == 1 ? 'accordé' : 'accordés'}';

  String? get implantsLabel => implantsCount == null
      ? null
      : '$implantsCount ${implantsCount == 1 ? 'implant' : 'implants'}';

  @override
  List<Object?> get props => [
        quotesToSign,
        coverageLabel,
        referringDoctorName,
        dependentsCount,
        consentsGrantedCount,
        implantsCount,
        pharmacyName,
      ];
}

final class ProfileError extends ProfileState {
  final String message;

  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

final class ProfileToggleFailed extends ProfileState {
  final ProfileLoaded previousState;
  final String message;

  const ProfileToggleFailed(this.previousState, this.message);

  @override
  List<Object?> get props => [previousState, message];
}
