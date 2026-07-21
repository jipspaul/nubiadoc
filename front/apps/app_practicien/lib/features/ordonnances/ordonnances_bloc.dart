import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ordonnances_event.dart';
import 'ordonnances_state.dart';

class OrdonnancesBloc extends Bloc<OrdonnancesEvent, OrdonnancesState> {
  final CreatePrescriptionUseCase _create;
  final SignPrescriptionUseCase _sign;
  final ListPrescriptionTemplatesUseCase _listTemplates;
  final ApplyPrescriptionTemplateUseCase _applyTemplate;

  OrdonnancesBloc({
    required CreatePrescriptionUseCase create,
    required SignPrescriptionUseCase sign,
    required ListPrescriptionTemplatesUseCase listTemplates,
    required ApplyPrescriptionTemplateUseCase applyTemplate,
  })  : _create = create,
        _sign = sign,
        _listTemplates = listTemplates,
        _applyTemplate = applyTemplate,
        super(const OrdonnancesInitial()) {
    on<OrdonnancesCreateRequested>(_onCreate);
    on<OrdonnancesSignRequested>(_onSign);
    on<OrdonnancesApplyTemplateRequested>(_onApplyTemplate);
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
    if (current is! OrdonnancesCreated) return;
    emit(OrdonnancesApplyingTemplate(current.prescription));
    try {
      final result = await _applyTemplate(
        prescriptionId: event.prescriptionId,
        templateId: event.templateId,
      );
      result.fold(
        (failure) => emit(OrdonnancesError(failure.message)),
        (prescription) => emit(OrdonnancesCreated(prescription)),
      );
    } catch (_) {
      emit(const OrdonnancesError("Erreur d'application du modèle."));
    }
  }
}
