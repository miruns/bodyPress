import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'core/router/app_router.dart';
import 'core/services/service_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezone data is needed for scheduled notifications.
  tz.initializeTimeZones();

  // Load .env file (keys available via dotenv.env['KEY']).
  // Silently ignored when the file is absent (e.g. CI builds that use --dart-define).
  await dotenv.load(fileName: '.env', mergeWith: {}).catchError((_) {});

  // Build a single ProviderContainer that lives for the app's lifetime.
  // All provider reads here share the same instances as the widget tree.
  final container = ProviderContainer();

  bool skipOnboarding = false;

  try {
    // Hydrate the persisted AI provider configuration before any AI calls.
    await container
        .read(aiConfigProvider.notifier)
        .init()
        .timeout(const Duration(seconds: 3), onTimeout: () {});

    // Initialise background capture scheduler (re-registers periodic task
    // if the user previously enabled it).
    final bgService = container.read(backgroundCaptureServiceProvider);
    await bgService.initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () => debugPrint('[main] bgService.initialize() timed out'),
    );

    // Show onboarding only when permissions are missing.
    // Always check actual OS permissions so that revoking them
    // re-surfaces the onboarding flow on next launch.
    final db = container.read(localDbServiceProvider);
    final permService = container.read(permissionServiceProvider);
    final healthService = container.read(healthServiceProvider);
    final criticalPerms = await permService
        .areCriticalPermissionsGranted()
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    final healthPerms = await healthService.hasPermissionsProbe().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    skipOnboarding = criticalPerms && healthPerms;
    // Keep the DB flag in sync so other parts of the app can read it.
    await db.setSetting('skip_onboarding', skipOnboarding ? 'true' : 'false');

    // Schedule the two hardcoded daily pushes (08:30 + 20:00).
    // Request permission first — on Android 13+ this is required at runtime.
    final notifService = container.read(notificationServiceProvider);
    await notifService.initialize();
    await notifService.requestPermission();
    await notifService.scheduleDailyReminders();
  } catch (e, st) {
    // Initialization errors must never prevent the app from launching.
    // In release builds an unhandled exception here leaves the native splash
    // screen frozen forever because runApp() would never be reached.
    debugPrint('[main] Initialization error: $e\n$st');
  }

  AppRouter.init(skipOnboarding: skipOnboarding);

  // Silently warm up AI metadata for any captures that were never analyzed
  // (fire-and-forget failure during capture save, or captures pre-dating
  // this feature). Runs in the background so Patterns data is ready before
  // the user navigates there. The re-entrant guard in the service ensures
  // a subsequent Patterns-screen visit won't spawn a second loop.
  unawaited(
    container
        .read(captureMetadataServiceProvider)
        .processAllPendingMetadata()
        .catchError((Object e) {
          debugPrint('[main] Background metadata catch-up error: $e');
          return 0;
        }),
  );

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'BodyPress',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: AppRouter.router,
    );
  }
}
