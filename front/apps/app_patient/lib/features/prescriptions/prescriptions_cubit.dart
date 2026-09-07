import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PrescriptionsState extends Equatable {
  const PrescriptionsState();

  @override
  List<Object?> get props => [];
}

class PrescriptionsLoading extends PrescriptionsState {
  const PrescriptionsLoading();
}

class PrescriptionsLoaded extends PrescriptionsState {
  const PrescriptionsLoaded(this.prescriptions);

  final List<PatientPrescription> prescriptions;

  @override
  List<Object?> get props => [prescriptions];
}

class PrescriptionsError extends PrescriptionsState {
  const PrescriptionsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Émis ponctuellement quand une URL signée de PDF est prête à ouvrir —
/// capté par un `BlocListener`, ne remplace pas durablement la liste
/// (même pattern que `DocumentsBloc._onDownloadRequested`).
class PrescriptionsDocumentReady extends PrescriptionsState {
  const PrescriptionsDocumentReady(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

class PrescriptionsDocumentError extends PrescriptionsState {
  const PrescriptionsDocumentError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Liste des ordonnances du patient (`GET /v1/account/prescriptions`,
/// #6232) — la tuile « Mes ordonnances » de l'accueil n'avait jusqu'ici
/// aucune destination bien que l'API serve déjà la donnée.
class PrescriptionsCubit extends Cubit<PrescriptionsState> {
  PrescriptionsCubit({
    required ListMyPrescriptionsUseCase listPrescriptions,
    required GetDocumentSignedUrlUseCase getDocumentSignedUrl,
  })  : _listPrescriptions = listPrescriptions,
        _getDocumentSignedUrl = getDocumentSignedUrl,
        super(const PrescriptionsLoading());

  final ListMyPrescriptionsUseCase _listPrescriptions;
  final GetDocumentSignedUrlUseCase _getDocumentSignedUrl;

  Future<void> load() async {
    emit(const PrescriptionsLoading());
    final result = await _listPrescriptions();
    result.fold(
      (failure) => emit(PrescriptionsError(failure.message)),
      (prescriptions) => emit(PrescriptionsLoaded(prescriptions)),
    );
  }

  Future<void> openDocument(String documentId) async {
    final result = await _getDocumentSignedUrl(documentId);
    result.fold(
      (failure) => emit(PrescriptionsDocumentError(failure.message)),
      (url) => emit(PrescriptionsDocumentReady(url)),
    );
  }
}
