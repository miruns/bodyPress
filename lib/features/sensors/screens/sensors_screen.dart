import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/service_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sensors & State — live dashboard of every data source the app relies on
// ─────────────────────────────────────────────────────────────────────────────

class SensorsScreen extends ConsumerStatefulWidget {
  const SensorsScreen({super.key});

  @override
  ConsumerState<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends ConsumerState<SensorsScreen> {
  bool _loading = true;
  final List<_SensorGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _probe();
  }

  /// Probe every sensor subsystem in parallel and build the status model.
  Future<void> _probe() async {
    setState(() => _loading = true);

    final health = ref.read(healthServiceProvider);
    final location = ref.read(locationServiceProvider);
    final ambient = ref.read(ambientScanServiceProvider);
    final calendar = ref.read(calendarServiceProvider);
    final ble = ref.read(bleHeartRateServiceProvider);

    // ── Run all probes in parallel ─────────────────────────────────────────
    final results = await Future.wait([
      _probeHealth(health), // 0
      _probeLocation(location), // 1
      _probeAmbient(ambient), // 2
      _probeCalendar(calendar), // 3
      _probeBle(ble), // 4
      _probePermissions(), // 5
    ]);

    if (!mounted) return;

    setState(() {
      _groups
        ..clear()
        ..addAll(results);
      _loading = false;
    });
  }

  // ── Individual probes ──────────────────────────────────────────────────────

  Future<_SensorGroup> _probeHealth(dynamic health) async {
    final items = <_SensorItem>[];
    try {
      final available = await health.isHealthAvailable();
      items.add(
        _SensorItem(
          label: 'Platform',
          value: available ? 'Available' : 'Not available',
          state: available ? _SensorState.active : _SensorState.unavailable,
        ),
      );

      if (available) {
        final hasPerms = await health.hasPermissionsProbe();
        items.add(
          _SensorItem(
            label: 'Permissions',
            value: hasPerms ? 'Granted' : 'Not granted',
            state: hasPerms ? _SensorState.active : _SensorState.denied,
          ),
        );

        if (hasPerms) {
          final steps = await health.getTodaySteps();
          items.add(
            _SensorItem(
              label: 'Steps today',
              value: '$steps',
              state: steps > 0 ? _SensorState.active : _SensorState.idle,
            ),
          );
          final hr = await health.getTodayAverageHeartRate();
          items.add(
            _SensorItem(
              label: 'Avg heart rate',
              value: hr > 0 ? '$hr bpm' : '—',
              state: hr > 0 ? _SensorState.active : _SensorState.idle,
            ),
          );
          final sleep = await health.getLastNightSleep();
          items.add(
            _SensorItem(
              label: 'Sleep',
              value: sleep > 0 ? '${sleep.toStringAsFixed(1)} h' : '—',
              state: sleep > 0 ? _SensorState.active : _SensorState.idle,
            ),
          );
          final calories = await health.getTodayCalories();
          items.add(
            _SensorItem(
              label: 'Calories',
              value: calories > 0 ? '${calories.toStringAsFixed(0)} kcal' : '—',
              state: calories > 0 ? _SensorState.active : _SensorState.idle,
            ),
          );
          final workouts = await health.getTodayWorkoutCount();
          items.add(
            _SensorItem(
              label: 'Workouts',
              value: workouts > 0
                  ? '$workouts session${workouts > 1 ? "s" : ""}'
                  : '—',
              state: workouts > 0 ? _SensorState.active : _SensorState.idle,
            ),
          );
        }
      }
    } catch (e) {
      items.add(
        _SensorItem(label: 'Error', value: '$e', state: _SensorState.error),
      );
    }
    return _SensorGroup(
      title: 'Health',
      icon: Icons.monitor_heart_outlined,
      items: items,
    );
  }

