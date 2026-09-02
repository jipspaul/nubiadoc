import 'package:equatable/equatable.dart';

/// Actes de soin proposables — miroir de `nurse::requests::ALLOWED_ACTS`
/// (`api/src/nurse/requests.rs`) avec leur libellé affiché au patient.
const Map<String, String> homeCareActs = {
  'prise_de_sang': 'Prise de sang',
  'pansement': 'Pansement',
  'injection': 'Injection',
  'perfusion': 'Perfusion',
  'toilette': 'Toilette',
  'surveillance': 'Surveillance',
};

/// Libellés des statuts du cycle de visite (`requested→offered→accepted→
/// en_route→arrived→done`, + `cancelled`/`expired`) — miroir de
/// `VisitDto.status` côté back (`api/src/nurse/requests.rs`).
const Map<String, String> visitStatusLabels = {
  'requested': 'Demande envoyée',
  'offered': 'Recherche d\'une infirmière',
  'accepted': 'Infirmière en route',
  'en_route': 'Infirmière en route',
  'arrived': 'Infirmière sur place',
  'done': 'Visite terminée',
  'cancelled': 'Demande annulée',
  'expired': 'Demande expirée',
};

/// Statuts depuis lesquels le patient peut encore annuler sa demande —
/// miroir de la contrainte `WHERE status IN (...)` de
/// `cancel_account_visit_request` (`api/src/nurse/requests.rs`).
const Set<String> cancellableVisitStatuses = {
  'requested',
  'offered',
  'accepted',
  'en_route',
  'arrived',
};

/// Une demande de visite infirmière à domicile
/// (`/v1/account/visit-requests*`).
class VisitRequest extends Equatable {
  const VisitRequest({
    required this.id,
    required this.status,
    required this.requestedActs,
    required this.address,
    required this.estimatedPriceCents,
  });

  final String id;
  final String status;
  final List<String> requestedActs;
  final Map<String, dynamic> address;
  final int estimatedPriceCents;

  static VisitRequest fromJson(Map<String, dynamic> j) => VisitRequest(
        id: j['id'] as String,
        status: j['status'] as String? ?? 'requested',
        requestedActs:
            (j['requested_acts'] as List<dynamic>? ?? []).cast<String>(),
        address: (j['address'] as Map<String, dynamic>?) ?? const {},
        estimatedPriceCents: j['estimated_price_cents'] as int? ?? 0,
      );

  String get addressLine =>
      '${address['line1'] ?? ''}, ${address['postal_code'] ?? ''} '
      '${address['city'] ?? ''}';

  @override
  List<Object?> get props => [id, status];
}
