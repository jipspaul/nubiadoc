import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Décide si [message] continue le groupe du [previous] message (#5126) :
/// même auteur et même jour. Une continuation n'affiche ni avatar visible,
/// ni nom, ni heure — seul un nouveau groupe (auteur différent, ou premier
/// message d'un nouveau jour) répète l'en-tête complet.
bool isMessageContinuation(
  CabinetTeamMessage message,
  CabinetTeamMessage? previous,
) {
  if (previous == null) return false;
  return previous.senderId == message.senderId &&
      NubiaDate.isSameDay(previous.createdAt, message.createdAt);
}
