//! Cubit léger qui charge l'identité patient (nom, date de naissance) pour
//! le bandeau en tête de l'écran plans de traitement (#5024) — détaché de
//! [TreatmentPlansCubit] pour ne pas coupler le chargement des plans à
//! celui de l'identité patient. Source : `GetCabinetPatientUseCase`, le
//! même use case que `PatientsBloc` (fiche patient).
//!
//! Modes d'échec : erreur silencieuse — le bandeau retombe sur un nom
//! générique (cf. [PatientHeaderBar]) plutôt que de bloquer l'écran, la
//! liste des plans restant l'information principale de la page.

import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

class PatientHeaderCubit extends Cubit<CabinetPatient?> {
  PatientHeaderCubit({
    required this.patientId,
    required GetCabinetPatientUseCase getPatient,
  })  : _getPatient = getPatient,
        super(null) {
    _load();
  }

  final String patientId;
  final GetCabinetPatientUseCase _getPatient;

  Future<void> _load() async {
    final result = await _getPatient(patientId);
    result.fold((_) {}, emit);
  }
}
