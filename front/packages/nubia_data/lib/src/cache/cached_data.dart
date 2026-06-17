class CachedData<T> {
  final T data;
  final DateTime cachedAt;

  const CachedData({required this.data, required this.cachedAt});

  bool isStale(Duration maxAge) =>
      DateTime.now().difference(cachedAt) > maxAge;
}
