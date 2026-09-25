import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// État de l'étape « signature & tampon » de fin d'onboarding (#7148/#7147).
/// Réservée aux comptes praticien côté back ([UploadProviderSignatureUseCase]
/// exige `ProPractitionerClaims`) — un secrétaire/admin obtient un 403,
/// affiché comme [error] sans bloquer la suite (étape sautable).
class ProviderStampState extends Equatable {
  const ProviderStampState({
    this.signature,
    this.stamp,
    this.uploadingSignature = false,
    this.uploadingStamp = false,
    this.signatureUploaded = false,
    this.stampUploaded = false,
    this.error,
  });

  final PickedFile? signature;
  final PickedFile? stamp;
  final bool uploadingSignature;
  final bool uploadingStamp;
  final bool signatureUploaded;
  final bool stampUploaded;
  final String? error;

  ProviderStampState copyWith({
    PickedFile? signature,
    PickedFile? stamp,
    bool? uploadingSignature,
    bool? uploadingStamp,
    bool? signatureUploaded,
    bool? stampUploaded,
    String? error,
    bool clearError = false,
  }) =>
      ProviderStampState(
        signature: signature ?? this.signature,
        stamp: stamp ?? this.stamp,
        uploadingSignature: uploadingSignature ?? this.uploadingSignature,
        uploadingStamp: uploadingStamp ?? this.uploadingStamp,
        signatureUploaded: signatureUploaded ?? this.signatureUploaded,
        stampUploaded: stampUploaded ?? this.stampUploaded,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [
        signature,
        stamp,
        uploadingSignature,
        uploadingStamp,
        signatureUploaded,
        stampUploaded,
        error,
      ];
}

class ProviderStampCubit extends Cubit<ProviderStampState> {
  ProviderStampCubit({
    required UploadProviderSignatureUseCase uploadSignature,
    required UploadProviderStampUseCase uploadStamp,
  })  : _uploadSignature = uploadSignature,
        _uploadStamp = uploadStamp,
        super(const ProviderStampState());

  final UploadProviderSignatureUseCase _uploadSignature;
  final UploadProviderStampUseCase _uploadStamp;

  Future<void> pickAndUploadSignature(PickedFile file) async {
    emit(state.copyWith(
      signature: file,
      signatureUploaded: false,
      uploadingSignature: true,
      clearError: true,
    ));
    final result = await _uploadSignature(
      bytes: file.bytes,
      filename: file.name,
      mimeType: file.mimeType,
    );
    result.fold(
      (failure) => emit(state.copyWith(
        uploadingSignature: false,
        error: failure.message,
      )),
      (_) => emit(state.copyWith(
        uploadingSignature: false,
        signatureUploaded: true,
      )),
    );
  }

  Future<void> pickAndUploadStamp(PickedFile file) async {
    emit(state.copyWith(
      stamp: file,
      stampUploaded: false,
      uploadingStamp: true,
      clearError: true,
    ));
    final result = await _uploadStamp(
      bytes: file.bytes,
      filename: file.name,
      mimeType: file.mimeType,
    );
    result.fold(
      (failure) => emit(state.copyWith(
        uploadingStamp: false,
        error: failure.message,
      )),
      (_) => emit(state.copyWith(
        uploadingStamp: false,
        stampUploaded: true,
      )),
    );
  }
}
