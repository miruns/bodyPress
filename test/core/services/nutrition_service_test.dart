import 'dart:convert';

import 'package:bodypress_flutter/core/services/nutrition_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('NutritionService — unit (mocked HTTP)', () {
    test('lookupBarcode parses a valid Open Food Facts response', () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://world.openfoodfacts.org/api/v2/product/3017620422003.json',
        );
        return http.Response(
          jsonEncode({
            'status': 1,
            'product': {
              'product_name': 'Nutella',
              'brands': 'Ferrero',
              'nutriscore_grade': 'e',
              'nova_group': 4,
              'serving_size': '15 g',
              'nutriments': {
                'energy-kcal_100g': 539,
                'fat_100g': 30.9,
                'saturated-fat_100g': 10.6,
                'carbohydrates_100g': 57.5,
                'sugars_100g': 56.3,
                'fiber_100g': 0.0,
                'proteins_100g': 6.3,
                'salt_100g': 0.107,
                'energy-kcal_serving': 80.85,
                'fat_serving': 4.64,
                'carbohydrates_serving': 8.63,
                'sugars_serving': 8.45,
                'proteins_serving': 0.945,
                'salt_serving': 0.016,
              },
              'image_front_small_url': 'https://example.com/nutella.jpg',
            },
          }),
          200,
        );
      });

      final svc = NutritionService(client: mockClient);
      final result = await svc.lookupBarcode('3017620422003');

      expect(result, isNotNull, reason: 'Expected a NutritionLog');
      expect(result!.barcode, '3017620422003');
      expect(result.productName, 'Nutella');
      expect(result.brand, 'Ferrero');
      expect(result.nutriScore, 'e');
      expect(result.novaGroup, 4);
      expect(result.per100g, isNotNull);
      expect(result.per100g!.energyKcal, 539);
      expect(result.per100g!.sugars, 56.3);
      expect(result.per100g!.proteins, 6.3);
      expect(result.perServing, isNotNull);
      expect(result.perServing!.energyKcal, 80.85);
      expect(result.imageUrl, 'https://example.com/nutella.jpg');
    });

    test(
      'lookupBarcode returns null when product not found (status 0)',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'status': 0, 'status_verbose': 'product not found'}),
            200,
          );
        });

        final svc = NutritionService(client: mockClient);
        final result = await svc.lookupBarcode('0000000000000');
        expect(result, isNull);
      },
    );

    test('lookupBarcode returns null on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final svc = NutritionService(client: mockClient);
      final result = await svc.lookupBarcode('3017620422003');
      expect(result, isNull);
    });

    test('lookupBarcode returns null on network exception', () async {
      final mockClient = MockClient((request) async {
        throw Exception('No internet');
      });

      final svc = NutritionService(client: mockClient);
      final result = await svc.lookupBarcode('3017620422003');
      expect(result, isNull);
    });

    test('search returns a list of parsed products', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v2/search');
        return http.Response(
          jsonEncode({
            'products': [
              {
                'code': '1234567890',
                'product_name': 'Test Product',
                'brands': 'Test Brand',
                'nutriscore_grade': 'b',
                'nova_group': 2,
                'nutriments': {
                  'energy-kcal_100g': 250,
                  'proteins_100g': 10,
                  'carbohydrates_100g': 30,
                  'fat_100g': 8,
                },
              },
            ],
          }),
          200,
        );
      });

      final svc = NutritionService(client: mockClient);
      final results = await svc.search('test');
      expect(results, hasLength(1));
      expect(results.first.productName, 'Test Product');
      expect(results.first.per100g!.energyKcal, 250);
    });
  });

  group('NutritionService — live API integration', () {
    // These tests hit the real Open Food Facts API.
    // They validate that the API contract hasn't changed.
    // Skip in CI with: flutter test --tags "!integration"

    test('lookupBarcode for Nutella (3017620422003) returns data', () async {
      final svc = NutritionService();
      final result = await svc.lookupBarcode('3017620422003');

      print('\n===== LIVE API RESULT =====');
      if (result == null) {
        print('RESULT: null — API returned no data!');
      } else {
        print('Product:    ${result.productName}');
        print('Brand:      ${result.brand}');
        print('NutriScore: ${result.nutriScore}');
        print('NOVA:       ${result.novaGroup}');
        print('Per 100g:   ${result.per100g?.energyKcal} kcal');
        print('  Fat:      ${result.per100g?.fat} g');
        print('  Carbs:    ${result.per100g?.carbohydrates} g');
        print('  Sugar:    ${result.per100g?.sugars} g');
        print('  Protein:  ${result.per100g?.proteins} g');
        print('  Salt:     ${result.per100g?.salt} g');
        print('Serving:    ${result.servingSize}');
        print('Per serv:   ${result.perServing?.energyKcal} kcal');
        print('Image:      ${result.imageUrl}');
      }
      print('===========================\n');

      expect(result, isNotNull, reason: 'Nutella should be in Open Food Facts');
      expect(result!.productName.toLowerCase(), contains('nutella'));
      expect(result.per100g, isNotNull);
      expect(result.per100g!.energyKcal, isNotNull);
      expect(result.per100g!.energyKcal!, greaterThan(0));

      svc.dispose();
    });

    test('lookupBarcode for Coca-Cola (5449000000996) returns data', () async {
      final svc = NutritionService();
      final result = await svc.lookupBarcode('5449000000996');

      print('\n===== LIVE API RESULT =====');
      if (result == null) {
        print('RESULT: null — API returned no data!');
      } else {
        print('Product:    ${result.productName}');
        print('Brand:      ${result.brand}');
        print('NutriScore: ${result.nutriScore}');
        print('NOVA:       ${result.novaGroup}');
        print('Per 100g:   ${result.per100g?.energyKcal} kcal');
        print('  Sugar:    ${result.per100g?.sugars} g');
      }
      print('===========================\n');

      expect(
        result,
        isNotNull,
        reason: 'Coca-Cola should be in Open Food Facts',
      );
      expect(result!.per100g, isNotNull);

      svc.dispose();
    });

    test('lookupBarcode for unknown barcode returns null', () async {
      final svc = NutritionService();
      final result = await svc.lookupBarcode('0000000000001');

      print('\n===== LIVE API RESULT =====');
      print(
        'Unknown barcode → result is ${result == null ? "null ✓" : "NOT null ✗"}',
      );
      print('===========================\n');

      expect(result, isNull);

      svc.dispose();
    });

    test('search for "nutella" returns results', () async {
      final svc = NutritionService();
      final results = await svc.search('nutella');

      print('\n===== LIVE SEARCH RESULTS =====');
      print('Found ${results.length} products');
      for (final r in results.take(3)) {
        print('  - ${r.productName} (${r.brand}) [${r.barcode}]');
      }
      print('===============================\n');

      expect(results, isNotEmpty);

      svc.dispose();
    });
  });
}
