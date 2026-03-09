import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/nutrition_log.dart';

/// Client for the Open Food Facts v2 JSON API.
///
/// Docs: https://wiki.openfoodfacts.org/API
/// All requests are anonymous — no API key required.
class NutritionService {
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2';
  static const _userAgent = 'BodyPress/1.0 (Flutter) - contact@governor-hq.com';

  final http.Client _client;

  NutritionService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() => _client.close();

  /// Look up a product by EAN / UPC barcode.
  ///
  /// Returns `null` when:
  /// - the barcode is not in the database,
  /// - the response can't be parsed, or
  /// - a network error occurs.
  Future<NutritionLog?> lookupBarcode(String barcode) async {
    final uri = Uri.parse('$_baseUrl/product/$barcode.json');

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          '[NutritionService] HTTP ${response.statusCode} for $barcode',
        );
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final status = body['status'] as int?;
      if (status != 1) {
        debugPrint('[NutritionService] Product not found: $barcode');
        return null;
      }

      final product = body['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      return _parseProduct(barcode, product);
    } catch (e) {
      debugPrint('[NutritionService] Error looking up $barcode: $e');
      return null;
    }
  }

  /// Search products by name / keyword (paginated).
  ///
  /// Useful for manual entry fallback if barcode isn't in the DB.
  Future<List<NutritionLog>> search(String query, {int page = 1}) async {
    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {
        'search_terms': query,
        'search_simple': '1',
        'json': '1',
        'page': page.toString(),
        'page_size': '10',
        'fields':
            'code,product_name,brands,nutriscore_grade,nova_group,'
            'nutriments,serving_size,image_front_small_url',
      },
    );

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final products = body['products'] as List?;
      if (products == null || products.isEmpty) return const [];

      return products
          .map((p) {
            final map = p as Map<String, dynamic>;
            final code = map['code'] as String? ?? '';
            if (code.isEmpty) return null;
            return _parseProduct(code, map);
          })
          .whereType<NutritionLog>()
          .toList();
    } catch (e) {
      debugPrint('[NutritionService] Search error: $e');
      return const [];
    }
  }

  // ── Internal parser ──────────────────────────────────────────────────────

  NutritionLog _parseProduct(String barcode, Map<String, dynamic> p) {
    final nutriments = p['nutriments'] as Map<String, dynamic>? ?? {};

    return NutritionLog(
      barcode: barcode,
      productName: _productName(p),
      brand: _firstBrand(p),
      nutriScore: (p['nutriscore_grade'] as String?)?.toLowerCase(),
      novaGroup: _parseInt(p['nova_group']),
      per100g: _parseFacts(nutriments, '100g'),
      servingSize: p['serving_size'] as String?,
      perServing: _parseFacts(nutriments, 'serving'),
      imageUrl:
          (p['image_front_small_url'] as String?) ??
          (p['image_url'] as String?),
      scannedAt: DateTime.now(),
    );
  }

  String _productName(Map<String, dynamic> p) {
    return (p['product_name'] as String?)?.trim().isNotEmpty == true
        ? p['product_name'] as String
        : (p['product_name_en'] as String?)?.trim().isNotEmpty == true
        ? p['product_name_en'] as String
        : 'Unknown product';
  }

  String? _firstBrand(Map<String, dynamic> p) {
    final raw = p['brands'] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.split(',').first.trim();
  }

  int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is num) return v.toInt();
    return null;
  }

  NutritionFacts? _parseFacts(Map<String, dynamic> n, String suffix) {
    double? val(String key) {
      final v = n['${key}_$suffix'];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final energy = val('energy-kcal');
    final fat = val('fat');
    final carbs = val('carbohydrates');
    final proteins = val('proteins');

    // If we got nothing at all, don't return an empty object.
    if (energy == null && fat == null && carbs == null && proteins == null) {
      return null;
    }

    return NutritionFacts(
      energyKcal: energy,
      fat: fat,
      saturatedFat: val('saturated-fat'),
      carbohydrates: carbs,
      sugars: val('sugars'),
      fiber: val('fiber'),
      proteins: proteins,
      salt: val('salt'),
      sodium: val('sodium'),
    );
  }
}
