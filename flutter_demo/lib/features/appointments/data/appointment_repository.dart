import '../models/appointment.dart';

/// Contrat du dépôt RDV.
abstract class AppointmentRepository {
  /// GET /v1/appointments — liste, filtrée par statut si fourni.
  Future<List<Appointment>> fetchAll({AppointmentStatus? status});

  /// GET /v1/appointments/{id} — détail.
  Future<Appointment> fetchById(String id);

  /// POST /v1/appointments — prendre RDV.
  Future<Appointment> book({
    required String providerId,
    required DateTime startsAt,
    required String motif,
  });

  /// POST /v1/appointments/{id}/cancel — annuler.
  Future<void> cancel(String id);
}

/// Implémentation fictive pour POC/démo — données non-PII.
class FakeAppointmentRepository implements AppointmentRepository {
  static final _appointments = <Appointment>[
    Appointment(
      id: 'apt-001',
      providerName: 'Dr Martin',
      motif: 'Pose prothèse',
      startsAt: DateTime.utc(2026, 7, 10, 9, 30),
      status: AppointmentStatus.confirmed,
      address: '12 rue de la Paix, 75001 Paris',
    ),
    Appointment(
      id: 'apt-002',
      providerName: 'Dr Martin',
      motif: 'Contrôle implant',
      startsAt: DateTime.utc(2026, 8, 5, 14, 0),
      status: AppointmentStatus.requested,
      address: '12 rue de la Paix, 75001 Paris',
    ),
    Appointment(
      id: 'apt-003',
      providerName: 'Dr Nguyen',
      motif: 'Détartrage',
      startsAt: DateTime.utc(2026, 4, 20, 10, 0),
      status: AppointmentStatus.done,
      address: '5 avenue Kléber, 75016 Paris',
    ),
  ];

  /// Mutable pour simuler le booking / l'annulation en mémoire.
  final List<Appointment> _store = List.of(_appointments);

  @override
  Future<List<Appointment>> fetchAll({AppointmentStatus? status}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (status == null) return List.unmodifiable(_store);
    return _store.where((a) => a.status == status).toList();
  }

  @override
  Future<Appointment> fetchById(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _store.firstWhere((a) => a.id == id);
  }

  @override
  Future<Appointment> book({
    required String providerId,
    required DateTime startsAt,
    required String motif,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final apt = Appointment(
      id: 'apt-${DateTime.now().millisecondsSinceEpoch}',
      providerName: providerId,
      motif: motif,
      startsAt: startsAt,
      status: AppointmentStatus.requested,
    );
    _store.add(apt);
    return apt;
  }

  @override
  Future<void> cancel(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final idx = _store.indexWhere((a) => a.id == id);
    if (idx == -1) throw StateError('Appointment $id not found');
    _store[idx] = Appointment(
      id: _store[idx].id,
      providerName: _store[idx].providerName,
      motif: _store[idx].motif,
      startsAt: _store[idx].startsAt,
      status: AppointmentStatus.cancelled,
      address: _store[idx].address,
    );
  }
}
