import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/signature_repository.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_event.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_state.dart';
import 'package:url_launcher/url_launcher.dart';

@injectable
class SignatureBloc extends Bloc<SignatureEvent, SignatureState> {
  final SignatureRepository _repository;

  SignatureBloc(this._repository) : super(const SignaturePending()) {
    on<SignatureStartRequested>(_onStartRequested);
    on<SignatureConfirmed>(_onConfirmed);
    on<SignatureCancelled>(_onCancelled);
  }

  Future<void> _onStartRequested(
    SignatureStartRequested event,
    Emitter<SignatureState> emit,
  ) async {
    emit(const SignatureInProgress());
    final result = await _repository.getSignatureUrl(
      documentId: event.documentId,
      idempotencyKey: event.idempotencyKey,
    );
    result.fold(
      (failure) => emit(SignatureFailed(failure.message)),
      (url) async {
        final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (!launched) {
          emit(const SignatureFailed("Impossible d'ouvrir le lien de signature."));
        }
        // L'état reste SignatureInProgress : le retour arrive via SignatureConfirmed
        // (deep-link nubia://documents/:id/sign?status=signed).
      },
    );
  }

  Future<void> _onConfirmed(
    SignatureConfirmed event,
    Emitter<SignatureState> emit,
  ) async {
    // Valider côté serveur avant de changer d'état.
    final current = state;
    if (current is! SignatureInProgress) return;
    emit(const SignatureSigned());
  }

  void _onCancelled(
    SignatureCancelled event,
    Emitter<SignatureState> emit,
  ) {
    if (state is! SignatureInProgress) return;
    emit(const SignaturePending());
  }
}
