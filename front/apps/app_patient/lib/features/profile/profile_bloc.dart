import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState>
    with SafeEmitMixin<ProfileState> {
  final GetAccountUseCase _getAccount;
  final UpdateAccountUseCase _updateAccount;
  final UserSettingsRepository _userSettings;
  final NotificationRepository _notificationRepo;
  final GetPendingQuotesUseCase _getPendingQuotes;
  final GetCoverageUseCase _getCoverage;
  final GetReferringDoctorUseCase _getReferringDoctor;
  final ListDependentsUseCase _listDependents;
  final ListConsentsUseCase _listConsents;
  final ListImplantPassportUseCase _listImplants;
  final GetMyPharmacyUseCase _getMyPharmacy;

  ProfileBloc({
    required GetAccountUseCase getAccount,
    required UpdateAccountUseCase updateAccount,
    required UserSettingsRepository userSettings,
    required NotificationRepository notificationRepo,
    required GetPendingQuotesUseCase getPendingQuotes,
    required GetCoverageUseCase getCoverage,
    required GetReferringDoctorUseCase getReferringDoctor,
    required ListDependentsUseCase listDependents,
    required ListConsentsUseCase listConsents,
    required ListImplantPassportUseCase listImplants,
    required GetMyPharmacyUseCase getMyPharmacy,
  })  : _getAccount = getAccount,
        _updateAccount = updateAccount,
        _userSettings = userSettings,
        _notificationRepo = notificationRepo,
        _getPendingQuotes = getPendingQuotes,
        _getCoverage = getCoverage,
        _getReferringDoctor = getReferringDoctor,
        _listDependents = listDependents,
        _listConsents = listConsents,
        _listImplants = listImplants,
        _getMyPharmacy = getMyPharmacy,
        super(const ProfileInitial()) {
    on<ProfileLoadRequested>(_onLoadRequested);
    on<BiometricToggleRequested>(_onBiometricToggle);
    on<ToggleEmailRdv>(_onToggleEmailRdv);
    on<TogglePushRdv>(_onTogglePushRdv);
    on<PhoneUpdateRequested>(_onPhoneUpdate);
  }

  Future<void> _onLoadRequested(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(const ProfileLoading());
    try {
      final result = await _getAccount();
      await result.fold(
        (failure) async => safeEmit(ProfileError(failure.message)),
        (account) async {
          final biometric = await _userSettings.getBiometricEnabled();
          final prefsResult = await _notificationRepo.getPreferences();
          final prefs = prefsResult.fold((_) => null, (p) => p);
          final accountSummary = await _loadAccountSummary();
          safeEmit(ProfileLoaded(account,
              biometricEnabled: biometric,
              notifPrefs: prefs,
              accountSummary: accountSummary));
        },
      );
    } catch (_) {
      safeEmit(const ProfileError('Erreur de chargement du profil.'));
    }
  }

  /// Valeurs courantes des tuiles « Mon compte » (#5232). Chaque source est
  /// indépendante : l'échec de l'une (ou une exception) ne doit pas empêcher
  /// l'affichage du reste du profil — juste dégrader la tuile concernée
  /// (pas de valeur, chevron conservé).
  Future<ProfileAccountSummary> _loadAccountSummary() async {
    try {
      final quotesFuture = _getPendingQuotes();
      final coverageFuture = _getCoverage();
      final doctorFuture = _getReferringDoctor();
      final dependentsFuture = _listDependents();
      final consentsFuture = _listConsents();
      final implantsFuture = _listImplants();
      final pharmacyFuture = _getMyPharmacy();

      final quotes = (await quotesFuture).fold((_) => null, (v) => v);
      final coverage = (await coverageFuture).fold((_) => null, (v) => v);
      final doctor = (await doctorFuture).fold((_) => null, (v) => v);
      final dependents = (await dependentsFuture).fold((_) => null, (v) => v);
      final consents = (await consentsFuture).fold((_) => null, (v) => v);
      final implants = (await implantsFuture).fold((_) => null, (v) => v);
      final pharmacy = (await pharmacyFuture).fold((_) => null, (v) => v);

      return ProfileAccountSummary(
        quotesToSign: quotes?.where((q) => q.canSign).length,
        coverageLabel: _nonEmpty(coverage?.insuranceName),
        referringDoctorName: _nonEmpty(doctor?.name),
        dependentsCount: dependents?.length,
        consentsGrantedCount: consents?.where((c) => c.granted).length,
        implantsCount: implants?.length,
        pharmacyName: _nonEmpty(pharmacy?.name),
      );
    } catch (_) {
      return ProfileAccountSummary.empty;
    }
  }

  static String? _nonEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  Future<void> _onBiometricToggle(
    BiometricToggleRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final previous = state as ProfileLoaded;
    emit(ProfileLoaded(previous.account,
        biometricEnabled: event.enabled,
        notifPrefs: previous.notifPrefs,
        accountSummary: previous.accountSummary));
    try {
      await _userSettings.setBiometricEnabled(event.enabled);
    } catch (e) {
      safeEmit(ProfileToggleFailed(previous, e.toString()));
    }
  }

  Future<void> _onToggleEmailRdv(
    ToggleEmailRdv event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final previous = state as ProfileLoaded;
    final updated =
        (previous.notifPrefs ?? const NotificationPreferences.allEnabled())
            .copyWith(emailEnabled: event.enabled);
    emit(ProfileLoaded(previous.account,
        biometricEnabled: previous.biometricEnabled,
        notifPrefs: updated,
        accountSummary: previous.accountSummary));
    try {
      await _notificationRepo.updatePreferences(updated);
    } catch (e) {
      safeEmit(ProfileToggleFailed(previous, e.toString()));
    }
  }

  Future<void> _onTogglePushRdv(
    TogglePushRdv event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final previous = state as ProfileLoaded;
    final updated =
        (previous.notifPrefs ?? const NotificationPreferences.allEnabled())
            .copyWith(pushEnabled: event.enabled);
    emit(ProfileLoaded(previous.account,
        biometricEnabled: previous.biometricEnabled,
        notifPrefs: updated,
        accountSummary: previous.accountSummary));
    try {
      await _notificationRepo.updatePreferences(updated);
    } catch (e) {
      safeEmit(ProfileToggleFailed(previous, e.toString()));
    }
  }

  Future<void> _onPhoneUpdate(
    PhoneUpdateRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;
    final previous = state as ProfileLoaded;
    emit(ProfileLoaded(previous.account,
        biometricEnabled: previous.biometricEnabled,
        notifPrefs: previous.notifPrefs,
        phoneUpdating: true,
        accountSummary: previous.accountSummary));
    final result = await _updateAccount(phone: event.phone);
    result.fold(
      (failure) => safeEmit(ProfileToggleFailed(previous, failure.message)),
      (account) => safeEmit(ProfileLoaded(account,
          biometricEnabled: previous.biometricEnabled,
          notifPrefs: previous.notifPrefs,
          accountSummary: previous.accountSummary)),
    );
  }
}
