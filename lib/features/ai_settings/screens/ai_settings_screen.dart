import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Screen that lets users configure which AI provider powers BodyPress.
///
/// Accessible from the "More" sheet → "AI Services".
/// The default BodyPress Cloud provider works out of the box. Users can
/// switch to any OpenAI-compatible endpoint (OpenAI, OpenRouter, Groq,
/// Mistral, DeepSeek, Together AI, Fireworks, Perplexity, Ollama, custom).
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late AiProviderConfig _draft;
  bool _isTesting = false;
  bool? _testResult;
  bool _obscureKey = true;

  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = ref.read(aiConfigProvider);
    _syncControllers();
  }

  void _syncControllers() {
    _apiKeyCtrl.text = _draft.apiKey;
    _modelCtrl.text = _draft.model;
    _urlCtrl.text = _draft.baseUrl;
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _selectProvider(AiProviderType type) {
    setState(() {
      _draft = AiProviderConfig.preset(type);
      _testResult = null;
      _syncControllers();
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final config = _buildConfig();
    final ok = await ref.read(aiConfigProvider.notifier).testConnection(config);
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = ok;
      });
    }
  }

  Future<void> _save() async {
    final config = _buildConfig();
    await ref.read(aiConfigProvider.notifier).update(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'AI provider set to ${config.type.displayName}',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.seaGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefault() async {
    await ref.read(aiConfigProvider.notifier).reset();
    if (mounted) {
      setState(() {
        _draft = AiProviderConfig.defaultProvider;
        _testResult = null;
        _syncControllers();
      });
    }
  }

  AiProviderConfig _buildConfig() {
    return _draft.copyWith(
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      baseUrl: _urlCtrl.text.trim(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentConfig = ref.watch(aiConfigProvider);

    return Scaffold(
      backgroundColor: AppTheme.midnight,
      appBar: AppBar(
        backgroundColor: AppTheme.midnight,
        foregroundColor: AppTheme.moonbeam,
        title: const Text('AI Services'),
        elevation: 0,
        actions: [
          if (!_draft.isDefault)
            TextButton(
              onPressed: _resetToDefault,
              child: Text(
                'Reset',
                style: TextStyle(
                  color: AppTheme.fog,
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // ── Active provider banner ─────────────────────────────────────
          _ActiveBanner(config: currentConfig),
          const SizedBox(height: 24),

          // ── Provider picker ────────────────────────────────────────────
          _SectionHeader('Choose Provider'),
          const SizedBox(height: 8),
          ...AiProviderType.values.map(
            (type) => _ProviderTile(
              type: type,
              isSelected: _draft.type == type,
              isCurrent: currentConfig.type == type,
              onTap: () => _selectProvider(type),
            ),
          ),
          const SizedBox(height: 24),

          // ── Configuration fields ───────────────────────────────────────
          if (!_draft.isDefault) ...[
            _SectionHeader('Configuration'),
            const SizedBox(height: 8),

            // API Key
            if (_draft.requiresApiKey) ...[
              _FieldLabel('API Key'),
              const SizedBox(height: 6),
              _buildApiKeyField(),
              const SizedBox(height: 16),
            ],

            // Model
            _FieldLabel('Model'),
            const SizedBox(height: 6),
            _buildTextField(controller: _modelCtrl, hint: 'e.g. gpt-4o-mini'),
            const SizedBox(height: 16),

            // Base URL (editable for local / custom)
            if (_draft.hasEditableUrl) ...[
              _FieldLabel('Base URL'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _urlCtrl,
                hint: 'https://api.example.com',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
            ] else ...[
              _FieldLabel('Endpoint'),
              const SizedBox(height: 4),
              Text(
                _draft.baseUrl,
                style: TextStyle(
                  color: AppTheme.fog,
                  fontSize: 13,
                  fontFamily: 'DM Sans',
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Test & Save ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: _isTesting ? 'Testing…' : 'Test Connection',
                    icon: _testResult == null
                        ? Icons.wifi_tethering_rounded
                        : _testResult!
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: _testResult == null
                        ? AppTheme.starlight
                        : _testResult!
                        ? AppTheme.seaGreen
                        : AppTheme.crimson,
                    onTap: _isTesting ? null : _testConnection,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Save & Activate',
                    icon: Icons.save_rounded,
                    color: AppTheme.glow,
                    filled: true,
                    onTap: _save,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // ── Save default (if switching back to BodyPress Cloud) ────────
          if (_draft.isDefault &&
              currentConfig.type != AiProviderType.bodyPressCloud) ...[
            const SizedBox(height: 8),
            _ActionButton(
              label: 'Switch back to BodyPress Cloud',
              icon: Icons.restore_rounded,
              color: AppTheme.glow,
              filled: true,
              onTap: _save,
            ),
            const SizedBox(height: 24),
          ],

          // ── Info box ───────────────────────────────────────────────────
          _InfoBox(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildApiKeyField() {
    return TextField(
      controller: _apiKeyCtrl,
      obscureText: _obscureKey,
      style: const TextStyle(
        color: AppTheme.moonbeam,
        fontFamily: 'DM Sans',
        fontSize: 14,
      ),
      decoration: _fieldDecoration(
        hint: 'sk-…',
        suffixIcon: IconButton(
          icon: Icon(
            _obscureKey
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: AppTheme.fog,
            size: 20,
          ),
          onPressed: () => setState(() => _obscureKey = !_obscureKey),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: AppTheme.moonbeam,
        fontFamily: 'DM Sans',
        fontSize: 14,
      ),
      decoration: _fieldDecoration(hint: hint),
    );
  }

  InputDecoration _fieldDecoration({required String hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppTheme.fog.withValues(alpha: 0.50)),
      filled: true,
      fillColor: AppTheme.deepSea,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.shimmer.withValues(alpha: 0.40)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.shimmer.withValues(alpha: 0.40)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.glow),
      ),
      suffixIcon: suffixIcon,
    );
  }
}

// ─── Active provider banner ──────────────────────────────────────────────────

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.config});
  final AiProviderConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.tidePool, AppTheme.deepSea],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.glow.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.glow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.glow,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active: ${config.type.displayName}',
                  style: const TextStyle(
                    color: AppTheme.moonbeam,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    fontFamily: 'DM Sans',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  config.model.isNotEmpty ? config.model : 'Default model',
                  style: TextStyle(
                    color: AppTheme.fog,
                    fontSize: 12,
                    fontFamily: 'DM Sans',
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.seaGreen,
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppTheme.fog,
        letterSpacing: 2.0,
        fontFamily: 'DM Sans',
      ),
    );
  }
}

// ─── Field label ─────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppTheme.moonbeam,
        fontFamily: 'DM Sans',
      ),
    );
  }
}

// ─── Provider tile ───────────────────────────────────────────────────────────

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.type,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
  });

  final AiProviderType type;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;

  IconData get _icon {
    switch (type) {
      case AiProviderType.bodyPressCloud:
        return Icons.cloud_rounded;
      case AiProviderType.openAi:
        return Icons.auto_awesome_rounded;
      case AiProviderType.openRouter:
        return Icons.hub_rounded;
      case AiProviderType.groq:
        return Icons.bolt_rounded;
      case AiProviderType.mistral:
        return Icons.air_rounded;
      case AiProviderType.deepSeek:
        return Icons.psychology_rounded;
      case AiProviderType.togetherAi:
        return Icons.groups_rounded;
      case AiProviderType.fireworks:
        return Icons.local_fire_department_rounded;
      case AiProviderType.perplexity:
        return Icons.search_rounded;
      case AiProviderType.local:
        return Icons.computer_rounded;
      case AiProviderType.custom:
        return Icons.settings_ethernet_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = AiProviderConfig.preset(type);
    final borderColor = isSelected
        ? AppTheme.glow.withValues(alpha: 0.60)
        : AppTheme.shimmer.withValues(alpha: 0.25);
    final bgColor = isSelected
        ? AppTheme.tidePool.withValues(alpha: 0.80)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(
                  _icon,
                  size: 20,
                  color: isSelected ? AppTheme.glow : AppTheme.fog,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.displayName,
                        style: TextStyle(
                          color: isSelected
                              ? AppTheme.moonbeam
                              : AppTheme.moonbeam.withValues(alpha: 0.85),
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontSize: 14,
                          fontFamily: 'DM Sans',
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        preset.subtitle,
                        style: TextStyle(
                          color: AppTheme.fog.withValues(alpha: 0.80),
                          fontSize: 11,
                          fontFamily: 'DM Sans',
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.seaGreen,
                    size: 18,
                  ),
                if (isSelected && !isCurrent)
                  Icon(
                    Icons.radio_button_checked_rounded,
                    color: AppTheme.glow,
                    size: 18,
                  ),
                if (!isSelected && !isCurrent)
                  Icon(
                    Icons.radio_button_unchecked_rounded,
                    color: AppTheme.shimmer.withValues(alpha: 0.50),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Action button ───────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.filled = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: filled ? 0.40 : 0.30),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFamily: 'DM Sans',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Info box ────────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.deepSea,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.shimmer.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppTheme.starlight.withValues(alpha: 0.70),
              ),
              const SizedBox(width: 8),
              Text(
                'How it works',
                style: TextStyle(
                  color: AppTheme.starlight,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFamily: 'DM Sans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoLine(
            'All providers use the OpenAI-compatible chat completions format.',
          ),
          const SizedBox(height: 6),
          _infoLine(
            'OpenRouter is recommended if you want access to 300+ models '
            '(OpenAI, Anthropic, Google, Meta, Mistral…) with a single API key.',
          ),
          const SizedBox(height: 6),
          _infoLine(
            'For local inference, install Ollama or LM Studio and point '
            'the base URL to your local server.',
          ),
          const SizedBox(height: 6),
          _infoLine(
            'Your API key is stored locally on this device and never '
            'sent to BodyPress Cloud.',
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.fog.withValues(alpha: 0.50),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTheme.fog,
              fontSize: 12,
              height: 1.4,
              fontFamily: 'DM Sans',
            ),
          ),
        ),
      ],
    );
  }
}
