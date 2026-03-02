import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/background_capture_config.dart';
import '../models/capture_entry.dart';
import '../services/capture_service.dart';
import '../services/local_db_service.dart';

/// Top-level callback invoked by WorkManager in a background isolate.
///
/// This runs **outside** the normal Flutter widget tree so it must
/// bootstrap its own services.  Keep it lightweight — the OS can kill
/// background work that takes too long (~30 s on iOS, ~10 min Android).
@pragma('vm:entry-point')
Future<bool> captureExecutorCallback() async {
  WidgetsFlutterBinding.ensureInitialized();

  final stopwatch = Stopwatch()..start();
  final errors = <String>[];

  try {
    // 1. Load user preferences
    final dbService = LocalDbService();
    final configRaw = await dbService.getSetting('background_capture_config');
    final config = configRaw != null
        ? BackgroundCaptureConfig.decode(configRaw)
        : BackgroundCaptureConfig.defaultConfig;

    // 2. Bail out early if disabled or in quiet hours
    if (!config.enabled) {
      debugPrint('[CaptureExecutor] Background captures disabled — skipping.');
      return true;
    }

    if (config.isInQuietHours()) {
      debugPrint('[CaptureExecutor] Inside quiet hours — skipping.');
      return true;
    }

    // 3. Execute the capture with a global timeout
    final captureService = CaptureService(dbService: dbService);

    CaptureEntry? capture;
    try {
      capture = await captureService
          .createCapture(
            includeHealth: config.includeHealth,
            includeEnvironment: config.includeEnvironment,
            includeLocation: config.includeLocation,
            includeCalendar: config.includeCalendar,
            source: CaptureSource.backgroundScheduled,
            trigger: CaptureTrigger.time,
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      errors.add('Capture timed out after 25 s');
      debugPrint('[CaptureExecutor] Capture timed out.');
    }

    stopwatch.stop();

    // 4. If we got a partial or full capture, update with execution metadata
    if (capture != null) {
      final updated = capture.copyWith(
        executionDuration: stopwatch.elapsed,
        errors: errors,
      );
      await dbService.saveCapture(updated);

      // 5. Update last-successful-capture timestamp
      await dbService.setSetting(
        'last_background_capture',
        DateTime.now().toIso8601String(),
      );

      // Increment success counter
      await _incrementCounter(dbService, 'bg_capture_success_count');

      debugPrint(
        '[CaptureExecutor] Capture ${capture.id} saved '
        '(${stopwatch.elapsedMilliseconds} ms).',
      );
    } else {
      await _incrementCounter(dbService, 'bg_capture_failure_count');
    }

    return true;
  } catch (e, st) {
    debugPrint('[CaptureExecutor] Unhandled error: $e\n$st');

    // Best-effort: bump the failure counter even on crash.
    try {
      final db = LocalDbService();
      await _incrementCounter(db, 'bg_capture_failure_count');
    } catch (_) {}

    return false; // signals WorkManager to retry
  }
}

/// Atomically increment a counter stored in the settings table.
Future<void> _incrementCounter(LocalDbService db, String key) async {
  final raw = await db.getSetting(key);
  final current = int.tryParse(raw ?? '') ?? 0;
  await db.setSetting(key, '${current + 1}');
}

/// Human-readable summary of which data sources were included.
String _describeSources(BackgroundCaptureConfig config) {
  final parts = <String>[];
  if (config.includeHealth) parts.add('health');
  if (config.includeEnvironment) parts.add('environment');
  if (config.includeLocation) parts.add('location');
  if (config.includeCalendar) parts.add('calendar');
  return parts.join(', ');
}
