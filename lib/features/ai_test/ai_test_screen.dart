import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ai_models.dart';
import '../../core/services/service_providers.dart';

/// Simple test screen to verify AI service is working.
///
/// Add this to your router to test:
/// ```dart
/// GoRoute(
///   path: '/ai-test',
///   builder: (context, state) => const AiTestScreen(),
/// ),
/// ```
class AiTestScreen extends ConsumerStatefulWidget {
  const AiTestScreen({super.key});

  @override
  ConsumerState<AiTestScreen> createState() => _AiTestScreenState();
}

class _AiTestScreenState extends ConsumerState<AiTestScreen> {
  final _controller = TextEditingController();
  String _response = '';
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _response = '';
    });

    try {
      final ai = ref.read(aiServiceProvider);
      final response = await ai.ask(prompt);

      setState(() {
        _response = response;
        _isLoading = false;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = 'AI Error: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unexpected error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _checkHealth() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _response = '';
    });

    try {
      final ai = ref.read(aiServiceProvider);
      final isHealthy = await ai.checkHealth();

      setState(() {
        _response = isHealthy
            ? '✓ AI service is available and healthy'
            : '✗ AI service is not responding';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Health check failed: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Service Test')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Health check button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _checkHealth,
              icon: const Icon(Icons.health_and_safety),
              label: const Text('Check AI Health'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Prompt input
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Ask AI a question',
                hintText: 'e.g., What are the benefits of daily exercise?',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),

            // Send button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _sendMessage,
              icon: const Icon(Icons.send),
              label: const Text('Send'),
            ),
            const SizedBox(height: 24),

            // Loading indicator
            if (_isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Waiting for AI response...'),
                  ],
                ),
              ),

            // Error display
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),

            // Response display
            if (_response.isNotEmpty && !_isLoading)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Response:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(_response),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
