import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/reviews/review_dto.dart';

@injectable
class ReviewApi {
  final Dio _dio;

  ReviewApi(ApiClient client) : _dio = client.dio;

  Future<List<ReviewDto>> getProviderReviews(String providerId) async {
    final response = await _dio.get<List<dynamic>>(
      '/providers/$providerId/reviews',
    );
    return (response.data!)
        .map((e) => ReviewDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ReviewDto> submitReview({
    required String appointmentId,
    required int rating,
    String? comment,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/reviews',
      data: {
        'appointment_id': appointmentId,
        'rating': rating,
        if (comment != null) 'comment': comment,
      },
      options: Options(
        headers: {'Idempotency-Key': idempotencyKey},
      ),
    );
    return ReviewDto.fromJson(response.data!);
  }
}
