import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  // Request Location Permission
  Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  // Request Calendar Permission
  Future<bool> requestCalendarPermission() async {
    final status = await Permission.calendarFullAccess.request();
    return status.isGranted;
  }

  // Request Activity Recognition (for health tracking)
  Future<bool> requestActivityRecognitionPermission() async {
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  }

  // Request Sensors Permission (for health data on Android)
  Future<bool> requestSensorsPermission() async {
    final status = await Permission.sensors.request();
    return status.isGranted;
  }

  // Request All Critical Permissions
  Future<Map<String, bool>> requestAllPermissions() async {
    final results = <String, bool>{};

    results['location'] = await requestLocationPermission();
    results['calendar'] = await requestCalendarPermission();
    results['activityRecognition'] =
        await requestActivityRecognitionPermission();
    results['sensors'] = await requestSensorsPermission();

    return results;
  }

  // Check Location Permission Status
  Future<bool> isLocationPermissionGranted() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  // Check Calendar Permission Status
  Future<bool> isCalendarPermissionGranted() async {
    final status = await Permission.calendarFullAccess.status;
    return status.isGranted;
  }

  // Check if all critical permissions are granted
  Future<bool> areAllPermissionsGranted() async {
    final location = await isLocationPermissionGranted();
    final calendar = await isCalendarPermissionGranted();

    return location && calendar;
  }

  /// Returns true when the permissions that gate the core experience are in
  /// place — location + activity recognition.  Calendar, notifications, and
  /// body-sensors enhance the experience but are not required to skip the
  /// intro.  This check never triggers a system dialog.
  Future<bool> areCriticalPermissionsGranted() async {
    final location = await Permission.location.status;
    final activity = await Permission.activityRecognition.status;
    return location.isGranted && activity.isGranted;
  }

  // ── Battery optimization ────────────────────────────────────────────────

  /// Request exemption from battery optimization (Doze mode).
  ///
  /// This is **critical** for reliable background notifications.  Without it,
  /// Android aggressively kills scheduled alarms and WorkManager tasks.
  /// Shows a system dialog — not a runtime permission prompt.
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return true;
      final result = await Permission.ignoreBatteryOptimizations.request();
      debugPrint('[PermissionService] Battery optimization exemption: $result');
      return result.isGranted;
    } catch (e) {
      debugPrint('[PermissionService] Battery opt error: $e');
      return false;
    }
  }

  /// Whether the app is already exempt from battery optimization.
  Future<bool> isBatteryOptimizationExempted() async {
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return false;
    }
  }

  // ── Exact alarm permission ──────────────────────────────────────────────

  /// Request permission to schedule exact alarms (Android 12+).
  ///
  /// Required for `exactAllowWhileIdle` mode in flutter_local_notifications.
  Future<bool> requestExactAlarmPermission() async {
    try {
      final status = await Permission.scheduleExactAlarm.status;
      if (status.isGranted) return true;
      final result = await Permission.scheduleExactAlarm.request();
      debugPrint('[PermissionService] Exact alarm permission: $result');
      return result.isGranted;
    } catch (e) {
      debugPrint('[PermissionService] Exact alarm error: $e');
      return false;
    }
  }

  // Open app settings if permissions are denied
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
