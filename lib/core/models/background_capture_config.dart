import 'dart:convert';

/// User preferences for background capture behaviour.
///
/// Persisted as a JSON blob in the `settings` table under the key
/// `background_capture_config`.
class BackgroundCaptureConfig {
  /// Whether background captures are enabled at all.
  final bool enabled;

  /// Minimum interval between scheduled captures.
  ///
  /// Android WorkManager enforces a 15-minute minimum. Allowed presets:
  /// 15 min, 30 min, 1 h, 2 h, 4 h.
  final Duration interval;

  /// Include health metrics (steps, heart rate, etc.).
  final bool includeHealth;

  /// Include environment data (weather, AQI, UV).
  final bool includeEnvironment;

  /// Include GPS location data.
  final bool includeLocation;

  /// Include calendar events.
  final bool includeCalendar;

  /// Start of daily quiet hours (no background captures).
  final int quietHoursStartHour;
  final int quietHoursStartMinute;

  /// End of daily quiet hours.
  final int quietHoursEndHour;
  final int quietHoursEndMinute;

  /// Reduce capture frequency when battery is low.
  final bool batteryOptimization;

  const BackgroundCaptureConfig({
    this.enabled = true,
    this.interval = const Duration(minutes: 30),
    this.includeHealth = true,
    this.includeEnvironment = true,
    this.includeLocation = true,
    this.includeCalendar = true,
    this.quietHoursStartHour = 22,
    this.quietHoursStartMinute = 0,
    this.quietHoursEndHour = 7,
    this.quietHoursEndMinute = 0,
    this.batteryOptimization = true,
  });

  /// Default configuration — background captures enabled.
  static const BackgroundCaptureConfig defaultConfig =
      BackgroundCaptureConfig();

  BackgroundCaptureConfig copyWith({
    bool? enabled,
    Duration? interval,
    bool? includeHealth,
    bool? includeEnvironment,
    bool? includeLocation,
    bool? includeCalendar,
    int? quietHoursStartHour,
    int? quietHoursStartMinute,
    int? quietHoursEndHour,
    int? quietHoursEndMinute,
    bool? batteryOptimization,
  }) {
    return BackgroundCaptureConfig(
      enabled: enabled ?? this.enabled,
      interval: interval ?? this.interval,
      includeHealth: includeHealth ?? this.includeHealth,
      includeEnvironment: includeEnvironment ?? this.includeEnvironment,
      includeLocation: includeLocation ?? this.includeLocation,
      includeCalendar: includeCalendar ?? this.includeCalendar,
      quietHoursStartHour: quietHoursStartHour ?? this.quietHoursStartHour,
      quietHoursStartMinute:
          quietHoursStartMinute ?? this.quietHoursStartMinute,
      quietHoursEndHour: quietHoursEndHour ?? this.quietHoursEndHour,
      quietHoursEndMinute: quietHoursEndMinute ?? this.quietHoursEndMinute,
      batteryOptimization: batteryOptimization ?? this.batteryOptimization,
    );
  }

  /// Whether the current time falls within the configured quiet hours.
  bool isInQuietHours([DateTime? now]) {
    final time = now ?? DateTime.now();
    final currentMinutes = time.hour * 60 + time.minute;
    final startMinutes = quietHoursStartHour * 60 + quietHoursStartMinute;
    final endMinutes = quietHoursEndHour * 60 + quietHoursEndMinute;

    if (startMinutes <= endMinutes) {
      // e.g. 08:00 → 12:00
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // e.g. 22:00 → 07:00 (overnight)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'interval_minutes': interval.inMinutes,
    'include_health': includeHealth,
    'include_environment': includeEnvironment,
    'include_location': includeLocation,
    'include_calendar': includeCalendar,
    'quiet_hours_start_hour': quietHoursStartHour,
    'quiet_hours_start_minute': quietHoursStartMinute,
    'quiet_hours_end_hour': quietHoursEndHour,
    'quiet_hours_end_minute': quietHoursEndMinute,
    'battery_optimization': batteryOptimization,
  };

  factory BackgroundCaptureConfig.fromJson(Map<String, dynamic> json) {
    return BackgroundCaptureConfig(
      enabled: json['enabled'] as bool? ?? false,
      interval: Duration(minutes: json['interval_minutes'] as int? ?? 30),
      includeHealth: json['include_health'] as bool? ?? true,
      includeEnvironment: json['include_environment'] as bool? ?? true,
      includeLocation: json['include_location'] as bool? ?? true,
      includeCalendar: json['include_calendar'] as bool? ?? true,
      quietHoursStartHour: json['quiet_hours_start_hour'] as int? ?? 22,
      quietHoursStartMinute: json['quiet_hours_start_minute'] as int? ?? 0,
      quietHoursEndHour: json['quiet_hours_end_hour'] as int? ?? 7,
      quietHoursEndMinute: json['quiet_hours_end_minute'] as int? ?? 0,
      batteryOptimization: json['battery_optimization'] as bool? ?? true,
    );
  }

  /// Convenience: encode/decode for the settings table.
  String encode() => jsonEncode(toJson());
  static BackgroundCaptureConfig decode(String raw) =>
      BackgroundCaptureConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  String toString() =>
      'BackgroundCaptureConfig('
      'enabled=$enabled, '
      'interval=${interval.inMinutes}min, '
      'health=$includeHealth, env=$includeEnvironment, '
      'loc=$includeLocation, cal=$includeCalendar)';
}
