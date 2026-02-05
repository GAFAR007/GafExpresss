/// lib/app/features/home/presentation/business_product_api.dart
/// ------------------------------------------------------------
/// WHAT:
/// - BusinessProductApi handles business-scoped product CRUD.
///
/// WHY:
/// - Keeps /business/products networking out of UI widgets.
/// - Centralizes token handling and response parsing.
///
/// HOW:
/// - GET /business/products (list)
/// - POST /business/products (create)
/// - POST /business/products/ai-draft (AI draft)
/// - PATCH /business/products/:id (update)
/// - DELETE /business/products/:id (soft delete)
/// - PATCH /business/products/:id/restore (restore)
///
/// DEBUGGING:
/// - Logs request start/end for traceability.
/// ------------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'business_analytics_models.dart';
import 'product_ai_model.dart';
import 'product_model.dart';

class BusinessProductApi {
  final Dio _dio;

  BusinessProductApi({required Dio dio}) : _dio = dio;

  /// ------------------------------------------------------
  /// ANALYTICS SUMMARY
  /// ------------------------------------------------------
  Future<BusinessAnalyticsSummary> fetchAnalyticsSummary({
    required String token,
  }) async {
    // WHY: Business analytics requires auth for scope.
    if (token.trim().isEmpty) {
      AppDebug.log(
        "BUSINESS_PRODUCT_API",
        "fetchAnalyticsSummary() missing token",
      );
      throw Exception("Missing auth token");
    }

    AppDebug.log("BUSINESS_PRODUCT_API", "fetchAnalyticsSummary() start");

    final resp = await _dio.get(
      "/business/analytics/summary",
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final summaryMap = (data["summary"] ?? {}) as Map<String, dynamic>;
    final summary = BusinessAnalyticsSummary.fromJson(summaryMap);

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "fetchAnalyticsSummary() success",
      extra: {
        "totalProducts": summary.totalProducts,
        "totalOrders": summary.totalOrders,
      },
    );

    return summary;
  }

  /// ------------------------------------------------------
  /// LIST PRODUCTS
  /// ------------------------------------------------------
  Future<List<Product>> fetchProducts({
    required String token,
    int page = 1,
    int limit = 10,
    String? searchQuery,
    String? sort,
    bool? isActive,
  }) async {
    // WHY: Prevent unauthenticated calls to protected endpoints.
    if (token.trim().isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "fetchProducts() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "fetchProducts() start",
      extra: {
        "page": page,
        "limit": limit,
        "q": searchQuery?.trim(),
        "sort": sort?.trim(),
        "isActive": isActive,
      },
    );

    final queryParameters = <String, dynamic>{
      "page": page,
      "limit": limit,
    };

    final trimmedQuery = searchQuery?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      queryParameters["q"] = trimmedQuery;
    }

    final trimmedSort = sort?.trim();
    if (trimmedSort != null && trimmedSort.isNotEmpty) {
      queryParameters["sort"] = trimmedSort;
    }

    if (isActive != null) {
      queryParameters["isActive"] = isActive.toString();
    }

    final resp = await _dio.get(
      "/business/products",
      queryParameters: queryParameters,
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final rawList = (data["products"] ?? []) as List<dynamic>;

    final products = rawList
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "fetchProducts() success",
      extra: {"count": products.length},
    );

