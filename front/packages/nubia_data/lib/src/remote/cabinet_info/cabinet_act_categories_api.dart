import 'package:dio/dio.dart';
import 'package:nubia_core/nubia_core.dart';

class CabinetActCategoriesApi {
  final Dio _dio;

  CabinetActCategoriesApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/cabinet/settings/act-categories (#7186) — une entrée par
  /// catégorie connue, `enabled: true` par défaut si jamais réglée.
  Future<List<({String category, bool enabled})>> getActCategories() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/settings/act-categories',
    );
    final data = (response.data?['data'] as List<dynamic>? ?? []);
    return data
        .map(
          (e) => (
            category: (e as Map<String, dynamic>)['category'] as String,
            enabled: e['enabled'] as bool,
          ),
        )
        .toList();
  }

  /// PUT /v1/cabinet/settings/act-categories — upsert partiel des overrides
  /// soumis (#7186).
  Future<List<({String category, bool enabled})>> updateActCategories(
    List<({String category, bool enabled})> categories,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/cabinet/settings/act-categories',
      data: {
        'categories': [
          for (final c in categories)
            {'category': c.category, 'enabled': c.enabled},
        ],
      },
    );
    final data = (response.data?['data'] as List<dynamic>? ?? []);
    return data
        .map(
          (e) => (
            category: (e as Map<String, dynamic>)['category'] as String,
            enabled: e['enabled'] as bool,
          ),
        )
        .toList();
  }
}
