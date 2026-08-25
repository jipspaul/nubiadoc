/// Segment de texte issu du parsing d'une mention `@Nom` (#5129) dans le
/// corps d'un message : le rendu (widget) reste séparé du parsing (pur).
class MentionTextSegment {
  const MentionTextSegment.text(this.text) : isMention = false;
  const MentionTextSegment.mention(this.text) : isMention = true;

  final String text;
  final bool isMention;
}

final _mentionPattern = RegExp(r'@[\p{L}\p{N}_]+', unicode: true);

/// Découpe [body] en segments texte / mention (`@Nom`) pour permettre un
/// rendu riche qui distingue visuellement une mention (tâche adressée) du
/// reste du message.
List<MentionTextSegment> parseMentionSegments(String body) {
  final segments = <MentionTextSegment>[];
  var lastEnd = 0;
  for (final match in _mentionPattern.allMatches(body)) {
    if (match.start > lastEnd) {
      segments.add(
        MentionTextSegment.text(body.substring(lastEnd, match.start)),
      );
    }
    segments.add(MentionTextSegment.mention(match.group(0)!));
    lastEnd = match.end;
  }
  if (lastEnd < body.length) {
    segments.add(MentionTextSegment.text(body.substring(lastEnd)));
  }
  return segments;
}
