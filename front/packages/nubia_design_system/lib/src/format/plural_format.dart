/// Accorde un mot au singulier pour 0 et 1, au pluriel au-delà — en
/// français, 0 et 1 commandent le singulier (ex. « 1 restant », pas
/// « 1 restants »). Partagé entre les apps pour éviter le pluriel codé en
/// dur sur les compteurs (#6982).
String pluralize(num count, String singular, [String? plural]) {
  return count.abs() < 2 ? singular : (plural ?? '${singular}s');
}
