import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// Thin wrapper around the Google Play In-App Updates API.
///
/// Works on internal, closed, open and production tracks.
/// On non-Android platforms or debug/sideloaded builds the check
/// silently returns without showing anything.
class AppUpdateService {
  /// Check the Play Store for a newer version and prompt the user.
  ///
  /// Uses a **flexible** update flow by default (user can continue using
  /// the app while it downloads). Pass [immediate] = true to block the
  /// app until the update is installed.
  Future<void> checkForUpdate({bool immediate = false}) async {
    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return; // Already on the latest version.
      }

      if (immediate && info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        // Once download completes, ask the user to restart.
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      // Expected to fail on debug builds, sideloaded APKs, emulators, etc.
      debugPrint('[AppUpdateService] In-app update check failed: $e');
    }
  }
}
