import 'package:bodypress_flutter/core/models/background_capture_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ─── Defaults ─────────────────────────────────────────────────────────────

  group('BackgroundCaptureConfig defaults', () {
    test('defaultConfig has expected values', () {
      const c = BackgroundCaptureConfig.defaultConfig;
      expect(c.enabled, true);
      expect(c.interval, const Duration(minutes: 30));
      expect(c.includeHealth, true);
      expect(c.includeEnvironment, true);
      expect(c.includeLocation, true);
      expect(c.includeCalendar, true);
      expect(c.quietHoursStartHour, 22);
      expect(c.quietHoursStartMinute, 0);
      expect(c.quietHoursEndHour, 7);
      expect(c.quietHoursEndMinute, 0);
      expect(c.batteryOptimization, true);
    });
  });

  // ─── Serialisation ────────────────────────────────────────────────────────

  group('serialisation', () {
    test('toJson / fromJson round-trip', () {
      const original = BackgroundCaptureConfig(
        enabled: true,
        interval: Duration(hours: 2),
        includeHealth: false,
        includeEnvironment: true,
        includeLocation: false,
        includeCalendar: true,
        quietHoursStartHour: 23,
        quietHoursStartMinute: 30,
        quietHoursEndHour: 6,
        quietHoursEndMinute: 45,
        batteryOptimization: false,
      );
      final json = original.toJson();
      final decoded = BackgroundCaptureConfig.fromJson(json);

      expect(decoded.enabled, original.enabled);
      expect(decoded.interval, original.interval);
      expect(decoded.includeHealth, original.includeHealth);
      expect(decoded.includeEnvironment, original.includeEnvironment);
      expect(decoded.includeLocation, original.includeLocation);
      expect(decoded.includeCalendar, original.includeCalendar);
      expect(decoded.quietHoursStartHour, original.quietHoursStartHour);
      expect(decoded.quietHoursStartMinute, original.quietHoursStartMinute);
      expect(decoded.quietHoursEndHour, original.quietHoursEndHour);
      expect(decoded.quietHoursEndMinute, original.quietHoursEndMinute);
      expect(decoded.batteryOptimization, original.batteryOptimization);
    });

    test('fromJson uses defaults for missing keys', () {
      final decoded = BackgroundCaptureConfig.fromJson({});
      expect(decoded.enabled, false);
      expect(decoded.interval, const Duration(minutes: 30));
      expect(decoded.includeHealth, true);
      expect(decoded.quietHoursStartHour, 22);
    });

    test('encode / decode round-trip (String)', () {
      const original = BackgroundCaptureConfig(
        enabled: true,
        interval: Duration(minutes: 15),
      );
      final encoded = original.encode();
      expect(encoded, isA<String>());
      final decoded = BackgroundCaptureConfig.decode(encoded);
      expect(decoded.enabled, true);
      expect(decoded.interval.inMinutes, 15);
    });

    test('toJson stores interval as minutes', () {
      const c = BackgroundCaptureConfig(interval: Duration(hours: 4));
      expect(c.toJson()['interval_minutes'], 240);
    });
  });

  // ─── copyWith ─────────────────────────────────────────────────────────────

  group('copyWith', () {
    test('preserves values when no args', () {
      const original = BackgroundCaptureConfig(
        enabled: true,
        interval: Duration(hours: 1),
      );
      final copy = original.copyWith();
      expect(copy.enabled, true);
      expect(copy.interval, const Duration(hours: 1));
    });

    test('overrides specified fields', () {
      const original = BackgroundCaptureConfig();
      final copy = original.copyWith(
        enabled: true,
        interval: const Duration(minutes: 15),
        includeHealth: false,
        quietHoursStartHour: 20,
        quietHoursEndMinute: 15,
      );
      expect(copy.enabled, true);
      expect(copy.interval, const Duration(minutes: 15));
      expect(copy.includeHealth, false);
      expect(copy.quietHoursStartHour, 20);
      expect(copy.quietHoursEndMinute, 15);
      // unchanged
      expect(copy.includeEnvironment, true);
    });
  });

  // ─── isInQuietHours ───────────────────────────────────────────────────────

  group('isInQuietHours', () {
    test('overnight range (22:00 → 07:00): during quiet hours (23:00)', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 22,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 7,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 23, 0)), true);
    });

    test('overnight range: during quiet hours (01:00)', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 22,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 7,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 1, 0)), true);
    });

    test('overnight range: at start boundary (22:00) → in quiet hours', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 22,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 7,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 22, 0)), true);
    });

    test('overnight range: at end boundary (07:00) → NOT in quiet hours', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 22,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 7,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 7, 0)), false);
    });

    test('overnight range: during daytime (12:00) → NOT in quiet hours', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 22,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 7,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 12, 0)), false);
    });

    test('same-day range (08:00 → 12:00): during quiet hours (10:00)', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 8,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 12,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 10, 0)), true);
    });

    test('same-day range: at start boundary (08:00) → in quiet hours', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 8,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 12,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 8, 0)), true);
    });

    test('same-day range: at end boundary (12:00) → NOT in quiet hours', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 8,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 12,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 12, 0)), false);
    });

    test('same-day range: outside (15:00) → NOT in quiet hours', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 8,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 12,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 15, 0)), false);
    });

    test('quiet hours with minutes (22:30 → 06:45)', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 22,
        quietHoursStartMinute: 30,
        quietHoursEndHour: 6,
        quietHoursEndMinute: 45,
      );
      // 22:29 → NOT quiet
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 22, 29)), false);
      // 22:30 → quiet
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 22, 30)), true);
      // 06:44 → quiet
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 6, 44)), true);
      // 06:45 → NOT quiet
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 6, 45)), false);
    });

    test('midnight edge case (00:00) in overnight range', () {
      const config = BackgroundCaptureConfig(
        quietHoursStartHour: 22,
        quietHoursStartMinute: 0,
        quietHoursEndHour: 7,
        quietHoursEndMinute: 0,
      );
      expect(config.isInQuietHours(DateTime(2025, 1, 1, 0, 0)), true);
    });
  });

  // ─── toString ─────────────────────────────────────────────────────────────

  group('toString', () {
    test('includes key fields', () {
      const config = BackgroundCaptureConfig(enabled: true);
      final str = config.toString();
      expect(str, contains('enabled=true'));
      expect(str, contains('interval=30min'));
    });
  });
}
