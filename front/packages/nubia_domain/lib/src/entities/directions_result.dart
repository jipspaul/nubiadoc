class DirectionsResult {
  final String deeplink;
  final int? durationMinutes;
  final double? distanceKm;

  const DirectionsResult({
    required this.deeplink,
    this.durationMinutes,
    this.distanceKm,
  });
}
