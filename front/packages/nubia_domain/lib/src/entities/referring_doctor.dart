import 'package:equatable/equatable.dart';

/// Médecin traitant déclaré par le patient (GET/PUT /v1/account/referring-doctor).
///
/// [providerId] renseigné si le médecin est un praticien Nubia existant ;
/// sinon [name]/[specialty]/[phone]/[email]/[address] proviennent d'une
/// saisie libre du patient (médecin absent de la base Nubia).
class ReferringDoctor extends Equatable {
  final String? providerId;
  final String name;
  final String? specialty;
  final String? phone;
  final String? email;
  final String? address;

  const ReferringDoctor({
    this.providerId,
    required this.name,
    this.specialty,
    this.phone,
    this.email,
    this.address,
  });

  @override
  List<Object?> get props =>
      [providerId, name, specialty, phone, email, address];
}
