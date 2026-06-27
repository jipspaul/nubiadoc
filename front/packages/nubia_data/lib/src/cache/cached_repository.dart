import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

import 'cached_data.dart';

/// Base class for repositories that follow the cache-then-network pattern.
///
/// - Reads: return cached data if non-stale; otherwise fetch from remote,
///   persist to cache, and return the network result.
/// - Writes: delegate to remote first (write-through), then update cache.
abstract class CachedXRepository<T> {
  final Duration maxAge;

  const CachedXRepository({this.maxAge = const Duration(minutes: 5)});

  /// Returns cached value when fresh; otherwise fetches from [fromRemote],
  /// persists via [writeToCache], and returns the network result.
  Future<Either<Failure, R>> cacheFirst<R>({
    required Future<CachedData<R>?> Function() readCache,
    required Future<Either<Failure, R>> Function() fromRemote,
    required Future<void> Function(R) writeToCache,
  }) async {
    final cached = await readCache();
    if (cached != null && !cached.isStale(maxAge)) {
      return Right(cached.data);
    }
    final result = await fromRemote();
    await result.fold(
      (_) async {},
      (data) async {
        try {
          await writeToCache(data);
        } catch (_) {}
      },
    );
    return result;
  }
}
