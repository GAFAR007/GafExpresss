/// lib/app/features/home/presentation/address_autocomplete_api.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Client for backend address autocomplete + place details endpoints.
///
/// WHY:
/// - Keeps Google API key on the backend.
/// - Provides structured address suggestions for Settings + checkout.
///
/// HOW:
/// - Calls /auth/address/autocomplete and /auth/address/place-details.
/// - Returns typed suggestion models and UserAddress data.
/// -----------------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';

class AddressSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const AddressSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    return AddressSuggestion(
      placeId: (json["placeId"] ?? "").toString(),
      description: (json["description"] ?? "").toString(),
      mainText: (json["mainText"] ?? "").toString(),
      secondaryText: (json["secondaryText"] ?? "").toString(),
    );
  }
}

class AddressAutocompleteApi {
  final Dio _dio;

  AddressAutocompleteApi({required Dio dio}) : _dio = dio;

  Options _authOptions(String? token) {
    if (token == null || token.isEmpty) {
      AppDebug.log("ADDRESS_API", "Missing auth token");
      throw Exception("Missing auth token");
    }

    return Options(
      headers: {
        "Authorization": "Bearer $token",
      },
    );
  }

  Future<List<AddressSuggestion>> fetchSuggestions({
    required String? token,
    required String query,
  }) async {
    AppDebug.log(
      "ADDRESS_API",
      "fetchSuggestions() start",
      extra: {"length": query.length},
    );

    final resp = await _dio.get(
      "/auth/address/autocomplete",
      queryParameters: {"query": query},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final raw = (data["suggestions"] ?? []) as List<dynamic>;
    final suggestions = raw
        .map((item) => AddressSuggestion.fromJson(item as Map<String, dynamic>))
        .toList();

    AppDebug.log(
      "ADDRESS_API",
      "fetchSuggestions() success",
      extra: {"count": suggestions.length},
    );

    return suggestions;
  }

  Future<UserAddress> fetchPlaceDetails({
    required String? token,
    required String placeId,
  }) async {
    AppDebug.log(
      "ADDRESS_API",
      "fetchPlaceDetails() start",
      extra: {"hasId": placeId.isNotEmpty},
    );

    final resp = await _dio.get(
      "/auth/address/place-details",
      queryParameters: {"placeId": placeId},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final addressMap = (data["address"] ?? {}) as Map<String, dynamic>;
    final address = UserAddress.fromJson(addressMap);

    AppDebug.log("ADDRESS_API", "fetchPlaceDetails() success");

    return address;
  }
}
