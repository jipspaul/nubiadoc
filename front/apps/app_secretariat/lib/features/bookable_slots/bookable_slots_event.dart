abstract class BookableSlotsEvent {
  const BookableSlotsEvent();
}

class BookableSlotsLoadRequested extends BookableSlotsEvent {
  const BookableSlotsLoadRequested();
}

class CreateSlotRequested extends BookableSlotsEvent {
  const CreateSlotRequested({
    required this.practitionerId,
    required this.startsAt,
    required this.endsAt,
  });

  /// Praticien auquel rattacher le créneau (UUID). Obligatoire : le back rejette
  /// un `practitioner_id` vide par un 422 (#3465).
  final String practitionerId;
  final DateTime startsAt;
  final DateTime endsAt;
}