  Future<_SensorGroup> _probeLocation(dynamic location) async {
    final items = <_SensorItem>[];
    try {
      final enabled = await location.isLocationServiceEnabled();
      items.add(
        _SensorItem(
          label: 'Location services',
          value: enabled ? 'Enabled' : 'Disabled',
          state: enabled ? _SensorState.active : _SensorState.unavailable,
        ),
      );
      if (enabled) {
        final pos = await location.getCurrentLocation().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
        if (pos != null) {
          items.add(
            _SensorItem(
              label: 'Latitude',
              value: pos.latitude.toStringAsFixed(4),
              state: _SensorState.active,
            ),
          );
          items.add(
            _SensorItem(
              label: 'Longitude',
              value: pos.longitude.toStringAsFixed(4),
              state: _SensorState.active,
            ),
          );
          items.add(
            _SensorItem(
              label: 'Accuracy',
              value: '${pos.accuracy.toStringAsFixed(0)} m',
              state: _SensorState.active,
            ),
          );
        } else {
          items.add(
            _SensorItem(
              label: 'Position',
              value: 'Unavailable',
              state: _SensorState.idle,
            ),
          );
        }
      }
    } catch (e) {
      items.add(
        _SensorItem(label: 'Error', value: '$e', state: _SensorState.error),
      );
    }
    return _SensorGroup(
      title: 'Location (GPS)',
      icon: Icons.location_on_outlined,
      items: items,
    );
  }

  Future<_SensorGroup> _probeAmbient(dynamic ambient) async {
    final items = <_SensorItem>[];
    try {
      final available = await ambient.isAvailable();
      items.add(
        _SensorItem(
          label: 'Ambient API',
          value: available ? 'Reachable' : 'Unreachable',
          state: available ? _SensorState.active : _SensorState.unavailable,
        ),
      );
    } catch (e) {
      items.add(
        _SensorItem(label: 'Error', value: '$e', state: _SensorState.error),
      );
    }
    return _SensorGroup(
      title: 'Ambient / Weather',
      icon: Icons.thermostat_outlined,
      items: items,
    );
  }

  Future<_SensorGroup> _probeCalendar(dynamic calendar) async {
    final items = <_SensorItem>[];
    try {
      final hasPerms = await calendar.hasPermissions();
      items.add(
        _SensorItem(
          label: 'Permission',
          value: hasPerms ? 'Granted' : 'Not granted',
          state: hasPerms ? _SensorState.active : _SensorState.denied,
        ),
      );
      if (hasPerms) {
        final calendars = await calendar.getCalendars();
        items.add(
          _SensorItem(
            label: 'Calendars found',
            value: '${calendars.length}',
            state: calendars.isNotEmpty
                ? _SensorState.active
                : _SensorState.idle,
          ),
        );
      }
    } catch (e) {
      items.add(
        _SensorItem(label: 'Error', value: '$e', state: _SensorState.error),
      );
    }
    return _SensorGroup(
      title: 'Calendar',
      icon: Icons.event_outlined,
      items: items,
    );
  }

  Future<_SensorGroup> _probeBle(dynamic ble) async {
    final items = <_SensorItem>[];
    try {
      final state = ble.state;
      items.add(
        _SensorItem(
          label: 'Connection',
          value: state.name.replaceAll('_', ' '),
          state: state.name == 'streaming'
              ? _SensorState.active
              : state.name == 'connected'
              ? _SensorState.active
              : _SensorState.idle,
        ),
      );
    } catch (e) {
      items.add(
        _SensorItem(label: 'Error', value: '$e', state: _SensorState.error),
      );
    }
    return _SensorGroup(
      title: 'BLE Heart Rate',
      icon: Icons.bluetooth_outlined,
      items: items,
    );
  }

  Future<_SensorGroup> _probePermissions() async {
    final items = <_SensorItem>[];
    try {
      final perms = await Future.wait([
        Permission.location.status,
        Permission.activityRecognition.status,
        Permission.sensors.status,
        Permission.calendarFullAccess.status,
        Permission.notification.status,
      ]);
      final labels = [
        'Location',
        'Activity Recognition',
        'Body Sensors',
        'Calendar',
        'Notifications',
      ];
      for (var i = 0; i < perms.length; i++) {
        items.add(
          _SensorItem(
            label: labels[i],
            value: _permLabel(perms[i]),
            state: perms[i].isGranted
                ? _SensorState.active
                : perms[i].isDenied
                ? _SensorState.denied
                : _SensorState.unavailable,
          ),
        );
      }
    } catch (e) {
      items.add(
        _SensorItem(label: 'Error', value: '$e', state: _SensorState.error),
      );
    }
    return _SensorGroup(
      title: 'Permissions',
      icon: Icons.shield_outlined,
      items: items,
    );
  }

