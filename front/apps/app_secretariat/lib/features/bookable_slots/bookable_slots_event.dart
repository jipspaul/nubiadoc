abstract class BookableSlotsEvent {
  const BookableSlotsEvent();
}

class BookableSlotsLoadRequested extends BookableSlotsEvent {
  const BookableSlotsLoadRequested();
}

class CreateSlotRequested extends BookableSlotsEvent {
  const CreateSlotRequested({required this.startsAt, required this.endsAt});

  final DateTime startsAt;
  final DateTime endsAt;
}
