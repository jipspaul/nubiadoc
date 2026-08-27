import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ordonnances_event.dart';
import 'ordonnances_state.dart';

class OrdonnancesBloc extends Bloc<OrdonnancesEvent, OrdonnancesState> {
  final CreatePrescriptionUseCase _create;
  final SignPrescriptionUseCase _sign;
  final ListPrescriptionTemplatesUseCase _listTemplates;
  final ApplyPrescriptionTemplateUseCase _applyTemplate;
  final ListPrescriptionsUseCase _list;
  final RenewPrescriptionUseCase _renew;

  OrdonnancesBloc({
    required CreatePrescriptionUseCase create,
    required SignPrescriptionUseCase sign,
    required ListPrescriptionTemplatesUseCase listTemplates,
    required ApplyPrescriptionTemplateUseCase applyTemplate,
    required ListPrescriptionsUseCase list,
    required RenewPrescriptionUseCase renew,
  })  : _create = create,
        _sign = sign,
        _listTemplates = listTemplates,
        _applyTemplate = applyTemplate,
        _list = list,
        _renew = renew,
        super(const OrdonnancesInitial()) {
    on<OrdonnancesCreateRequested>(_onCreate);
    on<OrdonnancesSignRequested>(_onSign);
    on<OrdonnancesApplyTemplateRequested>(_onApplyTemplate);
    on<OrdonnancesListRequested>(_onList);
    on<OrdonnancesRenewRequested>(_onRenew);
  }

  /// Exposé pour le sélecteur de modèle (#4074) : liste indépendante de
  /// l'état du bloc (n'émet aucun état, appelée directement par l'UI via un
  /// `FutureBuilder`/picker — même pattern que `SendToPharmacyCubit.load`
  /// pour la liste des pharmacies, mais ici un simple appel one-shot suffit,
  /// pas besoin d'un état dédié pour une liste qui ne change pas pendant
  /// l'ouverture du picker).
  Future<List<PrescriptionTemplate>> loadTemplates() async {
    final result = await _listTemplates();
    return result.fold((_) => const [], (templates) => templates);
  }

  Future<void> _onCreate(
    OrdonnancesCreateRequested event,
    Emitter<OrdonnancesState> emit,
  ) async {
    emit(const OrdonnancesLoading());
    try {
      final result = await _create(
        patientId: event.patientId,
        items: event.items,
      );
      result.fold(
        (failure) => emit(OrdonnancesError(failure.message)),
        (prescription) => emit(OrdonnancesCreated(prescription)),
      );
    } catch (_) {
      emit(const OrdonnancesError('Erreur de création.'));
    }
  }

  Future<void> _onSign(
    OrdonnancesSignRequested event,
    Emitter<OrdonnancesState> emit,
  ) async {
    if (state is OrdonnancesSigningInProgress) return;
    final current = state;
    if (current is! OrdonnancesCreated) return;
    emit(OrdonnancesSigningInProgress(current.prescription));
    try {
      final result = await _sign(event.prescriptionId);
      result.fold(
        (failure) => emit(OrdonnancesError(failure.message)),
        (prescription) => emit(OrdonnancesSigned(prescription)),
      );
    } catch (_) {
      emit(const OrdonnancesError('Erreur de signature.'));
    }
  }

  Future<void> _onApplyTemplate(
    OrdonnancesApplyTemplateRequested event,
    Emitter<OrdonnancesState> emit,
  ) async {
    final current = state;
    if (current is OrdonnancesCreated) {
      emit(OrdonnancesApplyingTemplate(current.prescription));
      try {
        final result = await _applyTemplate(
          prescriptionId: event.prescriptionId ?? current.prescription.id,
          templateId: event.templateId,
        );
        result.fold(
          (failure) => emit(OrdonnancesError(failure.message)),
          (prescription) => emit(OrdonnancesCreated(prescription)),
        );
      } catch (_) {
        emit(const OrdonnancesError("Erreur d'application du modèle."));
      }
      return;
    }

    // #4988 : modèle choisi depuis l'écran de composition, avant toute
    // création de brouillon. `apply-template` exige côté serveur un
    // `prescription.id` déjà existant — le brouillon est donc créé
    // implicitement avec les lignes du modèle, sans imposer d'étape
    // manuelle de création préalable au praticien.
    final patientId = event.patientId;
    if (patientId == null) return;
    emit(const OrdonnancesApplyingTemplate());
    try {
      final templates = await loadTemplates();
      PrescriptionTemplate? template;
      for (final t in templates) {
        if (t.id == event.templateId) {
          template = t;
          break;
        }
      }
      if (template == null) {
        emit(const OrdonnancesError("Erreur d'application du modèle."));
        return;
      }
      final result = await _create(patientId: patientId, items: template.items);
      result.fold(
        (failure) => emit(OrdonnancesError(failure.message)),
        (prescription) => emit(OrdonnancesCreated(prescription)),
      );
    } catch (_) {
      emit(const OrdonnancesError("Erreur d'application du modèle."));
    }
  }

  /// #4132 : charge l'historique des ordonnances du patient à l'ouverture
  /// de la page.
  Future<void> _onList(
    OrdonnancesListRequested event,
    Emitter<OrdonnancesState> emit,
  ) async {
    emit(const OrdonnancesLoading());
    try {
      final result = await _list(event.patientId);
      result.fold(
        (failure) => emit(OrdonnancesError(failure.message)),
        (ordonnances) => emit(OrdonnancesLoaded(ordonnances)),
      );
    } catch (_) {
      emit(const OrdonnancesError("Erreur de chargement de l'historique."));
    }
  }

  /// #4132 : renouvelle une ordonnance passée — duplique ses lignes dans un
  /// nouveau brouillon, puis affiche ce brouillon (même écran de relecture
  /// qu'après une création classique).
  Future<void> _onRenew(
    OrdonnancesRenewRequested event,
    Emitter<OrdonnancesState> emit,
  ) async {
    emit(const OrdonnancesLoading());
    try {
      final result = await _renew(event.prescriptionId);
      result.fold(
        (failure) => emit(OrdonnancesError(failure.message)),
        (prescription) => emit(OrdonnancesCreated(prescription)),
      );
    } catch (_) {
      emit(const OrdonnancesError('Erreur de renouvellement.'));
    }
  }
}