  String _permLabel(PermissionStatus s) {
    if (s.isGranted) return 'Granted';
    if (s.isDenied) return 'Denied';
    if (s.isPermanentlyDenied) return 'Permanently denied';
    if (s.isRestricted) return 'Restricted';
    if (s.isLimited) return 'Limited';
    return 'Unknown';
  }

  // ── Fix permissions ────────────────────────────────────────────────────────

  /// Open app settings so the user can grant all missing permissions, then
  /// re-probe sensors to refresh the UI.
  Future<void> _fixAllPermissions() async {
    // First try requesting permissions directly
    final health = ref.read(healthServiceProvider);
    await health.requestAuthorization();
    await [
      Permission.location,
      Permission.activityRecognition,
      Permission.sensors,
      Permission.calendarFullAccess,
      Permission.notification,
    ].request();
    // If anything is still permanently denied, open system settings
    await openAppSettings();
    // Re-probe after returning from settings
    if (mounted) {
      ref.invalidate(healthPermissionStatusProvider);
      await _probe();
    }
  }

  /// Fix permissions for a specific sensor group.
  Future<void> _fixGroupPermission(_SensorGroup group) async {
    switch (group.title) {
      case 'Health':
        final health = ref.read(healthServiceProvider);
        await health.requestAuthorization();
        // Also try opening Health Connect / Apple Health settings
        await health.openHealthConnectApp();
      case 'Location (GPS)':
        final status = await Permission.location.request();
        if (status.isPermanentlyDenied) await openAppSettings();
      case 'Calendar':
        final status = await Permission.calendarFullAccess.request();
        if (status.isPermanentlyDenied) await openAppSettings();
      case 'Permissions':
        await _fixAllPermissions();
        return; // _fixAllPermissions already re-probes
      default:
        await openAppSettings();
    }
    if (mounted) {
      ref.invalidate(healthPermissionStatusProvider);
      await _probe();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Sensors & State',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Re-probe all sensors',
            onPressed: _loading ? null : _probe,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _probe,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // ── Sensor guidance tips ──
                  if (_groups.any((g) => g.overallState != _SensorState.active))
                    _SensorGuidanceCard(groups: _groups, dark: dark),
                  // ── Fix All Permissions banner ──
                  if (_groups.any((g) => g.hasDenied))
                    _FixAllPermissionsBanner(
                      dark: dark,
                      onFix: _fixAllPermissions,
                    ),
                  // ── Sensor groups ──
                  ..._groups.map(
                    (g) => _SensorGroupCard(
                      group: g,
                      dark: dark,
                      onFixPermission: g.hasDenied
                          ? () => _fixGroupPermission(g)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Data models
// ═════════════════════════════════════════════════════════════════════════════

enum _SensorState { active, idle, denied, unavailable, error }

class _SensorItem {
  final String label;
  final String value;
  final _SensorState state;

  const _SensorItem({
    required this.label,
    required this.value,
    required this.state,
  });
}

class _SensorGroup {
  final String title;
  final IconData icon;
  final List<_SensorItem> items;

  const _SensorGroup({
    required this.title,
    required this.icon,
    required this.items,
  });

  /// Overall group health — the best state among its items.
  _SensorState get overallState {
    if (items.any((i) => i.state == _SensorState.error)) {
      return _SensorState.error;
    }
    if (items.any((i) => i.state == _SensorState.active)) {
      return _SensorState.active;
    }
    if (items.any((i) => i.state == _SensorState.idle)) {
      return _SensorState.idle;
    }
    if (items.any((i) => i.state == _SensorState.denied)) {
      return _SensorState.denied;
    }
    return _SensorState.unavailable;
  }

  /// Whether any item in this group has denied permissions.
  bool get hasDenied => items.any((i) => i.state == _SensorState.denied);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Widgets
// ═════════════════════════════════════════════════════════════════════════════

class _SensorGroupCard extends StatelessWidget {
  const _SensorGroupCard({
    required this.group,
    required this.dark,
    this.onFixPermission,
  });
  final _SensorGroup group;
  final bool dark;
  final VoidCallback? onFixPermission;

  @override
  Widget build(BuildContext context) {
    final accent = _stateColor(group.overallState);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── header ──────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(group.icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    group.title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StateBadge(state: group.overallState),
              ],
            ),
            const SizedBox(height: 14),
            // ── items ───────────────────────────────────────────────────
            ...group.items.map((item) => _SensorRow(item: item, dark: dark)),
            // ── fix permission button ────────────────────────────────────
            if (onFixPermission != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onFixPermission,
                  icon: const Icon(Icons.build_rounded, size: 16),
                  label: Text(
                    'Fix permissions',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFBD5A),
                    side: const BorderSide(color: Color(0xFFFFBD5A), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({required this.item, required this.dark});
  final _SensorItem item;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _stateColor(item.state),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: dark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});
  final _SensorState state;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _stateLabel(state),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Color _stateColor(_SensorState s) {
  switch (s) {
    case _SensorState.active:
      return const Color(0xFF38C87E); // seaGreen
    case _SensorState.idle:
      return const Color(0xFFFFBD5A); // amber
    case _SensorState.denied:
      return const Color(0xFFFF5A7A); // crimson
    case _SensorState.unavailable:
      return const Color(0xFF60758F); // fog
    case _SensorState.error:
      return const Color(0xFFFF5A7A); // crimson
  }
}

String _stateLabel(_SensorState s) {
  switch (s) {
    case _SensorState.active:
      return 'Active';
    case _SensorState.idle:
      return 'Idle';
    case _SensorState.denied:
      return 'Denied';
    case _SensorState.unavailable:
      return 'Unavailable';
    case _SensorState.error:
      return 'Error';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  FIX ALL PERMISSIONS BANNER — prominent CTA at top of sensor list
// ═════════════════════════════════════════════════════════════════════════════

class _FixAllPermissionsBanner extends StatelessWidget {
  const _FixAllPermissionsBanner({required this.dark, required this.onFix});
  final bool dark;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFBD5A);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF2A2210), const Color(0xFF1E1A10)]
              : [const Color(0xFFFFF8E8), const Color(0xFFFFF3D6)],
        ),
        border: Border.all(color: accent.withValues(alpha: dark ? 0.25 : 0.30)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Some permissions are missing',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Grant access so your body story is complete',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: dark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onFix,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Fix all',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SENSOR GUIDANCE CARD — contextual tips when sensors are not all active
// ═════════════════════════════════════════════════════════════════════════════

class _GuidanceTip {
  const _GuidanceTip({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String message;
}

class _SensorGuidanceCard extends StatelessWidget {
  const _SensorGuidanceCard({required this.groups, required this.dark});
  final List<_SensorGroup> groups;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final denied = groups
        .where((g) => g.overallState == _SensorState.denied)
        .map((g) => g.title)
        .toList();
    final unavailable = groups
        .where((g) => g.overallState == _SensorState.unavailable)
        .map((g) => g.title)
        .toList();
    final idle = groups
        .where((g) => g.overallState == _SensorState.idle)
        .map((g) => g.title)
        .toList();
    final errored = groups
        .where((g) => g.overallState == _SensorState.error)
        .map((g) => g.title)
        .toList();

    final tips = <_GuidanceTip>[];

    if (denied.isNotEmpty) {
      tips.add(
        _GuidanceTip(
          icon: Icons.lock_outline_rounded,
          color: const Color(0xFFFF5A7A),
          title: 'Permissions needed',
          message:
              '${denied.join(", ")} — grant access so your body story is complete.',
        ),
      );
    }
    if (errored.isNotEmpty) {
      tips.add(
        _GuidanceTip(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFFF5A7A),
          title: 'Errors detected',
          message:
              '${errored.join(", ")} — try re-probing or restarting the app.',
        ),
      );
    }
    if (unavailable.isNotEmpty) {
      tips.add(
        _GuidanceTip(
          icon: Icons.cloud_off_rounded,
          color: const Color(0xFF60758F),
          title: 'Unavailable',
          message: '${unavailable.join(", ")} — not available on this device.',
        ),
      );
    }
    if (idle.isNotEmpty) {
      tips.add(
        _GuidanceTip(
          icon: Icons.hourglass_empty_rounded,
          color: const Color(0xFFFFBD5A),
          title: 'Waiting for data',
          message:
              '${idle.join(", ")} — try syncing your wearable or moving around.',
        ),
      );
    }

    if (tips.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: dark ? const Color(0xFF1A1F2B) : const Color(0xFFF5F6FA),
        border: Border.all(color: (dark ? Colors.white10 : Colors.black12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: dark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 8),
              Text(
                'SENSOR GUIDANCE',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white38 : Colors.black38,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tip.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tip.title,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tip.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tip.message,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: dark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
