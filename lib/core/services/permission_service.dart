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

  // Open app settings if permissions are denied
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
