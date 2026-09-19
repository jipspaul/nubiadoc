abstract class CorrespondentsEvent {
  const CorrespondentsEvent();
}

class CorrespondentsLoadRequested extends CorrespondentsEvent {
  const CorrespondentsLoadRequested();
}

class CorrespondentsCreateRequested extends CorrespondentsEvent {
  const CorrespondentsCreateRequested({
    required this.displayName,
    this.specialty,
    this.email,
    this.phone,
    this.address,
    this.rpps,
    this.notes,
  });

  final String displayName;
  final String? specialty;
  final String? email;
  final String? phone;
  final String? address;
  final String? rpps;
  final String? notes;
}

class CorrespondentsUpdateRequested extends CorrespondentsEvent {
  const CorrespondentsUpdateRequested({
    required this.id,
    required this.displayName,
    this.specialty,
    this.email,
    this.phone,
    this.address,
    this.rpps,
    this.notes,
  });

  final String id;
  final String displayName;
  final String? specialty;
  final String? email;
  final String? phone;
  final String? address;
  final String? rpps;
  final String? notes;
}

class CorrespondentsDeleteRequested extends CorrespondentsEvent {
  const CorrespondentsDeleteRequested(this.id);

  final String id;
}
