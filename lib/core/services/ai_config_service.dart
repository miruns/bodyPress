import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/ai_provider_config.dart';
import 'local_db_service.dart';

/// Persistence key used in the settings table.
const _kSettingsKey = 'ai_provider_config';

/// Manages persisting and loading the active [AiProviderConfig].
///
/// Stored as a JSON blob in the app's settings table, so schema migrations
/// are never needed — new fields simply get their defaults on decode.
class AiConfigService {
  final LocalDbService _db;

  AiConfigService({required LocalDbService db}) : _db = db;

  /// Load the saved config, falling back to the built-in default.
  Future<AiProviderConfig> load() async {
    try {
      final raw = await _db.getSetting(_kSettingsKey);
      if (raw != null && raw.isNotEmpty) {
        return AiProviderConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('[AiConfigService] Failed to load config, using default: $e');
    }
    return AiProviderConfig.defaultProvider;
  }

  /// Persist a new config to disk.
  Future<void> save(AiProviderConfig config) async {
    await _db.setSetting(_kSettingsKey, jsonEncode(config.toJson()));
  }
}

/// Reactive state of the active AI provider configuration.
///
/// Read with `ref.watch(aiConfigProvider)`.
/// Modify via `ref.read(aiConfigProvider.notifier).update(newConfig)`.
class AiConfigNotifier extends StateNotifier<AiProviderConfig> {
  final AiConfigService _service;

  AiConfigNotifier(this._service) : super(AiProviderConfig.defaultProvider);

  /// Hydrate from disk — call once at startup.
  Future<void> init() async {
    state = await _service.load();
  }

  /// Apply and persist a new config. Downstream providers that depend on
  /// [aiConfigProvider] will automatically invalidate & rebuild [AiService].
  Future<void> update(AiProviderConfig config) async {
    final active = config.copyWith(isActive: true);
    await _service.save(active);
    state = active;
  }

  /// Reset to built-in default.
  Future<void> reset() async {
    await _service.save(AiProviderConfig.defaultProvider);
    state = AiProviderConfig.defaultProvider;
  }

  /// Test a configuration by sending a minimal chat completion.
  /// Returns `true` if the endpoint responds with HTTP 200.
  Future<bool> testConnection(AiProviderConfig config) async {
    final client = http.Client();
    try {
      final baseUrl = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseUrl/v1/chat/completions');
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (config.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${config.apiKey}';
      }

      final body = jsonEncode({
        'messages': [
          {'role': 'user', 'content': 'Say "ok" in one word.'},
        ],
        'max_tokens': 5,
        if (config.model.isNotEmpty) 'model': config.model,
        'stream': false,
      });

      final response = await client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[AiConfig] Connection test failed: $e');
      return false;
    } finally {
      client.close();
    }
  }
}
