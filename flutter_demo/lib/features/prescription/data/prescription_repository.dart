import '../models/prescription.dart';

/// Contrat du dépôt ordonnance — praticien uniquement.
abstract class PrescriptionRepository {
  /// GET /v1/cabinet/prescriptions — liste.
  Future<List<Prescription>> fetchAll();

  /// POST /v1/cabinet/prescriptions — créer une ordonnance.
  Future<Prescription> create({
    required String patientId,
    required List<PrescriptionItem> items,
  });

  /// POST /v1/cabinet/prescriptions/{id}/sign — signer (eIDAS via Yousign).
  Future<Prescription> sign(String id);

  /// Patients du cabinet disponibles pour le sélecteur.
  Future<List<PatientSummary>> fetchPatients();
}

/// Implémentation fictive pour POC/démo — données non-PII.
class FakePrescriptionRepository implements PrescriptionRepository {
  final List<Prescription> _store = [];

  static final _patients = <PatientSummary>[
    const PatientSummary(id: 'pat-001', name: 'Alice Dupont'),
    const PatientSummary(id: 'pat-002', name: 'Bob Martin'),
    const PatientSummary(id: 'pat-003', name: 'Claire Nguyen'),
  ];

  @override
  Future<List<Prescription>> fetchAll() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_store);
  }

  @override
  Future<Prescription> create({
    required String patientId,
    required List<PrescriptionItem> items,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final patient = _patients.firstWhere((p) => p.id == patientId);
    final prescription = Prescription(
      id: 'rx-${DateTime.now().millisecondsSinceEpoch}',
      patientId: patientId,
      patientName: patient.name,
      items: List.unmodifiable(items),
      status: PrescriptionStatus.draft,
    );
    _store.add(prescription);
    return prescription;
  }

  @override
  Future<Prescription> sign(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final idx = _store.indexWhere((p) => p.id == id);
    if (idx == -1) throw StateError('Prescription $id not found');
    final signed = Prescription(
      id: _store[idx].id,
      patientId: _store[idx].patientId,
      patientName: _store[idx].patientName,
      items: _store[idx].items,
      status: PrescriptionStatus.signed,
    );
    _store[idx] = signed;
    return signed;
  }

  @override
  Future<List<PatientSummary>> fetchPatients() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_patients);
  }
}
