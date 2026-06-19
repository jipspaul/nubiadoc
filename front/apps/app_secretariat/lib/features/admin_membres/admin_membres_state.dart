import 'package:nubia_domain/nubia_domain.dart';

abstract class AdminMembresState {
  const AdminMembresState();
}

class AdminMembresInitial extends AdminMembresState {
  const AdminMembresInitial();

  @override
  bool operator ==(Object other) => other is AdminMembresInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class AdminMembresLoading extends AdminMembresState {
  const AdminMembresLoading();

  @override
  bool operator ==(Object other) => other is AdminMembresLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class AdminMembresLoaded extends AdminMembresState {
  const AdminMembresLoaded({required this.members, required this.secretariats});

  final List<Member> members;
  final List<Secretariat> secretariats;

  @override
  bool operator ==(Object other) =>
      other is AdminMembresLoaded &&
      other.members.length == members.length &&
      other.secretariats.length == secretariats.length;

  @override
  int get hashCode => Object.hash(members.length, secretariats.length);
}

class AdminMembresError extends AdminMembresState {
  const AdminMembresError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is AdminMembresError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
