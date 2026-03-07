import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/service_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding — Zen-inspired, step-by-step permission flow
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // 6 pages: welcome · location · health · calendar · notifications · complete
  static const _totalPages = 6;
  static const _permSteps = 4;

  final _pageCtrl = PageController();
  late final _permissionService = ref.read(permissionServiceProvider);
  late final _healthService = ref.read(healthServiceProvider);
  late final _dbService = ref.read(localDbServiceProvider);
  late final _notifService = ref.read(notificationServiceProvider);

  int _page = 0;
  bool _busy = false;
  bool _healthPhase2 = false;

  late final AnimationController _breathe;

  // ── lifecycle ──────────────────────────────────────────────────

  /// Whether we're waiting for the user to grant access inside Health Connect.
  bool _awaitingHealthConnect = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageCtrl.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingHealthConnect) {
      _recheckHealthPermissions();
    }
  }

  /// Re-check health permissions after returning from Health Connect.
  Future<void> _recheckHealthPermissions() async {
    _awaitingHealthConnect = false;
    setState(() => _busy = true);
    try {
      final granted = await _healthService.hasPermissions().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _healthPhase2 = !granted;
      });
      if (granted) _next();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── navigation ────────────────────────────────────────────────

  void _next() {
    if (_page < _totalPages - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _finish() => context.go('/journal');

  /// Skip this time only — go straight to journal.
  void _skip() => context.go('/journal');

  /// Persist the skip preference and go to journal.
  Future<void> _dontShowAgain() async {
    await _dbService.setSetting('skip_onboarding', 'true');
    if (mounted) context.go('/journal');
  }

  // ── permission helpers ────────────────────────────────────────

  Future<void> _requestLocation() async {
    setState(() => _busy = true);
    try {
      await _permissionService.requestLocationPermission().timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
    _next();
  }

  Future<void> _requestHealth() async {
    setState(() => _busy = true);
    try {
      await _permissionService.requestActivityRecognitionPermission().timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      await _permissionService.requestSensorsPermission().timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      await _healthService.requestAuthorization().timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {}

    // Check whether health permissions are actually granted now.
    final granted = await _healthService.hasPermissions().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );

    if (!mounted) return;
    if (granted) {
      setState(() => _busy = false);
      _next();
    } else {
      // Android: Health Connect permissions require the user to open the app
      // and explicitly allow access there. Show the follow-up phase instead of
      // silently advancing.
      setState(() {
        _busy = false;
        _healthPhase2 = true;
      });
    }
  }

  /// Opens Health Connect so the user can finish granting data access.
  /// The lifecycle observer will re-check permissions when the user returns.
  Future<void> _openHealthConnect() async {
    setState(() => _busy = true);
    try {
      _awaitingHealthConnect = true;
      await _healthService.openHealthConnectApp();
      // The future resolves immediately on Android because it just launches
      // an external activity. The actual permission check happens in
      // didChangeAppLifecycleState when the user comes back.
    } catch (_) {
      _awaitingHealthConnect = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCalendar() async {
    setState(() => _busy = true);
    try {
      await _permissionService.requestCalendarPermission().timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
    _next();
  }

  Future<void> _enableDailyReminder() async {
    setState(() => _busy = true);
    try {
      await _notifService.initialize();
      await _notifService.requestPermission();
      await _notifService.scheduleDailyReminders();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
    _next();
  }

  // ── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // ── progress bar (only on perm steps) ──
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (_page >= 1 && _page <= _permSteps)
                    ? _StepBar(
                        key: const ValueKey('bar'),
                        step: _page,
                        total: _permSteps,
                        accent: Theme.of(context).colorScheme.primary,
                        onSkip: _busy ? null : _next,
                      )
                    : const SizedBox.shrink(key: ValueKey('nobar')),
              ),

              // ── pages ──
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _WelcomePage(
                      onBegin: _next,
                      onSkip: _skip,
                      onDontShowAgain: _dontShowAgain,
                      breathe: _breathe,
                    ),
                    _PermissionStep(
                      icon: Icons.explore_outlined,
                      accent: const Color(0xFF6B8E6B),
                      title: 'Environmental\nAwareness',
                      subtitle: 'LOCATION ACCESS',
                      body:
                          'BodyPress uses your GPS coordinates to fetch local '
                          'environmental data — weather conditions, air quality, '
                          'UV index, and altitude.\n\n'
                          'This helps you understand how your surroundings '
                          'influence your body and overall wellness.',
                      privacy:
                          'Your location is never tracked, stored, or shared. '
                          'We only read it in the moment to pull environmental data.',
                      ctaLabel: 'Allow Location',
                      onAllow: _requestLocation,
                      onSkip: _next,
                      busy: _busy,
                      breathe: _breathe,
                    ),
                    _HealthPermissionStep(
                      accent: const Color(0xFFD4738A),
                      onAllow: _requestHealth,
                      onSkip: _next,
                      busy: _busy,
                      breathe: _breathe,
                      showPhase2: _healthPhase2,
                      onOpenHealthConnect: _openHealthConnect,
                    ),
                    _PermissionStep(
                      icon: Icons.event_outlined,
                      accent: const Color(0xFF7B8EC4),
                      title: 'Mindful\nScheduling',
                      subtitle: 'CALENDAR ACCESS',
                      body:
                          'Calendar integration helps you plan wellness '
                          'routines, set mindful reminders, and maintain a '
                          'consistent rhythm in your health journey.\n\n'
                          'See how your daily agenda aligns with your '
                          'body\'s needs.',
                      privacy:
                          'We only read your calendar for context — '
                          'nothing is modified, copied, or shared.',
                      ctaLabel: 'Allow Calendar',
                      onAllow: _requestCalendar,
                      onSkip: _next,
                      busy: _busy,
                      breathe: _breathe,
                    ),
                    _NotificationStep(
                      accent: const Color(0xFFA68BC1),
                      onEnable: _enableDailyReminder,
                      onSkip: _next,
                      busy: _busy,
                      breathe: _breathe,
                    ),
                    _CompletePage(onEnter: _finish, breathe: _breathe),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PROGRESS BAR
// ═════════════════════════════════════════════════════════════════════════════

class _StepBar extends StatelessWidget {
  const _StepBar({
    super.key,
    required this.step,
    required this.total,
    required this.accent,
    this.onSkip,
  });

  final int step;
  final int total;
  final Color accent;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step $step of $total',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[500],
                  letterSpacing: 1.0,
                ),
              ),
              GestureDetector(
                onTap: onSkip,
                child: Text(
                  'Skip',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: accent.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (step / total).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.grey.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  WELCOME PAGE
// ═════════════════════════════════════════════════════════════════════════════

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({
    required this.onBegin,
    required this.onSkip,
    required this.onDontShowAgain,
    required this.breathe,
  });

  final VoidCallback onBegin;
  final VoidCallback onSkip;
  final VoidCallback onDontShowAgain;
  final AnimationController breathe;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 3),

          // ── zen orb ──
          _ZenOrb(
            size: 180,
            color: primary,
            breathe: breathe,
            child: Icon(Icons.spa_outlined, size: 48, color: primary),
          ),

          const Spacer(flex: 2),

          // ── branding ──
          Text(
            'BodyPress',
            style: GoogleFonts.playfairDisplay(
              fontSize: 44,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your mindful body companion',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w300,
              color: Colors.grey[500],
              letterSpacing: 0.8,
            ),
          ),

          const SizedBox(height: 28),
          Container(
            width: 48,
            height: 1,
            color: Colors.grey.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 28),

          // ── philosophy ──
          Text(
            'Tune into your body\'s signals.\n'
            'Understand your environment.\n'
            'Live with intention.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.85,
              fontWeight: FontWeight.w300,
              color: dark ? Colors.white60 : Colors.black45,
            ),
          ),

          const Spacer(flex: 3),

          // ── CTA ──
          _PillButton(label: 'Begin', color: primary, onPressed: onBegin),

          const SizedBox(height: 16),

          // ── Skip / Don't show again ──
          GestureDetector(
            onTap: onSkip,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                'Skip',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PERMISSION STEP (reusable for each permission)
// ═════════════════════════════════════════════════════════════════════════════

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.privacy,
    required this.ctaLabel,
    required this.onAllow,
    required this.onSkip,
    required this.busy,
    required this.breathe,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String body;
  final String privacy;
  final String ctaLabel;
  final VoidCallback onAllow;
  final VoidCallback onSkip;
  final bool busy;
  final AnimationController breathe;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // ── scrollable content ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 36),

                // orb
                _ZenOrb(
                  size: 140,
                  color: accent,
                  breathe: breathe,
                  child: Icon(icon, size: 42, color: accent),
                ),

                const SizedBox(height: 36),

                // title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),

                const SizedBox(height: 10),

                // subtitle label
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    color: accent.withValues(alpha: 0.8),
                  ),
                ),

                const SizedBox(height: 28),

                // body
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.75,
                    fontWeight: FontWeight.w300,
                    color: dark ? Colors.white60 : Colors.black54,
                  ),
                ),

                const SizedBox(height: 24),

                // privacy note
                _PrivacyNote(text: privacy, accent: accent),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── pinned buttons ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              _PillButton(
                label: ctaLabel,
                color: accent,
                onPressed: busy ? null : onAllow,
                busy: busy,
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: busy ? null : onSkip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Not now',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  HEALTH PERMISSION STEP  (OS-aware, 2-phase)
// ═════════════════════════════════════════════════════════════════════════════

class _HealthPermissionStep extends StatelessWidget {
  const _HealthPermissionStep({
    required this.accent,
    required this.onAllow,
    required this.onSkip,
    required this.busy,
    required this.breathe,
    this.showPhase2 = false,
    this.onOpenHealthConnect,
  });

  final Color accent;
  final VoidCallback onAllow;
  final VoidCallback onSkip;
  final bool busy;
  final AnimationController breathe;

  /// Android only — true after the OS dialog was shown but Health Connect
  /// permissions were not yet granted.
  final bool showPhase2;

  /// Opens the Health Connect app so the user can finish granting access.
  final VoidCallback? onOpenHealthConnect;

  bool get _isIOS => Platform.isIOS;

  String get _platformName => _isIOS ? 'Apple Health' : 'Health Connect';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // ── Android phase 2 ──────────────────────────────────────────────────────
    // The OS "Physical activity" dialog was shown, but Health Connect still
    // needs to be opened to grant the actual data-type permissions.
    if (showPhase2 && !_isIOS) {
      return _AndroidHealthConnectPhase2(
        accent: accent,
        breathe: breathe,
        busy: busy,
        onOpenHealthConnect: onOpenHealthConnect ?? onSkip,
        onContinueAnyhow: onSkip,
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 36),

                // Health orb with custom inner illustration
                _HealthOrb(size: 140, accent: accent, breathe: breathe),

                const SizedBox(height: 36),

                Text(
                  'Body\nIntelligence',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),

                const SizedBox(height: 10),

                // OS-specific subtitle badge
                _OsBadge(
                  label: 'HEALTH DATA ACCESS',
                  platformName: _platformName,
                  accent: accent,
                  isIOS: _isIOS,
                ),

                const SizedBox(height: 28),

                Text(
                  _isIOS
                      ? 'BodyPress reads your steps, heart rate, sleep '
                            'patterns, calories, and workouts from Apple Health.\n\n'
                            'This paints a holistic picture of your daily vitality '
                            'so you can make informed choices.'
                      : 'Connecting Google Health Connect lets BodyPress read '
                            'your steps, heart rate, sleep, calories, and workouts.\n\n'
                            'This paints a holistic picture of your daily vitality '
                            'so you can make informed choices.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.75,
                    fontWeight: FontWeight.w300,
                    color: dark ? Colors.white60 : Colors.black54,
                  ),
                ),

                // Android: show a concise 2-step heads-up before they tap
                if (!_isIOS) ...[
                  const SizedBox(height: 24),
                  _AndroidTwoStepNote(accent: accent),
                ],

                const SizedBox(height: 24),

                _PrivacyNote(
                  text:
                      'Health data stays on your device. '
                      'We only read — never write or upload.',
                  accent: accent,
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // Pinned CTAs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              _PillButton(
                label: 'Allow $_platformName',
                color: accent,
                onPressed: busy ? null : onAllow,
                busy: busy,
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: busy ? null : onSkip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Not now',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Android helpers — shown in _HealthPermissionStep
// ─────────────────────────────────────────────────────────────────────────────

/// Inline note that explains the Android 2-step process BEFORE the user taps
/// "Allow Health Connect".
class _AndroidTwoStepNote extends StatelessWidget {
  const _AndroidTwoStepNote({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: dark ? 0.18 : 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: accent),
              const SizedBox(width: 6),
              Text(
                'HOW IT WORKS ON ANDROID',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AndroidStep(
            number: '1',
            accent: accent,
            label: 'Allow "Physical activity" in the system dialog',
          ),
          const SizedBox(height: 8),
          _AndroidStep(
            number: '2',
            accent: accent,
            label: 'Open Health Connect → tap BodyPress → allow data access',
          ),
        ],
      ),
    );
  }
}

class _AndroidStep extends StatelessWidget {
  const _AndroidStep({
    required this.number,
    required this.accent,
    required this.label,
  });

  final String number;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w400,
              color: dark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown on Android after the OS dialog if Health Connect permissions
/// were not fully granted yet. Guides the user through the second step.
class _AndroidHealthConnectPhase2 extends StatelessWidget {
  const _AndroidHealthConnectPhase2({
    required this.accent,
    required this.breathe,
    required this.busy,
    required this.onOpenHealthConnect,
    required this.onContinueAnyhow,
  });

  final Color accent;
  final AnimationController breathe;
  final bool busy;
  final VoidCallback onOpenHealthConnect;
  final VoidCallback onContinueAnyhow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 36),

                _HealthOrb(size: 140, accent: accent, breathe: breathe),

                const SizedBox(height: 36),

                Text(
                  'One more\nstep',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'HEALTH CONNECT',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    color: accent.withValues(alpha: 0.8),
                  ),
                ),

                const SizedBox(height: 28),

                // Step 1 — already done
                _Phase2Row(
                  number: '1',
                  accent: accent,
                  done: true,
                  label: '"Physical activity" system permission',
                  sublabel: 'Granted',
                ),

                const SizedBox(height: 12),

                // Step 2 — pending
                _Phase2Row(
                  number: '2',
                  accent: accent,
                  done: false,
                  label: 'Health Connect data access',
                  sublabel: 'Tap BodyPress → allow steps, heart rate, sleep…',
                ),

                const SizedBox(height: 28),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: dark ? 0.07 : 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: accent.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tap the button below → Health Connect will open → '
                          'find BodyPress in the app list → allow access.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.55,
                            fontWeight: FontWeight.w300,
                            color: dark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // Pinned CTAs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              _PillButton(
                label: 'Open Health Connect',
                color: accent,
                onPressed: busy ? null : onOpenHealthConnect,
                busy: busy,
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: busy ? null : onContinueAnyhow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Skip for now',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }
}

class _Phase2Row extends StatelessWidget {
  const _Phase2Row({
    required this.number,
    required this.accent,
    required this.done,
    required this.label,
    required this.sublabel,
  });

  final String number;
  final Color accent;
  final bool done;
  final String label;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dimColor = dark ? Colors.white38 : Colors.black26;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? const Color(0xFF6BAE6B).withValues(alpha: 0.15)
                : accent.withValues(alpha: 0.12),
          ),
          child: Center(
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Color(0xFF6BAE6B),
                  )
                : Text(
                    number,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: done
                      ? dimColor
                      : (dark ? Colors.white : Colors.black87),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w300,
                  color: done
                      ? const Color(0xFF6BAE6B).withValues(alpha: 0.8)
                      : (dark ? Colors.white54 : Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Health orb — custom ECG-line illustration
// ─────────────────────────────────────────────────────────────────────────────

class _HealthOrb extends StatelessWidget {
  const _HealthOrb({
    required this.size,
    required this.accent,
    required this.breathe,
  });

  final double size;
  final Color accent;
  final AnimationController breathe;

  @override
  Widget build(BuildContext context) {
    return _ZenOrb(
      size: size,
      color: accent,
      breathe: breathe,
      child: CustomPaint(
        size: Size(size * 0.44, size * 0.44),
        painter: _EcgHeartPainter(color: accent),
      ),
    );
  }
}

/// Draws a stylised heart shape with a tiny ECG blip inside it.
class _EcgHeartPainter extends CustomPainter {
  const _EcgHeartPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── heart shape ──────────────────────────────────────────────────────
    final heartPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final cx = w / 2;
    final cy = h * 0.45;

    // Bezier-based heart centred at (cx, cy)
    path.moveTo(cx, cy + h * 0.28);
    path.cubicTo(
      cx - w * 0.12,
      cy + h * 0.12,
      cx - w * 0.52,
      cy - h * 0.08,
      cx - w * 0.50,
      cy - h * 0.28,
    );
    path.cubicTo(
      cx - w * 0.48,
      cy - h * 0.46,
      cx - w * 0.06,
      cy - h * 0.50,
      cx,
      cy - h * 0.30,
    );
    path.cubicTo(
      cx + w * 0.06,
      cy - h * 0.50,
      cx + w * 0.48,
      cy - h * 0.46,
      cx + w * 0.50,
      cy - h * 0.28,
    );
    path.cubicTo(
      cx + w * 0.52,
      cy - h * 0.08,
      cx + w * 0.12,
      cy + h * 0.12,
      cx,
      cy + h * 0.28,
    );
    path.close();
    canvas.drawPath(path, heartPaint);

    // ── ECG blip overlay ────────────────────────────────────────────────
    final ecgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final y0 = cy + h * 0.04;
    final ecgPath = Path()
      ..moveTo(cx - w * 0.28, y0)
      ..lineTo(cx - w * 0.10, y0)
      ..lineTo(cx - w * 0.04, y0 - h * 0.22)
      ..lineTo(cx + w * 0.02, y0 + h * 0.14)
      ..lineTo(cx + w * 0.08, y0)
      ..lineTo(cx + w * 0.28, y0);
    canvas.drawPath(ecgPath, ecgPaint);
  }

  @override
  bool shouldRepaint(_EcgHeartPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
//  OS badge  (Apple Health | Google Health Connect chip)
// ─────────────────────────────────────────────────────────────────────────────

class _OsBadge extends StatelessWidget {
  const _OsBadge({
    required this.label,
    required this.platformName,
    required this.accent,
    required this.isIOS,
  });

  final String label;
  final String platformName;
  final Color accent;
  final bool isIOS;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.0,
            color: accent.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isIOS ? Icons.favorite : Icons.monitor_heart_outlined,
                size: 13,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                platformName,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  NOTIFICATION STEP — daily body-blog push
// ═════════════════════════════════════════════════════════════════════════════

class _NotificationStep extends StatelessWidget {
  const _NotificationStep({
    required this.accent,
    required this.onEnable,
    required this.onSkip,
    required this.busy,
    required this.breathe,
  });

  final Color accent;
  final VoidCallback onEnable;
  final VoidCallback onSkip;
  final bool busy;
  final AnimationController breathe;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 36),

                _ZenOrb(
                  size: 140,
                  color: accent,
                  breathe: breathe,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: 42,
                    color: accent,
                  ),
                ),

                const SizedBox(height: 36),

                Text(
                  'Daily\nBody Post',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'GENTLE DAILY REMINDERS',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    color: accent.withValues(alpha: 0.8),
                  ),
                ),

                const SizedBox(height: 28),

                Text(
                  'Your body writes a new story every day. '
                  'Two quiet notifications will keep you in the loop:\n\n'
                  '☀️  Morning at 8:30 AM — start your day informed\n'
                  '🌙  Evening at 8:00 PM — review your full day',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.75,
                    fontWeight: FontWeight.w300,
                    color: dark ? Colors.white60 : Colors.black54,
                  ),
                ),

                const SizedBox(height: 24),

                _PrivacyNote(
                  text:
                      'Two gentle pushes per day, nothing more. '
                      'You can turn them off anytime.',
                  accent: accent,
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── pinned buttons ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              _PillButton(
                label: 'Enable Daily Reminders',
                color: accent,
                onPressed: busy ? null : onEnable,
                busy: busy,
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: busy ? null : onSkip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Not now',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  COMPLETE PAGE
// ═════════════════════════════════════════════════════════════════════════════

class _CompletePage extends StatelessWidget {
  const _CompletePage({required this.onEnter, required this.breathe});

  final VoidCallback onEnter;
  final AnimationController breathe;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    const successGreen = Color(0xFF6B8E6B);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 3),

          _ZenOrb(
            size: 160,
            color: successGreen,
            breathe: breathe,
            child: const Icon(
              Icons.check_rounded,
              size: 52,
              color: successGreen,
            ),
          ),

          const Spacer(flex: 2),

          Text(
            'You\'re ready',
            style: GoogleFonts.playfairDisplay(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),

          const SizedBox(height: 16),
          Container(
            width: 48,
            height: 1,
            color: Colors.grey.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 16),

          Text(
            'BodyPress is set up to help you\n'
            'tune into your body and environment.\n'
            'Start your mindful journey.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.75,
              fontWeight: FontWeight.w300,
              color: dark ? Colors.white60 : Colors.black45,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'You can adjust permissions anytime in Settings.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.grey[500],
            ),
          ),

          const Spacer(flex: 3),

          _PillButton(
            label: 'Enter BodyPress',
            color: primary,
            onPressed: onEnter,
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

/// Pulsing concentric-circle decoration — the Zen orb.
class _ZenOrb extends StatelessWidget {
  const _ZenOrb({
    required this.size,
    required this.color,
    required this.breathe,
    required this.child,
  });

  final double size;
  final Color color;
  final AnimationController breathe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: breathe,
      builder: (context, child) {
        final t = breathe.value; // 0 → 1 → 0

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // outer ring
              Transform.scale(
                scale: 1.0 + t * 0.06,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.08 + t * 0.04),
                      width: 1,
                    ),
                  ),
                ),
              ),
              // middle ring
              Transform.scale(
                scale: 1.0 + t * 0.03,
                child: Container(
                  width: size * 0.72,
                  height: size * 0.72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.12 + t * 0.06),
                      width: 1,
                    ),
                  ),
                ),
              ),
              // inner filled circle
              Container(
                width: size * 0.48,
                height: size * 0.48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.08),
                ),
                child: Center(child: this.child),
              ),
            ],
          ),
        );
      },
      child: child,
    );
  }
}

/// Pill-shaped primary action button.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// Block-quote-style privacy reassurance.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accent.withValues(alpha: 0.4), width: 2),
        ),
        color: accent.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 16,
            color: accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.6,
                fontWeight: FontWeight.w400,
                color: dark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
