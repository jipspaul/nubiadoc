import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';

// ---------------------------------------------------------------------------
// Request value object
// ---------------------------------------------------------------------------

class ProRegisterRequest extends Equatable {
  const ProRegisterRequest({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    this.rpps,
    this.adeli,
    required this.raisonSociale,
    this.siret,
    required this.specialite,
  });

  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String? rpps;
  final String? adeli;
  final String raisonSociale;
  final String? siret;
  final String specialite;

  @override
  List<Object?> get props =>
      [email, password, firstName, lastName, rpps, adeli, raisonSociale, siret, specialite];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class ProRegisterState extends Equatable {
  const ProRegisterState();

  @override
  List<Object?> get props => [];
}

final class ProRegisterIdle extends ProRegisterState {
  const ProRegisterIdle();
}

final class ProRegisterLoading extends ProRegisterState {
  const ProRegisterLoading();
}

final class ProRegisterSuccess extends ProRegisterState {
  const ProRegisterSuccess();
}

final class ProRegisterFailure extends ProRegisterState {
  const ProRegisterFailure(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Cubit
// ---------------------------------------------------------------------------

/// Cubit d'inscription praticien.
///
/// Le use case ProRegisterUseCase (D1) sera injecté ici une fois disponible.
/// Pour l'instant le `submit` émet une erreur temporaire tant que D1 n'est
/// pas mergé.
class ProRegisterCubit extends Cubit<ProRegisterState>
    with SafeEmitMixin<ProRegisterState> {
  ProRegisterCubit() : super(const ProRegisterIdle());

  Future<void> submit(ProRegisterRequest request) async {
    safeEmit(const ProRegisterLoading());
    // TODO(D1): appeler ProRegisterUseCase quand disponible.
    safeEmit(const ProRegisterFailure(
      'Inscription praticien non encore disponible.',
    ));
  }
}
