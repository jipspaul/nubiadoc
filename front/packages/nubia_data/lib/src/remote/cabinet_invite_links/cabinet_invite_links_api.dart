import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_invite_links/cabinet_invite_link_dto.dart';

class CabinetInviteLinksApi {
  final Dio _dio;

  CabinetInviteLinksApi(ApiClient client) : _dio = client.dio;

  /// POST /cabinet/invite-links (#7148) — admin uniquement.
  Future<CabinetInviteLinkDto> create(String role) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/invite-links',
      data: {'role': role},
    );
    return CabinetInviteLinkDto.fromJson(response.data!);
  }
}
