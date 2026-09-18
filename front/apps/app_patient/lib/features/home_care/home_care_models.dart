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

/// Adresse de visite, décodée **de façon tolérante** depuis le `jsonb`
/// libre `address` de l'API (`api/src/nurse/requests.rs`, `serde_json::Value`).
///
/// #6961 / #6861 : la base contient des valeurs historiques non-objet
/// (`[]`, `"pas un objet"`, `null`, `true`…) que `GET /v1/account/visit-requests`
/// re-sert telles quelles. [tryParse] ne lève **jamais** : un objet donne ses
/// champs, une chaîne non vide devient une adresse libre ([line1]), tout le
/// reste (`null`, liste, booléen, nombre…) donne `null`.
class VisitAddress extends Equatable {
  const VisitAddress({this.line1, this.postalCode, this.city});

  final String? line1;
  final String? postalCode;
  final String? city;

  /// Décode `raw` sans jamais lever — cf. doc de classe.
  static VisitAddress? tryParse(Object? raw) {
    if (raw is Map) {
      final address = VisitAddress(
        line1: _field(raw['line1']),
        postalCode: _field(raw['postal_code']),
        city: _field(raw['city']),
      );
      return address.isEmpty ? null : address;
    }
    if (raw is String) {
      final freeform = raw.trim();
      return freeform.isEmpty ? null : VisitAddress(line1: freeform);
    }
    return null;
  }

  /// Champ d'adresse : chaîne (trim, vide → `null`) ou nombre (code postal
  /// stocké en entier) ; tout autre type est ignoré.
  static String? _field(Object? v) {
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is num) return v.toString();
    return null;
  }

  bool get isEmpty => line1 == null && postalCode == null && city == null;

  /// « line1, code postal ville » sans séparateur orphelin (#7121).
  String get line {
    final postalCity = [postalCode, city].whereType<String>().join(' ');
    return [line1, postalCity]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  @override
  List<Object?> get props => [line1, postalCode, city];
}

/// Une demande de visite infirmière à domicile
/// (`/v1/account/visit-requests*`).
class VisitRequest extends Equatable {
  const VisitRequest({
    required this.id,
    required this.status,
    required this.requestedActs,
    required this.estimatedPriceCents,
    this.address,
    this.nurseDisplayName,
  });

  final String id;
  final String status;
  final List<String> requestedActs;

  /// `null` quand l'API ne renvoie pas d'objet adresse exploitable
  /// (absent, `null`, ou valeur historique mal typée — cf. [VisitAddress]).
  final VisitAddress? address;
  final int estimatedPriceCents;

  /// Nom affiché de l'infirmière assignée, dès qu'une offre a été acceptée
  /// (`null` avant, symétrique de `patient_display_name` côté infirmière).
  final String? nurseDisplayName;

  /// Décodage tolérant : seul `id` est indispensable (lève une
  /// [FormatException] s'il manque ou n'est pas une chaîne — la ligne est
  /// alors inexploitable et c'est à l'appelant de l'écarter, cf.
  /// `decodeVisitRequests`). Tout autre champ mal typé retombe sur sa valeur
  /// par défaut sans `TypeError`.
  static VisitRequest fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('visit request: `id` manquant ou invalide');
    }
    final status = j['status'];
    final acts = j['requested_acts'];
    final price = j['estimated_price_cents'];
    final nurse = j['nurse_display_name'];
    return VisitRequest(
      id: id,
      status: status is String && status.isNotEmpty ? status : 'requested',
      requestedActs:
          acts is List ? acts.whereType<String>().toList() : const [],
      address: VisitAddress.tryParse(j['address']),
      estimatedPriceCents: price is num ? price.toInt() : 0,
      nurseDisplayName: nurse is String && nurse.isNotEmpty ? nurse : null,
    );
  }

  String get addressLine => address?.line ?? '';

  @override
  List<Object?> get props => [id, status];
}
