import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppHeader — shared top-bar for all main screens
// ─────────────────────────────────────────────────────────────────────────────

/// A named action shown inside the AppHeader ⋯ overflow popup.
class AppHeaderAction {
  const AppHeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Consistent top-bar widget used across all main screens.
///
/// Layout (left → right):
///   [title (+ optional subtitle)]  ‥  [primaryAction]  [⋯]
///
/// • [title] — screen name in Playfair Display.
/// • [subtitle] — optional dim caption line (e.g. "12 of 34 analysed").
/// • [primaryAction] — optional inline widget before the overflow icon
///   (e.g. a refresh button, a spinner, or a badge row).
/// • [extraActions] — screen-specific items prepended to the ⋯ popup.
///   The theme-mode toggle is always appended last.
class AppHeader extends ConsumerWidget {
  const AppHeader({
    required this.title,
    this.subtitle,
    this.primaryAction,
    this.extraActions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? primaryAction;
  final List<AppHeaderAction> extraActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);

    final dimColor = dark ? Colors.white38 : Colors.black26;
    final titleColor = dark ? Colors.white : Colors.black87;
    final subColor = dark
        ? Colors.white.withValues(alpha: 0.38)
        : Colors.black.withValues(alpha: 0.42);
    final popupBg = dark ? const Color(0xFF1C1C2E) : Colors.white;
    final popupBorder = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final popupTextColor = dark ? Colors.white70 : Colors.black87;

    void toggleTheme() {
      final next = switch (themeMode) {
        ThemeMode.system => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.light,
        ThemeMode.light => ThemeMode.system,
      };
      ref.read(themeModeProvider.notifier).setThemeMode(next);
    }

    final themeLabel = switch (themeMode) {
      ThemeMode.dark => 'Dark mode',
      ThemeMode.light => 'Light mode',
      ThemeMode.system => 'System theme',
    };

    final themeIcon = switch (themeMode) {
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };

    // Extra actions appear first; theme toggle is always last.
    final allPopupActions = [
      ...extraActions,
      AppHeaderAction(icon: themeIcon, label: themeLabel, onTap: toggleTheme),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Title + subtitle ──────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: subColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Inline primary action (e.g. refresh) ─────────────────────
          if (primaryAction != null) primaryAction!,

          // ── Overflow ⋯ popup ──────────────────────────────────────────
          PopupMenuButton<int>(
            onSelected: (i) => allPopupActions[i].onTap(),
            tooltip: 'More options',
            icon: Icon(Icons.more_horiz_rounded, color: dimColor, size: 22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: popupBorder),
            ),
            color: popupBg,
            elevation: 8,
            offset: const Offset(0, 40),
            itemBuilder: (_) => List.generate(allPopupActions.length, (i) {
              final a = allPopupActions[i];
              return PopupMenuItem<int>(
                value: i,
                height: 44,
                child: Row(
                  children: [
                    Icon(a.icon, size: 18, color: dimColor),
                    const SizedBox(width: 12),
                    Text(
                      a.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: popupTextColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
