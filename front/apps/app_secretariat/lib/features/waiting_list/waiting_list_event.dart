abstract class WaitingListEvent {
  const WaitingListEvent();
}

class WaitingListLoadRequested extends WaitingListEvent {
  const WaitingListLoadRequested();
}

class WaitingListOfferSlotRequested extends WaitingListEvent {
  const WaitingListOfferSlotRequested(this.id);
  final String id;
}
