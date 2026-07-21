import 'package:equatable/equatable.dart';

abstract class PatientsEvent {
  const PatientsEvent();
}

class PatientsLoadRequested extends PatientsEvent {
  const PatientsLoadRequested();
}

/// Recherche serveur (#4043) — remplace le filtrage en mémoire, qui ne
/// scale plus au-delà de quelques centaines de dossiers. Le debounce est
/// géré côté UI (patients_page.dart), pas ici.
class PatientsSearchChanged extends PatientsEvent with Equatable {
  const PatientsSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// Soumission du formulaire de création rapide (#4038, écran accueil).
class PatientsCreateRequested extends PatientsEvent {
  const PatientsCreateRequested({
    required this.firstName,
    required this.lastName,
    this.phone,
    this.birthDate,
  });

  final String firstName;
  final String lastName;
  final String? phone;
  final DateTime? birthDate;
}