    return products;
  }

  /// ------------------------------------------------------
  /// AI PRODUCT DRAFT
  /// ------------------------------------------------------
  Future<ProductDraft> generateProductDraft({
    required String token,
    required String prompt,
    bool useReasoning = false,
  }) async {
    // WHY: Avoid unauthenticated AI draft calls.
    if (token.trim().isEmpty) {
      AppDebug.log(
        "BUSINESS_PRODUCT_API",
        "generateProductDraft() missing token",
      );
      throw Exception("Missing auth token");
    }

    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      AppDebug.log(
        "BUSINESS_PRODUCT_API",
        "generateProductDraft() missing prompt",
      );
      throw Exception("Prompt is required");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "generateProductDraft() start",
      extra: {
        "promptLength": trimmedPrompt.length,
        "useReasoning": useReasoning,
      },
    );

    final resp = await _dio.post(
      "/business/products/ai-draft",
      data: {
        "prompt": trimmedPrompt,
        "useReasoning": useReasoning,
      },
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final draftMap = (data["draft"] ?? {}) as Map<String, dynamic>;
    final draft = ProductDraft.fromJson(draftMap);

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "generateProductDraft() success",
      extra: {"hasName": draft.name.trim().isNotEmpty},
    );

    return draft;
  }

  /// ------------------------------------------------------
  /// GET PRODUCT BY ID
  /// ------------------------------------------------------
  Future<Product> fetchProductById({
    required String token,
    required String id,
  }) async {
    // WHY: Prevent unauthenticated reads of business data.
    if (token.trim().isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "fetchProductById() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "fetchProductById() start",
      extra: {"id": id},
    );

    final resp = await _dio.get(
      "/business/products/$id",
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final productMap = (data["product"] ?? {}) as Map<String, dynamic>;
    final product = Product.fromJson(productMap);

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "fetchProductById() success",
      extra: {"id": product.id},
    );

    return product;
  }

  /// ------------------------------------------------------
  /// CREATE PRODUCT
  /// ------------------------------------------------------
  Future<Product> createProduct({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "createProduct() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log("BUSINESS_PRODUCT_API", "createProduct() start");

    final resp = await _dio.post(
      "/business/products",
      data: payload,
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final productMap = (data["product"] ?? {}) as Map<String, dynamic>;
    final product = Product.fromJson(productMap);

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "createProduct() success",
      extra: {"id": product.id},
    );

    return product;
  }

  /// ------------------------------------------------------
  /// UPDATE PRODUCT
  /// ------------------------------------------------------
  Future<Product> updateProduct({
    required String token,
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "updateProduct() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "updateProduct() start",
      extra: {"id": id},
    );

    final resp = await _dio.patch(
      "/business/products/$id",
      data: payload,
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final productMap = (data["product"] ?? {}) as Map<String, dynamic>;
    final product = Product.fromJson(productMap);

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "updateProduct() success",
      extra: {"id": product.id},
    );

    return product;
  }

  /// ------------------------------------------------------
  /// SOFT DELETE PRODUCT
  /// ------------------------------------------------------
  Future<void> softDeleteProduct({
    required String token,
    required String id,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "softDeleteProduct() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "softDeleteProduct() start",
      extra: {"id": id},
    );

    await _dio.delete(
      "/business/products/$id",
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "softDeleteProduct() success",
      extra: {"id": id},
    );
  }

  /// ------------------------------------------------------
  /// RESTORE PRODUCT
  /// ------------------------------------------------------
  Future<void> restoreProduct({
    required String token,
    required String id,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "restoreProduct() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "restoreProduct() start",
      extra: {"id": id},
    );

    await _dio.patch(
      "/business/products/$id/restore",
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "restoreProduct() success",
      extra: {"id": id},
    );
  }

  /// ------------------------------------------------------
  /// UPLOAD PRODUCT IMAGE
  /// ------------------------------------------------------
  Future<Product> uploadProductImage({
    required String token,
    required String id,
    required List<int> bytes,
    required String filename,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "uploadProductImage() missing token");
      throw Exception("Missing auth token");
    }

    if (bytes.isEmpty) {
      AppDebug.log("BUSINESS_PRODUCT_API", "uploadProductImage() missing bytes");
      throw Exception("Missing image data");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "uploadProductImage() start",
      extra: {"id": id, "bytes": bytes.length, "filename": filename},
    );

    final formData = FormData.fromMap({
      "image": MultipartFile.fromBytes(bytes, filename: filename),
    });

    final resp = await _dio.post(
      "/business/products/$id/image",
      data: formData,
      options: Options(
        headers: {"Authorization": "Bearer $token"},
        contentType: "multipart/form-data",
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final productMap = (data["product"] ?? {}) as Map<String, dynamic>;
    final product = Product.fromJson(productMap);

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "uploadProductImage() success",
      extra: {"id": product.id},
    );

    return product;
  }

  /// ------------------------------------------------------
  /// DELETE PRODUCT IMAGE
  /// ------------------------------------------------------
  Future<Product> deleteProductImage({
    required String token,
    required String id,
    required String imageUrl,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log(
        "BUSINESS_PRODUCT_API",
        "deleteProductImage() missing token",
      );
      throw Exception("Missing auth token");
    }

    if (imageUrl.trim().isEmpty) {
      AppDebug.log(
        "BUSINESS_PRODUCT_API",
        "deleteProductImage() missing imageUrl",
      );
      throw Exception("Missing image URL");
    }

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "deleteProductImage() start",
      extra: {"id": id},
    );

    final resp = await _dio.delete(
      "/business/products/$id/image",
      data: {"imageUrl": imageUrl},
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final productMap = (data["product"] ?? {}) as Map<String, dynamic>;
    final product = Product.fromJson(productMap);

    AppDebug.log(
      "BUSINESS_PRODUCT_API",
      "deleteProductImage() success",
      extra: {"id": product.id},
    );

    return product;
  }
}
