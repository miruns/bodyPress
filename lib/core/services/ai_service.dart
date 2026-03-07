import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/ai_models.dart';
import '../models/ai_provider_config.dart';

/// Service for interacting with any OpenAI-compatible LLM gateway.
///
/// When no [AiProviderConfig] is supplied the service falls back to the
/// built-in BodyPress Cloud gateway at `ai.governor-hq.com`, preserving
/// full backward compatibility.
///
/// Example usage:
/// ```dart
/// final service = AiService();
/// final response = await service.chatCompletion([
///   ChatMessage.user('Summarize this health data...'),
/// ]);
/// print(response.content);
/// ```
class AiService {
  /// Default gateway when no config override is provided.
  static const String _defaultBaseUrl = 'https://ai.governor-hq.com';

  /// HTTP status codes that are transient and safe to retry.
  static const _retryableStatusCodes = {429, 503, 529};

  /// Maximum number of attempts (1 original + 2 retries).
  static const _maxAttempts = 3;

  /// API key resolved in order:
  ///  1. Explicit config from AI Settings screen
  ///  2. Compile-time `--dart-define=AI_API_KEY=...` (CI builds)
  ///  3. Runtime `.env` file loaded by flutter_dotenv (local dev)
  static String get _envApiKey {
    const compiled = String.fromEnvironment('AI_API_KEY');
    if (compiled.isNotEmpty) return compiled;
    return dotenv.env['AI_API_KEY'] ?? '';
  }

  final http.Client _client;
  final AiProviderConfig? _config;

  /// The effective base URL: user-configured or default gateway.
  String get _baseUrl {
    final url = _config?.baseUrl ?? '';
    return url.isNotEmpty
        ? url.replaceAll(RegExp(r'/+$'), '')
        : _defaultBaseUrl;
  }

  /// The effective API key: user-configured key, or env/compile-time fallback.
  String get _apiKey {
    final configKey = _config?.apiKey ?? '';
    return configKey.isNotEmpty ? configKey : _envApiKey;
  }

  /// The effective model name, or `null` to let the gateway pick.
  String? get _model {
    final m = _config?.model ?? '';
    return m.isNotEmpty ? m : null;
  }

  /// The active provider type for debug / logging.
  AiProviderType get providerType =>
      _config?.type ?? AiProviderType.bodyPressCloud;

  AiService({http.Client? client, AiProviderConfig? config})
    : _client = client ?? http.Client(),
      _config = config;

  /// Send a chat completion request with the given messages.
  ///
  /// Automatically retries up to [_maxAttempts] times with exponential backoff
  /// when the server responds with a transient error (429 / 503 / 529).
  ///
  /// Returns the full [ChatCompletionResponse] from the API.
  /// Throws [AiServiceException] on failure.
  Future<ChatCompletionResponse> chatCompletion(
    List<ChatMessage> messages, {
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final request = ChatCompletionRequest(
      messages: messages,
      model: model ?? _model,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: false,
    );

    AiServiceException? lastException;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await _client
            .post(
              Uri.parse('$_baseUrl/v1/chat/completions'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_apiKey',
              },
              body: jsonEncode(request.toJson()),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return ChatCompletionResponse.fromJson(data);
        }

        // Try to extract error message from response body.
        String errorMsg = 'Request failed';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMsg = errorData['error']?['message'] ?? errorMsg;
        } catch (_) {
          errorMsg = response.body.isNotEmpty
              ? response.body
              : 'HTTP ${response.statusCode}';
        }

        lastException = AiServiceException(
          errorMsg,
          statusCode: response.statusCode,
        );

        if (!_retryableStatusCodes.contains(response.statusCode)) {
          // Non-retryable error (e.g. 401, 400) — fail immediately.
          throw lastException;
        }

        // Retryable — wait before next attempt (1 s, 2 s, …).
        if (attempt < _maxAttempts) {
          final delay = Duration(seconds: attempt);
          debugPrint(
            '[AiService] HTTP ${response.statusCode} on attempt $attempt/$_maxAttempts — '
            'retrying in ${delay.inSeconds}s…',
          );
          await Future<void>.delayed(delay);
        }
      } on TimeoutException {
        lastException = const AiServiceException('Request timed out');
        if (attempt < _maxAttempts) {
          final delay = Duration(seconds: attempt);
          debugPrint(
            '[AiService] Timeout on attempt $attempt/$_maxAttempts — '
            'retrying in ${delay.inSeconds}s…',
          );
          await Future<void>.delayed(delay);
        }
      } on http.ClientException catch (e) {
        throw AiServiceException(
          'Network error: ${e.message}',
          originalError: e,
        );
      } catch (e) {
        if (e is AiServiceException) rethrow;
        throw AiServiceException('Unexpected error: $e', originalError: e);
      }
    }

    throw lastException ?? const AiServiceException('Request failed');
  }

  /// Simplified method to get a quick AI response from a single user prompt.
  ///
  /// Optionally include a system prompt to set behavior/context.
  ///
  /// Example:
  /// ```dart
  /// final answer = await service.ask(
  ///   'What are the health benefits of walking 10k steps?',
  ///   systemPrompt: 'You are a fitness expert.',
  /// );
  /// print(answer);
  /// ```
  Future<String> ask(
    String userPrompt, {
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
  }) async {
    final messages = <ChatMessage>[
      if (systemPrompt != null) ChatMessage.system(systemPrompt),
      ChatMessage.user(userPrompt),
    ];

    final response = await chatCompletion(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    return response.content;
  }

  /// Check if the AI service is available.
  ///
  /// Makes a lightweight request to the /health endpoint.
  /// Returns `true` if the service is reachable, `false` otherwise.
  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Clean up resources.
  void dispose() {
    _client.close();
  }
}
