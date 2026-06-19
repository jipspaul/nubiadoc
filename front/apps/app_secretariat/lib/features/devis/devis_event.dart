abstract class DevisEvent {
  const DevisEvent();
}

class DevisLoadRequested extends DevisEvent {
  const DevisLoadRequested();
}

class DevisDetailLoadRequested extends DevisEvent {
  const DevisDetailLoadRequested(this.id);

  final String id;
}
