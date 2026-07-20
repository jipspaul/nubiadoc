abstract class PatientsEvent {
  const PatientsEvent();
}

class PatientsLoadRequested extends PatientsEvent {
  const PatientsLoadRequested();
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
