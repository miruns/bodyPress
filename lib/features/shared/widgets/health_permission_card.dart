import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/service_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HealthPermissionCard
//
// Shown in the main app whenever health permissions are missing.
// Detects iOS (Apple Health / HealthKit) vs Android (Health Connect) and
// shows OS-appropriate messaging and action.
//
// Usage:
//   const HealthPermissionCard()
//
// The card hides itself once permissions are granted or after the user
// dismisses it for the session.
// ─────────────────────────────────────────────────────────────────────────────

/// Session-level dismiss flag — resets if the app restarts.
final _healthCardDismissedProvider = StateProvider<bool>((_) => false);

class HealthPermissionCard extends ConsumerWidget {
  const HealthPermissionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If the user dismissed for this session, show nothing.
    final dismissed = ref.watch(_healthCardDismissedProvider);
    if (dismissed) return const SizedBox.shrink();

    // Check if health is available on this device before checking perms.
    final availableAsync = ref.watch(healthAvailableProvider);
    final permAsync = ref.watch(healthPermissionStatusProvider);

    return availableAsync.when(
      data: (available) {
        if (!available) return const SizedBox.shrink();
        return permAsync.when(
          data: (granted) {
            if (granted) return const SizedBox.shrink();
            return _HealthCard(
              onDismiss: () =>
                  ref.read(_healthCardDismissedProvider.notifier).state = true,
              onOpenSettings: () async {
                await ref.read(healthServiceProvider).openHealthConnectApp();
                // Invalidate to re-check after returning from settings.
                ref.invalidate(healthPermissionStatusProvider);
              },
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HealthCard  — the actual UI
// ─────────────────────────────────────────────────────────────────────────────

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.onDismiss, required this.onOpenSettings});

  final VoidCallback onDismiss;
  final VoidCallback onOpenSettings;

  bool get _isIOS => Platform.isIOS;
  String get _platformName => _isIOS ? 'Apple Health' : 'Health Connect';

  static const _accent = Color(0xFFD4738A);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [const Color(0xFF2C1A1F), const Color(0xFF1E1520)]
                  : [const Color(0xFFFFF0F2), const Color(0xFFFAE8EE)],
            ),
            border: Border.all(
              color: _accent.withValues(alpha: dark ? 0.20 : 0.22),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── left illustration ──────────────────────────────────
                _AnimatedHeartBadge(accent: _accent, isIOS: _isIOS),

                const SizedBox(width: 14),

                // ── text + action ──────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Platform chip
                      _PlatformChip(name: _platformName, isIOS: _isIOS),

                      const SizedBox(height: 6),

                      Text(
                        'Connect Health Data',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: dark ? Colors.white : Colors.black87,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        _isIOS
                            ? 'Allow Apple Health access so BodyPress can track '
                                  'your steps, heart rate, sleep, and workouts.'
                            : '1 · Tap "Open Health Connect" below\n'
                                  '2 · Find BodyPress in the app list\n'
                                  '3 · Allow access to steps, heart rate & sleep',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.5,
                          fontWeight: FontWeight.w300,
                          color: dark ? Colors.white54 : Colors.black54,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // CTA row
                      Row(
                        children: [
                          GestureDetector(
                            onTap: onOpenSettings,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: _accent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isIOS
                                        ? 'Open Settings'
                                        : 'Open Health Connect',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── dismiss ───────────────────────────────────────────
                GestureDetector(
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: dark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AnimatedHeartBadge  — pulsing heart with an ECG mark
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedHeartBadge extends StatefulWidget {
  const _AnimatedHeartBadge({required this.accent, required this.isIOS});

  final Color accent;
  final bool isIOS;

  @override
  State<_AnimatedHeartBadge> createState() => _AnimatedHeartBadgeState();
}

class _AnimatedHeartBadgeState extends State<_AnimatedHeartBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.accent.withValues(alpha: dark ? 0.15 : 0.12),
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(26, 26),
            painter: _MiniHeartEcgPainter(color: widget.accent),
          ),
        ),
      ),
    );
  }
}

/// Mini heart + ECG blip — same design as in onboarding but smaller.
class _MiniHeartEcgPainter extends CustomPainter {
  const _MiniHeartEcgPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h * 0.46;

    // Heart
    final heartPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(cx, cy + h * 0.28)
      ..cubicTo(
        cx - w * 0.12,
        cy + h * 0.12,
        cx - w * 0.52,
        cy - h * 0.08,
        cx - w * 0.50,
        cy - h * 0.28,
      )
      ..cubicTo(
        cx - w * 0.48,
        cy - h * 0.46,
        cx - w * 0.06,
        cy - h * 0.50,
        cx,
        cy - h * 0.30,
      )
      ..cubicTo(
        cx + w * 0.06,
        cy - h * 0.50,
        cx + w * 0.48,
        cy - h * 0.46,
        cx + w * 0.50,
        cy - h * 0.28,
      )
      ..cubicTo(
        cx + w * 0.52,
        cy - h * 0.08,
        cx + w * 0.12,
        cy + h * 0.12,
        cx,
        cy + h * 0.28,
      )
      ..close();

    canvas.drawPath(path, heartPaint);

    // ECG blip
    final ecgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final y0 = cy + h * 0.04;
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.28, y0)
        ..lineTo(cx - w * 0.08, y0)
        ..lineTo(cx - w * 0.02, y0 - h * 0.22)
        ..lineTo(cx + w * 0.04, y0 + h * 0.14)
        ..lineTo(cx + w * 0.10, y0)
        ..lineTo(cx + w * 0.28, y0),
      ecgPaint,
    );
  }

  @override
  bool shouldRepaint(_MiniHeartEcgPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// _PlatformChip  — "Apple Health" or "Google Health Connect" badge
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.name, required this.isIOS});

  final String name;
  final bool isIOS;

  static const _accent = Color(0xFFD4738A);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isIOS ? Icons.favorite : Icons.monitor_heart_outlined,
          size: 11,
          color: _accent,
        ),
        const SizedBox(width: 4),
        Text(
          name,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: _accent,
          ),
        ),
      ],
    );
  }
}
