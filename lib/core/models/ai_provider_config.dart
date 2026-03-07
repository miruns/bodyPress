import 'dart:convert';

/// Supported AI provider presets.
///
/// All use the **OpenAI-compatible** chat completions format, so adding a
/// provider is just a matter of changing [baseUrl] and [defaultModel].
///
/// [openRouter] is the recommended "plug everything" option — it proxies
/// 300+ models (OpenAI, Anthropic, Google, Meta, Mistral, …) behind a
/// single API key.
enum AiProviderType {
  /// BodyPress Cloud — the built-in gateway (default, no user config needed).
  bodyPressCloud('BodyPress Cloud'),

  /// OpenAI  — api.openai.com
  openAi('OpenAI'),

  /// OpenRouter  — openrouter.ai (aggregates hundreds of models)
  openRouter('OpenRouter'),

  /// Groq  — fast inference on open models (Llama, Mixtral)
  groq('Groq'),

  /// Mistral  — mistral.ai
  mistral('Mistral AI'),

  /// DeepSeek  — api.deepseek.com
  deepSeek('DeepSeek'),

  /// Together AI  — together.xyz
  togetherAi('Together AI'),

  /// Fireworks AI  — fireworks.ai
  fireworks('Fireworks AI'),

  /// Perplexity  — api.perplexity.ai
  perplexity('Perplexity'),

  /// Local  — any local OpenAI-compatible server (Ollama, LM Studio, etc.)
  local('Local (Ollama / LM Studio)'),

  /// Fully user-defined endpoint.
  custom('Custom');

  const AiProviderType(this.displayName);
  final String displayName;
}

/// Immutable configuration for a single AI provider endpoint.
class AiProviderConfig {
  final AiProviderType type;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool isActive;

  const AiProviderConfig({
    required this.type,
    required this.baseUrl,
    this.apiKey = '',
    this.model = '',
    this.isActive = false,
  });

  // ── Presets ───────────────────────────────────────────────────────────────

  /// BodyPress Cloud — the existing default. No key needed from user.
  static const defaultProvider = AiProviderConfig(
    type: AiProviderType.bodyPressCloud,
    baseUrl: 'https://ai.governor-hq.com',
    isActive: true,
  );

  /// Pre-filled templates for each provider type.
  static AiProviderConfig preset(AiProviderType type) {
    switch (type) {
      case AiProviderType.bodyPressCloud:
        return defaultProvider;
      case AiProviderType.openAi:
        return const AiProviderConfig(
          type: AiProviderType.openAi,
          baseUrl: 'https://api.openai.com',
          model: 'gpt-4o-mini',
        );
      case AiProviderType.openRouter:
        return const AiProviderConfig(
          type: AiProviderType.openRouter,
          baseUrl: 'https://openrouter.ai/api',
          model: 'openai/gpt-4o-mini',
        );
      case AiProviderType.groq:
        return const AiProviderConfig(
          type: AiProviderType.groq,
          baseUrl: 'https://api.groq.com/openai',
          model: 'llama-3.3-70b-versatile',
        );
      case AiProviderType.mistral:
        return const AiProviderConfig(
          type: AiProviderType.mistral,
          baseUrl: 'https://api.mistral.ai',
          model: 'mistral-small-latest',
        );
      case AiProviderType.deepSeek:
        return const AiProviderConfig(
          type: AiProviderType.deepSeek,
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-chat',
        );
      case AiProviderType.togetherAi:
        return const AiProviderConfig(
          type: AiProviderType.togetherAi,
          baseUrl: 'https://api.together.xyz',
          model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
        );
      case AiProviderType.fireworks:
        return const AiProviderConfig(
          type: AiProviderType.fireworks,
          baseUrl: 'https://api.fireworks.ai/inference',
          model: 'accounts/fireworks/models/llama-v3p3-70b-instruct',
        );
      case AiProviderType.perplexity:
        return const AiProviderConfig(
          type: AiProviderType.perplexity,
          baseUrl: 'https://api.perplexity.ai',
          model: 'sonar',
        );
      case AiProviderType.local:
        return const AiProviderConfig(
          type: AiProviderType.local,
          baseUrl: 'http://localhost:11434/v1',
          model: 'llama3.2',
        );
      case AiProviderType.custom:
        return const AiProviderConfig(type: AiProviderType.custom, baseUrl: '');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Whether the user must supply an API key for this provider.
  bool get requiresApiKey => type != AiProviderType.bodyPressCloud;

  /// Whether this is the built-in BodyPress Cloud gateway.
  bool get isDefault => type == AiProviderType.bodyPressCloud;

  /// Whether the base URL can be freely edited.
  bool get hasEditableUrl =>
      type == AiProviderType.local || type == AiProviderType.custom;

  /// Short description shown as a subtitle in the settings UI.
  String get subtitle {
    switch (type) {
      case AiProviderType.bodyPressCloud:
        return 'Built-in — no API key needed';
      case AiProviderType.openAi:
        return 'GPT-4o, GPT-4o-mini, o1, o3-mini …';
      case AiProviderType.openRouter:
        return '300+ models — one API key for all providers';
      case AiProviderType.groq:
        return 'Ultra-fast Llama & Mixtral inference';
      case AiProviderType.mistral:
        return 'Mistral Small, Medium, Large';
      case AiProviderType.deepSeek:
        return 'DeepSeek V3 & R1 reasoning models';
      case AiProviderType.togetherAi:
        return 'Open-source models at scale';
      case AiProviderType.fireworks:
        return 'Fast open-model inference';
      case AiProviderType.perplexity:
        return 'Search-augmented AI';
      case AiProviderType.local:
        return 'Ollama, LM Studio, or any local server';
      case AiProviderType.custom:
        return 'Any OpenAI-compatible endpoint';
    }
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'isActive': isActive,
  };

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'bodyPressCloud';
    final type = AiProviderType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => AiProviderType.bodyPressCloud,
    );
    return AiProviderConfig(
      type: type,
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  factory AiProviderConfig.decode(String json) =>
      AiProviderConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);

  AiProviderConfig copyWith({
    AiProviderType? type,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? isActive,
  }) {
    return AiProviderConfig(
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiProviderConfig &&
          type == other.type &&
          baseUrl == other.baseUrl &&
          apiKey == other.apiKey &&
          model == other.model &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(type, baseUrl, apiKey, model, isActive);
}
