import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/models/ai_models.dart';
import '../../core/models/background_capture_config.dart';
import '../../core/models/body_blog_entry.dart';
import '../../core/models/capture_entry.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/service_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DEBUG PANEL
//  Full-spectrum diagnostics: permissions · db · health · context · actions
// ─────────────────────────────────────────────────────────────────────────────

class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  // ── services ──────────────────────────────────────────
  late final _db = ref.read(localDbServiceProvider);
  late final _health = ref.read(healthServiceProvider);
  late final _permissions = ref.read(permissionServiceProvider);
  late final _context = ref.read(contextWindowServiceProvider);
  late final _blog = ref.read(bodyBlogServiceProvider);
  late final _ai = ref.read(aiServiceProvider);
  late final _bgCapture = ref.read(backgroundCaptureServiceProvider);
  late final _captureService = ref.read(captureServiceProvider);
  late final _notifService = ref.read(notificationServiceProvider);

  // ── state ──────────────────────────────────────────────
  bool _loading = true;

  // Permissions
  Map<String, _PermStatus> _permStatuses = {};

  // DB
  DbInfo? _dbInfo;
  List<Map<String, Object?>> _dbRows = [];

  // Health
  int _steps = 0;
  double _calories = 0;
  double _distanceKm = 0;
  double _sleepHours = 0;
  int _avgHr = 0;
  int _workouts = 0;
  bool _healthAuthorized = false;

  // Context window
  String _contextText = '';
  List<BodyBlogEntry> _contextEntries = [];

  // Recent entries
  List<BodyBlogEntry> _recentEntries = [];

  // AI service
  bool? _aiHealthy;
  String? _aiTestResponse;
  bool _aiTestRunning = false;

  // Background captures
  BackgroundCaptureConfig _bgConfig = BackgroundCaptureConfig.defaultConfig;
  Map<String, String> _bgStats = {};
  int _totalCaptures = 0;
  int _bgCaptures = 0;
  List<CaptureEntry> _recentCaptures = [];
  bool _bgTriggerRunning = false;

  // Daily notification
  bool _dailyReminderEnabled = false;
  TimeOfDay _dailyReminderTime = const TimeOfDay(hour: 9, minute: 0);

  // Errors per section
  String? _permError;
  String? _dbError;
  String? _healthError;
  String? _contextError;
  String? _aiError;
  String? _bgCaptureError;

  // Action state
  bool _actionRunning = false;
  String? _actionMessage;

  // Expanded state for each panel
  final Set<String> _expanded = {'permissions', 'db', 'health'};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _actionMessage = null;
    });
    await Future.wait([
      _loadPermissions(),
      _loadDb(),
      _loadHealth(),
      _loadContext(),
      _loadAi(),
      _loadBgCapture(),
      _loadDailyReminder(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  // ── loaders ───────────────────────────────────────────

  Future<void> _loadPermissions() async {
    try {
      final loc = await Permission.location.status;
      final cal = await Permission.calendarFullAccess.status;
      final act = await Permission.activityRecognition.status;
      final sen = await Permission.sensors.status;
      final healthOk = await _health.hasPermissions();

      if (mounted) {
        setState(() {
          _permStatuses = {
            'location': _PermStatus(
              icon: Icons.location_on_outlined,
              label: 'Location',
              status: loc,
              description: 'GPS tracking & ambient scan',
            ),
            'calendar': _PermStatus(
              icon: Icons.calendar_today_outlined,
              label: 'Calendar',
              status: cal,
              description: 'Workout scheduling & events',
            ),
            'activity': _PermStatus(
              icon: Icons.directions_run_outlined,
              label: 'Activity Recognition',
              status: act,
              description: 'Step counting & movement detection',
            ),
            'sensors': _PermStatus(
              icon: Icons.sensors_outlined,
              label: 'Sensors',
              status: sen,
              description: 'Heart rate & body sensors (Android)',
            ),
            'health': _PermStatus(
              icon: Icons.favorite_outline,
              label: 'Health / HealthKit',
              statusOverride: healthOk,
              description: 'Steps, sleep, heart rate, workouts',
            ),
          };
          _permError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _permError = e.toString());
    }
  }

  Future<void> _loadDb() async {
    try {
      final info = await _db.getDbInfo();
      final rows = await _db.getDebugRows();
      if (mounted) {
        setState(() {
          _dbInfo = info;
          _dbRows = rows;
          _dbError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _dbError = e.toString());
    }
  }

  Future<void> _loadHealth() async {
    try {
      final auth = await _health.hasPermissions();
      if (auth) {
        final results = await Future.wait([
          _health.getTodaySteps(),
          _health.getTodayCalories(),
          _health.getTodayDistance(),
          _health.getLastNightSleep(),
          _health.getTodayAverageHeartRate(),
          _health.getTodayWorkoutCount(),
        ]);
        if (mounted) {
          setState(() {
            _healthAuthorized = true;
            _steps = results[0] as int;
            _calories = results[1] as double;
            _distanceKm = (results[2] as double) / 1000;
            _sleepHours = results[3] as double;
            _avgHr = results[4] as int;
            _workouts = results[5] as int;
            _healthError = null;
          });
        }
      } else {
        if (mounted) setState(() => _healthAuthorized = false);
      }
    } catch (e) {
      if (mounted) setState(() => _healthError = e.toString());
    }
  }

  Future<void> _loadContext() async {
    try {
      final result = await _context.build(days: 7);
      if (mounted) {
        setState(() {
          _contextText = result.text;
          _contextEntries = result.entries;
          _recentEntries = result.entries;
          _contextError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _contextError = e.toString());
    }
  }

  Future<void> _loadAi() async {
    try {
      setState(() => _aiError = null);
      _aiHealthy = await _ai.checkHealth();
      if (mounted) setState(() {});
    } catch (e) {
      setState(() {
        _aiHealthy = false;
        _aiError = e.toString();
      });
    }
  }

  Future<void> _loadBgCapture() async {
    try {
      final config = await _bgCapture.loadConfig();
      final stats = await _bgCapture.getStats();
      final total = await _db.countCaptures();
      final allCaptures = await _db.loadCaptures(limit: 200);
      final bgCount = allCaptures
          .where((c) => c.source != CaptureSource.manual)
          .length;
      final recent = await _db.loadCaptures(limit: 5);
      if (mounted) {
        setState(() {
          _bgConfig = config;
          _bgStats = stats;
          _totalCaptures = total;
          _bgCaptures = bgCount;
          _recentCaptures = recent;
          _bgCaptureError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _bgCaptureError = e.toString());
    }
  }

  // ── actions ───────────────────────────────────────────

  Future<void> _loadDailyReminder() async {
    try {
      final timeSetting = await _db.getSetting('daily_reminder_time');
      if (mounted) {
        if (timeSetting != null && timeSetting.isNotEmpty) {
          final parts = timeSetting.split(':');
          if (parts.length == 2) {
            final h = int.tryParse(parts[0]) ?? 9;
            final m = int.tryParse(parts[1]) ?? 0;
            setState(() {
              _dailyReminderEnabled = true;
              _dailyReminderTime = TimeOfDay(hour: h, minute: m);
            });
          }
        } else {
          setState(() => _dailyReminderEnabled = false);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleDailyReminder() async {
    if (_dailyReminderEnabled) {
      // Disable
      await _notifService.cancelDailyReminder();
      await _db.setSetting('daily_reminder_time', '');
      // Remove the setting by writing empty; on reload it acts as disabled.
      // Actually let's truly remove it by overwriting, but our getSetting
      // returns the raw string. We'll check for empty too.
      _setActionMsg('Daily reminder disabled.');
    } else {
      // Enable with current time
      await _notifService.initialize();
      await _notifService.scheduleDailyReminder(
        hour: _dailyReminderTime.hour,
        minute: _dailyReminderTime.minute,
      );
      await _db.setSetting(
        'daily_reminder_time',
        '${_dailyReminderTime.hour}:${_dailyReminderTime.minute}',
      );
      _setActionMsg(
        'Daily reminder enabled at '
        '${_dailyReminderTime.hour.toString().padLeft(2, '0')}:'
        '${_dailyReminderTime.minute.toString().padLeft(2, '0')}.',
      );
    }
    await _loadDailyReminder();
  }

  Future<void> _pickDailyReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyReminderTime,
      helpText: 'Daily notification time',
    );
    if (picked == null || !mounted) return;

    setState(() => _dailyReminderTime = picked);

    if (_dailyReminderEnabled) {
      await _notifService.scheduleDailyReminder(
        hour: picked.hour,
        minute: picked.minute,
      );
      await _db.setSetting(
        'daily_reminder_time',
        '${picked.hour}:${picked.minute}',
      );
      _setActionMsg(
        'Reminder rescheduled to '
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}.',
      );
    }
  }

  Future<void> _sendTestDailyNotification() async {
    await _notifService.initialize();
    await _notifService.showTestDailyReminder();
    _setActionMsg('Test daily notification sent.');
  }

  Future<void> _toggleBgCapture() async {
    setState(() => _actionRunning = true);
    try {
      if (_bgConfig.enabled) {
        await _bgCapture.disable();
        _setActionMsg('Background captures disabled.');
      } else {
        await _bgCapture.enable();
        _setActionMsg('Background captures enabled!');
      }
      await _loadBgCapture();
    } catch (e) {
      _setActionMsg('Error: $e');
    }
  }

  Future<void> _triggerBgCaptureNow() async {
    setState(() => _bgTriggerRunning = true);
    try {
      // Run a direct foreground capture tagged as backgroundScheduled for testing
      final capture = await _captureService.createCapture(
        includeHealth: _bgConfig.includeHealth,
        includeEnvironment: _bgConfig.includeEnvironment,
        includeLocation: _bgConfig.includeLocation,
        includeCalendar: _bgConfig.includeCalendar,
        source: CaptureSource.backgroundScheduled,
        trigger: CaptureTrigger.time,
      );
      await _loadBgCapture();
      _setActionMsg(
        'Capture ${capture.id} saved '
        '(${capture.executionDuration?.inMilliseconds ?? "?"} ms).',
      );
    } catch (e) {
      _setActionMsg('Capture failed: $e');
    } finally {
      if (mounted) setState(() => _bgTriggerRunning = false);
    }
  }

  Future<void> _resetBgStats() async {
    setState(() => _actionRunning = true);
    try {
      await _bgCapture.resetStats();
      await _loadBgCapture();
      _setActionMsg('Background capture stats reset.');
    } catch (e) {
      _setActionMsg('Error: $e');
    }
  }

  Future<void> _updateBgInterval(Duration interval) async {
    setState(() => _actionRunning = true);
    try {
      final newConfig = _bgConfig.copyWith(interval: interval);
      await _bgCapture.updateConfig(newConfig);
      await _loadBgCapture();
      _setActionMsg('Interval updated to ${interval.inMinutes} min.');
    } catch (e) {
      _setActionMsg('Error: $e');
    }
  }

  Future<void> _toggleBgDataSource(String source) async {
    BackgroundCaptureConfig newConfig;
    switch (source) {
      case 'health':
        newConfig = _bgConfig.copyWith(includeHealth: !_bgConfig.includeHealth);
        break;
      case 'environment':
        newConfig = _bgConfig.copyWith(
          includeEnvironment: !_bgConfig.includeEnvironment,
        );
        break;
      case 'location':
        newConfig = _bgConfig.copyWith(
          includeLocation: !_bgConfig.includeLocation,
        );
        break;
      case 'calendar':
        newConfig = _bgConfig.copyWith(
          includeCalendar: !_bgConfig.includeCalendar,
        );
        break;
      default:
        return;
    }
    await _bgCapture.updateConfig(newConfig);
    await _loadBgCapture();
  }

  Future<void> _requestNotificationPermission() async {
    final notifService = ref.read(notificationServiceProvider);
    await notifService.initialize();
    final granted = await notifService.requestPermission();
    _setActionMsg(
      granted
          ? 'Notification permission granted.'
          : 'Notification permission denied.',
    );
  }

  Future<void> _requestAllPermissions() async {
    setState(() => _actionRunning = true);
    try {
      await _permissions.requestAllPermissions();
      await _health.requestAuthorization();
      await _loadPermissions();
      _setActionMsg('Permissions re-requested.');
    } catch (e) {
      _setActionMsg('Error: $e');
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _forceRefreshEntry() async {
    setState(() => _actionRunning = true);
    try {
      await _blog.getTodayEntry();
      await _loadDb();
      await _loadContext();
      _setActionMsg('Today\'s entry refreshed.');
    } catch (e) {
      _setActionMsg('Error: $e');
    }
  }

  Future<void> _clearDb() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all entries?'),
        content: const Text(
          'This permanently deletes every body-blog entry from the local database. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _actionRunning = true);
    try {
      // Delete all entries day by day by loading and deleting
      final rows = await _db.getDebugRows();
      int deleted = 0;
      for (final row in rows) {
        final dateStr = row['date'] as String?;
        if (dateStr != null) {
          final date = DateTime.tryParse('${dateStr}T00:00:00.000');
          if (date != null) {
            await _db.deleteEntry(date);
            deleted++;
          }
        }
      }
      await _loadDb();
      await _loadContext();
      _setActionMsg('Deleted $deleted entr${deleted == 1 ? 'y' : 'ies'}.');
    } catch (e) {
      _setActionMsg('Error: $e');
    }
  }

  Future<void> _copyContext() async {
    await Clipboard.setData(ClipboardData(text: _contextText));
    _setActionMsg('Context window copied to clipboard.');
  }

  Future<void> _runAiTest() async {
    setState(() {
      _aiTestRunning = true;
      _aiTestResponse = null;
    });
    try {
      final response = await _ai.ask(
        'Respond with exactly one encouraging sentence about fitness.',
        temperature: 0.7,
      );
      setState(() {
        _aiTestResponse = response;
        _actionMessage = 'AI test completed';
      });
    } on AiServiceException catch (e) {
      setState(() {
        _aiTestResponse = 'Error: ${e.message}';
        _aiError = e.toString();
      });
    } catch (e) {
      setState(() {
        _aiTestResponse = 'Unexpected error: $e';
        _aiError = e.toString();
      });
    } finally {
      setState(() => _aiTestRunning = false);
    }
  }

  void _setActionMsg(String msg) {
    if (mounted) {
      setState(() {
        _actionRunning = false;
        _actionMessage = msg;
      });
    }
  }

  void _toggle(String key) {
    setState(() {
      if (_expanded.contains(key)) {
        _expanded.remove(key);
      } else {
        _expanded.add(key);
      }
    });
  }

  // ── build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF0E0E0E) : const Color(0xFFF5F5F5);
    final surface = dark ? const Color(0xFF1A1A1A) : Colors.white;
    final dividerColor = dark ? Colors.white12 : Colors.black12;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(
            children: [
              // ── top bar
              _buildTopBar(dark),
              // ── content
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          children: [
                            // ── app info
                            _buildAppInfoCard(dark, surface),
                            const SizedBox(height: 12),
                            // ── permissions
                            _buildSection(
                              key: 'permissions',
                              title: 'Permissions',
                              icon: Icons.shield_outlined,
                              accent: Colors.orange,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              badge: _permissionsBadge(),
                              errorText: _permError,
                              child: _buildPermissionsContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── database
                            _buildSection(
                              key: 'db',
                              title: 'Database',
                              icon: Icons.storage_outlined,
                              accent: Colors.blue,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              badge: _dbInfo == null
                                  ? null
                                  : '${_dbInfo!.entryCount}j · ${_dbInfo!.captureCount}c',
                              errorText: _dbError,
                              child: _buildDbContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── health
                            _buildSection(
                              key: 'health',
                              title: 'Health Snapshot',
                              icon: Icons.monitor_heart_outlined,
                              accent: Colors.red,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              badge: _healthAuthorized
                                  ? 'authorized'
                                  : 'no access',
                              badgeColor: _healthAuthorized
                                  ? Colors.green
                                  : Colors.red,
                              errorText: _healthError,
                              child: _buildHealthContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── ai service
                            _buildSection(
                              key: 'ai',
                              title: 'AI Service',
                              icon: Icons.smart_toy_outlined,
                              accent: Colors.indigo,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              badge: _aiHealthy == null
                                  ? 'checking'
                                  : (_aiHealthy! ? 'online' : 'offline'),
                              badgeColor: _aiHealthy == null
                                  ? Colors.grey
                                  : (_aiHealthy! ? Colors.green : Colors.red),
                              errorText: _aiError,
                              child: _buildAiContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── context window
                            _buildSection(
                              key: 'context',
                              title: 'AI Context Window',
                              icon: Icons.psychology_outlined,
                              accent: Colors.purple,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              badge: '${_contextEntries.length} days',
                              errorText: _contextError,
                              child: _buildContextContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── background captures
                            _buildSection(
                              key: 'bgcapture',
                              title: 'Background Captures',
                              icon: Icons.sync_outlined,
                              accent: Colors.cyan,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              badge: _bgConfig.enabled ? 'enabled' : 'disabled',
                              badgeColor: _bgConfig.enabled
                                  ? Colors.green
                                  : Colors.grey,
                              errorText: _bgCaptureError,
                              child: _buildBgCaptureContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── daily notifications
                            _buildSection(
                              key: 'dailynotif',
                              title: 'Daily Notifications',
                              icon: Icons.notifications_none_rounded,
                              accent: const Color(0xFFA68BC1),
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              badge: _dailyReminderEnabled
                                  ? 'enabled'
                                  : 'disabled',
                              badgeColor: _dailyReminderEnabled
                                  ? Colors.green
                                  : Colors.grey,
                              child: _buildDailyNotifContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── recent entries
                            _buildSection(
                              key: 'entries',
                              title: 'Recent Entries',
                              icon: Icons.article_outlined,
                              accent: Colors.teal,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              child: _buildEntriesContent(dark),
                            ),
                            const SizedBox(height: 10),
                            // ── actions
                            _buildSection(
                              key: 'actions',
                              title: 'Actions',
                              icon: Icons.bolt_outlined,
                              accent: Colors.amber,
                              dark: dark,
                              surface: surface,
                              dividerColor: dividerColor,
                              child: _buildActionsContent(dark),
                            ),
                            if (_actionMessage != null) ...[
                              const SizedBox(height: 12),
                              _buildToast(dark),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────── TOP BAR ───────────────────────

  Widget _buildTopBar(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.bug_report,
            size: 22,
            color: dark ? Colors.white54 : Colors.black45,
          ),
          const SizedBox(width: 8),
          Text(
            'Debug Panel',
            style: GoogleFonts.spaceMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : Colors.black87,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (_actionRunning)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: dark ? Colors.white38 : Colors.black38,
            ),
            tooltip: 'Reload all',
            onPressed: _loading ? null : _loadAll,
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 20,
              color: dark ? Colors.white38 : Colors.black38,
            ),
            tooltip: 'Close',
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── APP INFO ───────────────────────

  Widget _buildAppInfoCard(bool dark, Color surface) {
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final monoStyle = GoogleFonts.spaceMono(
      fontSize: 11,
      color: dark ? Colors.white60 : Colors.black54,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BodyPress',
                style: GoogleFonts.spaceMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text('v1.0.0+1', style: monoStyle),
              Text(fmt.format(now), style: monoStyle),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _chip(
                Platform.isAndroid
                    ? 'Android'
                    : Platform.isIOS
                    ? 'iOS'
                    : 'Other',
                Colors.blue,
              ),
              const SizedBox(height: 4),
              _chip('DEBUG', Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────── SECTION WRAPPER ───────────────────────

  Widget _buildSection({
    required String key,
    required String title,
    required IconData icon,
    required Color accent,
    required bool dark,
    required Color surface,
    required Color dividerColor,
    Widget? child,
    String? badge,
    Color? badgeColor,
    String? errorText,
  }) {
    final isOpen = _expanded.contains(key);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white10 : Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggle(key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: GoogleFonts.spaceMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white : Colors.black87,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  if (badge != null) _chip(badge, badgeColor ?? accent),
                  const SizedBox(width: 8),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            Divider(height: 1, color: dividerColor),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        errorText,
                        style: GoogleFonts.spaceMono(
                          fontSize: 10,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (child != null)
              child,
          ],
        ],
      ),
    );
  }

  // ─────────────────────── PERMISSIONS ───────────────────────

  String? _permissionsBadge() {
    if (_permStatuses.isEmpty) return null;
    final granted = _permStatuses.values.where((p) => p.isGranted).length;
    final total = _permStatuses.length;
    return '$granted/$total granted';
  }

  Widget _buildPermissionsContent(bool dark) {
    return Column(
      children: [
        ..._permStatuses.entries.map(
          (e) => _buildPermRow(e.key, e.value, dark),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: 'Request All',
                  icon: Icons.refresh_rounded,
                  color: Colors.orange,
                  onTap: _actionRunning ? null : _requestAllPermissions,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  label: 'App Settings',
                  icon: Icons.settings_outlined,
                  color: Colors.blue,
                  onTap: _openSettings,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermRow(String id, _PermStatus perm, bool dark) {
    final statusLabel = perm.statusLabel;
    final statusColor = perm.statusColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(perm.icon, size: 16, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  perm.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  perm.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusBadge(statusLabel, statusColor),
          if (!perm.isGranted) ...[
            const SizedBox(width: 6),
            _tinyButton(
              label: perm.isPermanentlyDenied ? 'Settings' : 'Fix',
              color: Colors.orange,
              onTap: perm.isPermanentlyDenied
                  ? _openSettings
                  : _requestAllPermissions,
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────── DATABASE ───────────────────────

  Widget _buildDbContent(bool dark) {
    if (_dbInfo == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No database info available'),
      );
    }
    final mono = GoogleFonts.spaceMono(
      fontSize: 11,
      color: dark ? Colors.white60 : Colors.black54,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Metadata grid
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _dbKv('Schema', 'v${_dbInfo!.schemaVersion}', dark),
              _dbKv('Journal', '${_dbInfo!.entryCount}', dark),
              _dbKv('Captures', '${_dbInfo!.captureCount}', dark),
              _dbKv('Oldest', _dbInfo!.oldestDate ?? '—', dark),
              _dbKv('Newest', _dbInfo!.newestDate ?? '—', dark),
            ],
          ),
        ),
        // DB path (monospace, selectable)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: SelectableText(_dbInfo!.path, style: mono),
        ),
        // Table header
        if (_dbRows.isNotEmpty) ...[
          Divider(height: 1, color: dark ? Colors.white12 : Colors.black12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'RAW ROWS  (latest ${_dbRows.length})',
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white38 : Colors.black38,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Scrollable table
          SizedBox(
            height: 200,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount: _dbRows.length,
              itemBuilder: (_, i) {
                final row = _dbRows[i];
                final _ = (row['tags'] as String?) ?? '[]';
                final note = (row['user_note'] as String?);
                final userMood = (row['user_mood'] as String?);
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text(
                        row['date'] as String? ?? '—',
                        style: mono.copyWith(
                          fontWeight: FontWeight.w700,
                          color: dark
                              ? Colors.white70
                              : Colors.black.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${row['mood_emoji'] ?? ''} ${row['mood'] ?? ''}',
                        style: mono,
                      ),
                      const Spacer(),
                      if (userMood != null)
                        Text(userMood, style: const TextStyle(fontSize: 13)),
                      if (note != null)
                        Icon(
                          Icons.edit_note,
                          size: 13,
                          color: dark
                              ? Colors.white30
                              : Colors.black.withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text('No rows in database.', style: mono),
          ),
      ],
    );
  }

  Widget _dbKv(String label, String value, bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.spaceMono(
            fontSize: 9,
            color: dark ? Colors.white38 : Colors.black38,
            letterSpacing: 0.6,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.spaceMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  // ─────────────────────── HEALTH ───────────────────────

  Widget _buildHealthContent(bool dark) {
    if (!_healthAuthorized) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health access is not authorized. Grant permissions to see today\'s metrics.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            _actionButton(
              label: 'Request Health Access',
              icon: Icons.favorite_outline,
              color: Colors.red,
              onTap: _actionRunning ? null : _requestAllPermissions,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _healthTile(
            Icons.directions_walk_outlined,
            _steps.toString(),
            'Steps',
            Colors.green,
            dark,
          ),
          _healthTile(
            Icons.local_fire_department_outlined,
            '${_calories.toStringAsFixed(0)} kcal',
            'Calories',
            Colors.orange,
            dark,
          ),
          _healthTile(
            Icons.route_outlined,
            '${_distanceKm.toStringAsFixed(2)} km',
            'Distance',
            Colors.blue,
            dark,
          ),
          _healthTile(
            Icons.bedtime_outlined,
            '${_sleepHours.toStringAsFixed(1)} h',
            'Sleep',
            Colors.indigo,
            dark,
          ),
          _healthTile(
            Icons.favorite_outlined,
            _avgHr > 0 ? '$_avgHr bpm' : '—',
            'Avg Heart Rate',
            Colors.red,
            dark,
          ),
          _healthTile(
            Icons.fitness_center_outlined,
            '$_workouts',
            'Workouts',
            Colors.teal,
            dark,
          ),
        ],
      ),
    );
  }

  Widget _healthTile(
    IconData icon,
    String value,
    String label,
    Color color,
    bool dark,
  ) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── AI SERVICE ───────────────────────

  Widget _buildAiContent(bool dark) {
    final mono = GoogleFonts.spaceMono(
      fontSize: 11,
      color: dark ? Colors.white60 : Colors.black54,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Icon(
                _aiHealthy == true ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: _aiHealthy == true ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                _aiHealthy == true
                    ? 'AI service is online and responding'
                    : 'AI service is not available',
                style: TextStyle(
                  fontSize: 12,
                  color: dark
                      ? Colors.white70
                      : Colors.black.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Endpoint info
          Text(
            'ENDPOINT',
            style: GoogleFonts.spaceMono(
              fontSize: 9,
              color: dark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText('https://ai.governor-hq.com', style: mono),
          const SizedBox(height: 16),
          // Test button
          _actionButton(
            label: 'Send test prompt',
            icon: Icons.send_outlined,
            color: Colors.indigo,
            onTap: (_aiHealthy != true || _aiTestRunning) ? null : _runAiTest,
          ),
          if (_aiTestRunning) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 8),
                Text(
                  'Waiting for AI response...',
                  style: TextStyle(
                    fontSize: 11,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ],
          if (_aiTestResponse != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.indigo.withValues(alpha: 0.1)
                    : Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.smart_toy,
                        size: 13,
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AI Response',
                        style: GoogleFonts.spaceMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _aiTestResponse!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: dark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────── CONTEXT WINDOW ───────────────────────

  Widget _buildContextContent(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Copy button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Text(
                'Last ${_contextEntries.length} da${_contextEntries.length == 1 ? 'y' : 'ys'} · '
                '${_contextText.split('\n').length} lines',
                style: TextStyle(
                  fontSize: 11,
                  color: dark ? Colors.white38 : Colors.black38,
                ),
              ),
              const Spacer(),
              _tinyButton(
                label: 'Copy',
                color: Colors.purple,
                icon: Icons.copy_outlined,
                onTap: _copyContext,
              ),
            ],
          ),
        ),
        // Preformatted text
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: dark ? Colors.black54 : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _contextText.isEmpty
                  ? 'No context yet. Run the app for at least one day.'
                  : _contextText,
              style: GoogleFonts.spaceMono(
                fontSize: 10.5,
                height: 1.6,
                color: dark
                    ? Colors.white70
                    : Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────── RECENT ENTRIES ───────────────────────

  Widget _buildEntriesContent(bool dark) {
    if (_recentEntries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No entries stored yet.', style: TextStyle(fontSize: 13)),
      );
    }
    final fmt = DateFormat('EEE d MMM');
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      itemCount: _recentEntries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final e = _recentEntries[i];
        final s = e.snapshot;
        final isToday = i == 0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isToday
                ? (dark
                      ? Colors.teal.withValues(alpha: 0.1)
                      : Colors.teal.shade50)
                : (dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(8),
            border: isToday
                ? Border.all(color: Colors.teal.withValues(alpha: 0.35))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    fmt.format(e.date),
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isToday
                          ? Colors.teal
                          : (dark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 6),
                    _chip('TODAY', Colors.teal),
                  ],
                  const Spacer(),
                  Text(e.moodEmoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(
                    e.mood,
                    style: TextStyle(
                      fontSize: 11,
                      color: dark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                e.headline,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Snapshot mini row
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (s.steps > 0) _miniStat('👟', '${s.steps} steps'),
                  if (s.sleepHours > 0)
                    _miniStat(
                      '😴',
                      '${s.sleepHours.toStringAsFixed(1)}h sleep',
                    ),
                  if (s.avgHeartRate > 0)
                    _miniStat('❤️', '${s.avgHeartRate} bpm'),
                  if (s.temperatureC != null)
                    _miniStat('🌡️', '${s.temperatureC!.toStringAsFixed(1)}°C'),
                  if (s.city != null) _miniStat('📍', s.city!),
                  if (s.calendarEvents.isNotEmpty)
                    _miniStat('📅', '${s.calendarEvents.length} events'),
                ],
              ),
              if (e.userMood != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(e.userMood!, style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Text(
                      'user mood',
                      style: TextStyle(
                        fontSize: 11,
                        color: dark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                  ],
                ),
              ],
              if (e.userNote != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 11,
                      color: dark
                          ? Colors.white30
                          : Colors.black.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        e.userNote!,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: dark ? Colors.white38 : Colors.black38,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────── ACTIONS ───────────────────────

  // ─────────────────────── BACKGROUND CAPTURES ───────────────────────

  Widget _buildBgCaptureContent(bool dark) {
    final mono = GoogleFonts.spaceMono(
      fontSize: 11,
      color: dark ? Colors.white60 : Colors.black54,
    );
    final intervalMin = _bgConfig.interval.inMinutes;
    final lastCapture = _bgStats['last_capture'] ?? 'never';
    final successes = _bgStats['successes'] ?? '0';
    final failures = _bgStats['failures'] ?? '0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Status & stats
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _dbKv('Status', _bgConfig.enabled ? 'ON' : 'OFF', dark),
              _dbKv('Interval', '${intervalMin}m', dark),
              _dbKv('Total', '$_totalCaptures', dark),
              _dbKv('Background', '$_bgCaptures', dark),
              _dbKv('Successes', successes, dark),
              _dbKv('Failures', failures, dark),
            ],
          ),
        ),

        // ── Last capture time
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Text('Last bg capture: $lastCapture', style: mono),
        ),

        Divider(height: 1, color: dark ? Colors.white12 : Colors.black12),

        // ── Data source toggles
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'DATA SOURCES',
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _bgToggleRow(
          'Health',
          Icons.monitor_heart_outlined,
          _bgConfig.includeHealth,
          () => _toggleBgDataSource('health'),
          dark,
        ),
        _bgToggleRow(
          'Environment',
          Icons.cloud_outlined,
          _bgConfig.includeEnvironment,
          () => _toggleBgDataSource('environment'),
          dark,
        ),
        _bgToggleRow(
          'Location',
          Icons.location_on_outlined,
          _bgConfig.includeLocation,
          () => _toggleBgDataSource('location'),
          dark,
        ),
        _bgToggleRow(
          'Calendar',
          Icons.calendar_today_outlined,
          _bgConfig.includeCalendar,
          () => _toggleBgDataSource('calendar'),
          dark,
        ),
        Divider(height: 1, color: dark ? Colors.white12 : Colors.black12),

        // ── Interval selector
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'CAPTURE INTERVAL',
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final min in [15, 30, 60, 120, 240])
                _intervalChip(min, intervalMin == min, dark),
            ],
          ),
        ),

        Divider(height: 1, color: dark ? Colors.white12 : Colors.black12),

        // ── Quiet hours
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Icon(
                Icons.bedtime_outlined,
                size: 14,
                color: dark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 6),
              Text(
                'Quiet hours: '
                '${_bgConfig.quietHoursStartHour.toString().padLeft(2, '0')}:'
                '${_bgConfig.quietHoursStartMinute.toString().padLeft(2, '0')}'
                ' → '
                '${_bgConfig.quietHoursEndHour.toString().padLeft(2, '0')}:'
                '${_bgConfig.quietHoursEndMinute.toString().padLeft(2, '0')}',
                style: mono,
              ),
              const SizedBox(width: 8),
              _chip(
                _bgConfig.isInQuietHours() ? 'ACTIVE' : 'INACTIVE',
                _bgConfig.isInQuietHours() ? Colors.orange : Colors.green,
              ),
            ],
          ),
        ),

        Divider(height: 1, color: dark ? Colors.white12 : Colors.black12),

        // ── Recent captures list
        if (_recentCaptures.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'RECENT CAPTURES (${_recentCaptures.length})',
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white38 : Colors.black38,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ..._recentCaptures.map((c) => _buildCaptureRow(c, dark)),
          Divider(height: 1, color: dark ? Colors.white12 : Colors.black12),
        ],

        // ── Actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _actionButton(
                label: _bgConfig.enabled
                    ? 'Disable background captures'
                    : 'Enable background captures',
                icon: _bgConfig.enabled
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                color: _bgConfig.enabled ? Colors.orange : Colors.green,
                onTap: _actionRunning ? null : _toggleBgCapture,
              ),
              const SizedBox(height: 8),
              _actionButton(
                label: _bgTriggerRunning
                    ? 'Running capture…'
                    : 'Trigger capture now',
                icon: Icons.flash_on_outlined,
                color: Colors.cyan,
                onTap: (_actionRunning || _bgTriggerRunning)
                    ? null
                    : _triggerBgCaptureNow,
              ),
              const SizedBox(height: 8),
              _actionButton(
                label: 'Request notification permission',
                icon: Icons.notifications_active_outlined,
                color: Colors.indigo,
                onTap: _requestNotificationPermission,
              ),
              const SizedBox(height: 8),
              _actionButton(
                label: 'Reset capture stats',
                icon: Icons.restart_alt_outlined,
                color: Colors.red,
                onTap: _actionRunning ? null : _resetBgStats,
                destructive: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bgToggleRow(
    String label,
    IconData icon,
    bool value,
    VoidCallback onTap,
    bool dark,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: value
                  ? Colors.cyan
                  : (dark ? Colors.white24 : Colors.black26),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: dark ? Colors.white70 : Colors.black87,
              ),
            ),
            const Spacer(),
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: value
                  ? Colors.cyan
                  : (dark ? Colors.white24 : Colors.black26),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intervalChip(int minutes, bool selected, bool dark) {
    final label = minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h';
    return GestureDetector(
      onTap: () => _updateBgInterval(Duration(minutes: minutes)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? Colors.cyan.withValues(alpha: 0.2)
              : (dark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Colors.cyan.withValues(alpha: 0.6)
                : (dark ? Colors.white12 : Colors.black12),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceMono(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected
                ? Colors.cyan
                : (dark ? Colors.white54 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureRow(CaptureEntry capture, bool dark) {
    final fmt = DateFormat('MMM d HH:mm:ss');
    final isManual = capture.source == CaptureSource.manual;
    final sourceLabel = isManual ? 'MANUAL' : 'BG';
    final sourceColor = isManual ? Colors.blue : Colors.cyan;
    final durationMs = capture.executionDuration?.inMilliseconds;
    final hasErrors = capture.errors.isNotEmpty;

    // Data presence indicators
    final parts = <String>[];
    if (capture.healthData != null) parts.add('H');
    if (capture.environmentData != null) parts.add('E');
    if (capture.locationData != null) parts.add('L');
    if (capture.calendarEvents.isNotEmpty) parts.add('C');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Icon(
            hasErrors
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            size: 14,
            color: hasErrors ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmt.format(capture.timestamp),
                  style: GoogleFonts.spaceMono(
                    fontSize: 11,
                    color: dark ? Colors.white70 : Colors.black87,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      parts.join(' · '),
                      style: GoogleFonts.spaceMono(
                        fontSize: 9,
                        color: dark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    if (durationMs != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${durationMs}ms',
                        style: GoogleFonts.spaceMono(
                          fontSize: 9,
                          color: dark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _chip(sourceLabel, sourceColor),
        ],
      ),
    );
  }

  // ─────────────────────── DAILY NOTIFICATIONS ───────────────────────

  Widget _buildDailyNotifContent(bool dark) {
    final timeStr =
        '${_dailyReminderTime.hour.toString().padLeft(2, '0')}:'
        '${_dailyReminderTime.minute.toString().padLeft(2, '0')}';
    const accent = Color(0xFFA68BC1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status
          Row(
            children: [
              Icon(
                _dailyReminderEnabled
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 16,
                color: _dailyReminderEnabled ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                _dailyReminderEnabled
                    ? 'Daily body blog push is active'
                    : 'Daily notification is off',
                style: TextStyle(
                  fontSize: 12,
                  color: dark
                      ? Colors.white70
                      : Colors.black.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Time display & picker
          Row(
            children: [
              Text(
                'SCHEDULED TIME',
                style: GoogleFonts.spaceMono(
                  fontSize: 9,
                  color: dark ? Colors.white38 : Colors.black38,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _pickDailyReminderTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 13, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: GoogleFonts.spaceMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Sample message preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark
                  ? accent.withValues(alpha: 0.08)
                  : accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.format_quote, size: 12, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Sample message',
                      style: GoogleFonts.spaceMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  NotificationService.dailyMessages.first.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  NotificationService.dailyMessages.first.body,
                  style: TextStyle(
                    fontSize: 11,
                    color: dark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Actions
          _actionButton(
            label: _dailyReminderEnabled
                ? 'Disable daily reminder'
                : 'Enable daily reminder',
            icon: _dailyReminderEnabled
                ? Icons.notifications_off_outlined
                : Icons.notifications_active_outlined,
            color: _dailyReminderEnabled ? Colors.orange : Colors.green,
            onTap: _toggleDailyReminder,
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Send test notification now',
            icon: Icons.send_outlined,
            color: accent,
            onTap: _sendTestDailyNotification,
          ),
        ],
      ),
    );
  }

  // ─────────────────────── ACTIONS ───────────────────────

  Widget _buildActionsContent(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _actionButton(
            label: 'Force refresh today\'s entry',
            icon: Icons.autorenew,
            color: Colors.teal,
            onTap: _actionRunning ? null : _forceRefreshEntry,
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Copy context window',
            icon: Icons.copy_outlined,
            color: Colors.purple,
            onTap: _copyContext,
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Re-request all permissions',
            icon: Icons.policy_outlined,
            color: Colors.orange,
            onTap: _actionRunning ? null : _requestAllPermissions,
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Open app settings',
            icon: Icons.settings_outlined,
            color: Colors.blue,
            onTap: _openSettings,
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Clear all database entries',
            icon: Icons.delete_sweep_outlined,
            color: Colors.red,
            onTap: _actionRunning ? null : _clearDb,
            destructive: true,
          ),
        ],
      ),
    );
  }

  // ─────────────────────── ACTION TOAST ───────────────────────

  Widget _buildToast(bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? Colors.white12 : Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _actionMessage ?? '',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _actionMessage = null),
            child: Icon(
              Icons.close,
              size: 14,
              color: dark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── HELPERS ───────────────────────

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: GoogleFonts.spaceMono(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _statusBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label.toUpperCase(),
      style: GoogleFonts.spaceMono(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  Widget _tinyButton({
    required String label,
    required Color color,
    VoidCallback? onTap,
    IconData? icon,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool destructive = false,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: destructive ? 0.08 : 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: destructive ? 0.35 : 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: onTap == null ? color.withValues(alpha: 0.35) : color,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: onTap == null ? color.withValues(alpha: 0.35) : color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _miniStat(String emoji, String value) =>
      Text('$emoji $value', style: const TextStyle(fontSize: 11));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Permission status model
// ─────────────────────────────────────────────────────────────────────────────

class _PermStatus {
  final IconData icon;
  final String label;
  final String description;
  final PermissionStatus? status;
  final bool? statusOverride; // for health (not a PermissionStatus)

  const _PermStatus({
    required this.icon,
    required this.label,
    required this.description,
    this.status,
    this.statusOverride,
  });

  bool get isGranted => statusOverride ?? (status == PermissionStatus.granted);

  bool get isPermanentlyDenied => status == PermissionStatus.permanentlyDenied;

  String get statusLabel {
    if (statusOverride != null) {
      return statusOverride! ? 'granted' : 'denied';
    }
    if (status == null) return 'unknown';
    switch (status!) {
      case PermissionStatus.granted:
        return 'granted';
      case PermissionStatus.denied:
        return 'denied';
      case PermissionStatus.permanentlyDenied:
        return 'blocked';
      case PermissionStatus.restricted:
        return 'restricted';
      case PermissionStatus.limited:
        return 'limited';
      case PermissionStatus.provisional:
        return 'provisional';
    }
  }

  Color get statusColor {
    if (isGranted) return Colors.green;
    if (status == PermissionStatus.permanentlyDenied ||
        status == PermissionStatus.restricted) {
      return Colors.red;
    }
    return Colors.orange;
  }
}
