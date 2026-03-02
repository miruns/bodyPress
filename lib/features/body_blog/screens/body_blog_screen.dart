import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/body_blog_entry.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/theme_provider.dart';
import '../../shared/widgets/health_permission_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Body Blog — Medium-inspired, Zen home screen
// ─────────────────────────────────────────────────────────────────────────────

class BodyBlogScreen extends ConsumerStatefulWidget {
  const BodyBlogScreen({super.key});

  @override
  ConsumerState<BodyBlogScreen> createState() => _BodyBlogScreenState();
}

class _BodyBlogScreenState extends ConsumerState<BodyBlogScreen> {
  late final _blogService = ref.read(bodyBlogServiceProvider);
  final PageController _pageCtrl = PageController();

  List<BodyBlogEntry> _entries = [];
  int _currentPage = 0;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  static const int _pageSize = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Normal load — uses getTodayEntry() which returns instantly when
  /// today's entry is persisted and no new captures exist.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await _blogService.getRecentEntries(days: _pageSize);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Explicit refresh — collects fresh sensors + AI for today and
  /// refreshes the displayed list.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final fresh = await _blogService.refreshTodayEntry();
      if (mounted) {
        // Replace today's entry (index 0) with the refreshed version.
        setState(() {
          if (_entries.isNotEmpty) {
            _entries = [fresh, ..._entries.skip(1)];
          } else {
            _entries = [fresh];
          }
          _refreshing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Lazily fetch older entries when the user approaches the end.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      final moreEntries = await _blogService.getRecentEntries(
        days: _entries.length + _pageSize,
      );
      if (mounted && moreEntries.length > _entries.length) {
        setState(() => _entries = moreEntries);
      }
    } catch (_) {}
    _loadingMore = false;
  }

  void _goPage(int page) {
    if (page < 0 || page >= _entries.length) return;
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _goToday() {
    _pageCtrl.animateToPage(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  // ── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          // _TopBar is always rendered so the app chrome is visible
          // immediately, regardless of whether content is loading.
          child: Column(
            children: [
              _TopBar(
                onDebug: () => context.push('/debug'),
                onRefresh: _refresh,
                isRefreshing: _refreshing,
              ),
              // Health permission banner — only visible when health access
              // is not granted on the current device.
              const HealthPermissionCard(),
              Expanded(
                child: _loading
                    ? const Center(child: _ZenLoader())
                    : _entries.isEmpty
                    ? _emptyState(dark)
                    : Stack(
                        children: [
                          Column(
                            children: [
                              Expanded(
                                child: PageView.builder(
                                  controller: _pageCtrl,
                                  itemCount: _entries.length,
                                  onPageChanged: (i) {
                                    setState(() => _currentPage = i);
                                    // Pre-fetch older entries when nearing the end
                                    if (i >= _entries.length - 3) _loadMore();
                                  },
                                  itemBuilder: (ctx, i) => _BlogPage(
                                    entry: _entries[i],
                                    onReadMore: () =>
                                        _openDetail(context, _entries[i]),
                                    isToday: i == 0,
                                    isRefreshing: _refreshing,
                                    onRefresh: _refresh,
                                  ),
                                ),
                              ),
                              _DateNav(
                                entries: _entries,
                                current: _currentPage,
                                onPrev: () => _goPage(_currentPage - 1),
                                onNext: () => _goPage(_currentPage + 1),
                              ),
                            ],
                          ),
                          // Floating "Today" pill — visible only when away from today
                          if (_currentPage > 0)
                            Positioned(
                              bottom: 72,
                              left: 0,
                              right: 0,
                              child: Center(child: _TodayPill(onTap: _goToday)),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Your body journal is preparing…\nPull down to refresh.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: dark ? Colors.white54 : Colors.black38,
            height: 1.8,
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, BodyBlogEntry entry) {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => _BlogDetailPage(entry: entry),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        )
        .then((_) => _load()); // refresh list with any AI changes from detail
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TOP BAR
// ═════════════════════════════════════════════════════════════════════════════

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.onDebug,
    required this.onRefresh,
    this.isRefreshing = false,
  });

  final VoidCallback onDebug;
  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);

    void toggleTheme() {
      // Cycle: system → dark → light → system
      final next = switch (themeMode) {
        ThemeMode.system => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.light,
        ThemeMode.light => ThemeMode.system,
      };
      ref.read(themeModeProvider.notifier).setThemeMode(next);
    }

    IconData themeIcon;
    String themeTooltip;
    switch (themeMode) {
      case ThemeMode.dark:
        themeIcon = Icons.dark_mode_outlined;
        themeTooltip = 'Dark mode (tap for light)';
        break;
      case ThemeMode.light:
        themeIcon = Icons.light_mode_outlined;
        themeTooltip = 'Light mode (tap for system)';
        break;
      case ThemeMode.system:
        themeIcon = dark ? Icons.brightness_auto : Icons.brightness_auto;
        themeTooltip = 'System theme (tap for dark)';
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
      child: Row(
        children: [
          Text(
            'BodyPress',
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: toggleTheme,
            icon: Icon(
              themeIcon,
              color: dark ? Colors.white38 : Colors.black26,
              size: 22,
            ),
            tooltip: themeTooltip,
          ),
          isRefreshing
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: dark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: onRefresh,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: dark ? Colors.white38 : Colors.black26,
                    size: 22,
                  ),
                  tooltip: 'Refresh today',
                ),
          IconButton(
            onPressed: onDebug,
            icon: Icon(
              Icons.bug_report_outlined,
              color: dark ? Colors.white38 : Colors.black26,
              size: 22,
            ),
            tooltip: 'Debug panel',
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  BLOG PAGE (single entry card — scrollable)
// ═════════════════════════════════════════════════════════════════════════════

class _BlogPage extends StatelessWidget {
  const _BlogPage({
    required this.entry,
    required this.onReadMore,
    this.isToday = false,
    this.isRefreshing = false,
    this.onRefresh,
  });

  final BodyBlogEntry entry;
  final VoidCallback onReadMore;
  final bool isToday;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dateLabel = _formatDate(entry.date);
    final primary = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: () async {
        if (isToday && onRefresh != null) {
          onRefresh!();
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── date & mood ──
            Row(
              children: [
                Text(
                  dateLabel,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: primary.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                if (entry.aiGenerated) ...[
                  const _AiBadge(),
                  const SizedBox(width: 10),
                ],
                Text(entry.moodEmoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 6),
                Text(
                  entry.mood.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── headline ──
            Text(
              entry.headline,
              style: GoogleFonts.playfairDisplay(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),

            const SizedBox(height: 20),

            // ── horizontal rule ──
            Container(
              width: 48,
              height: 2,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),

            const SizedBox(height: 20),

            // ── summary ──
            Text(
              entry.summary,
              style: GoogleFonts.inter(
                fontSize: 16,
                height: 1.8,
                fontWeight: FontWeight.w300,
                color: dark ? Colors.white70 : Colors.black54,
              ),
            ),

            const SizedBox(height: 24),

            // ── tags ──
            if (entry.tags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entry.tags.map((t) => _Tag(label: t)).toList(),
              ),

            if (entry.tags.isNotEmpty) const SizedBox(height: 28),

            // ── snapshot glance ──
            _SnapshotGlance(snapshot: entry.snapshot),

            const SizedBox(height: 28),

            // ── refresh day button (today only) ──
            if (isToday)
              Center(
                child: isRefreshing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primary.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Gathering your story…',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: dark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      )
                    : TextButton.icon(
                        onPressed: onRefresh,
                        icon: Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: primary.withValues(alpha: 0.7),
                        ),
                        label: Text(
                          'Refresh day',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: primary.withValues(alpha: 0.7),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: primary.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                      ),
              ),

            if (isToday) const SizedBox(height: 20),

            // ── read more CTA ──
            if (entry.fullBody.isNotEmpty)
              Center(
                child: TextButton(
                  onPressed: onReadMore,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: primary.withValues(alpha: 0.25)),
                    ),
                  ),
                  child: Text(
                    'Read full journal entry',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: primary,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'TODAY  ·  ${DateFormat('MMMM d').format(d)}';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'YESTERDAY  ·  ${DateFormat('MMMM d').format(d)}';
    }
    return DateFormat('EEEE  ·  MMMM d').format(d).toUpperCase();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SNAPSHOT GLANCE — small stat row
// ═════════════════════════════════════════════════════════════════════════════

class _SnapshotGlance extends StatelessWidget {
  const _SnapshotGlance({required this.snapshot});
  final BodySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <_GlanceItem>[];

    if (snapshot.steps > 0) {
      items.add(_GlanceItem('🚶', '${snapshot.steps}', 'steps'));
    }
    if (snapshot.sleepHours > 0) {
      items.add(
        _GlanceItem('😴', snapshot.sleepHours.toStringAsFixed(1), 'h sleep'),
      );
    }
    if (snapshot.avgHeartRate > 0) {
      items.add(_GlanceItem('❤️', '${snapshot.avgHeartRate}', 'bpm'));
    }
    if (snapshot.caloriesBurned > 0) {
      items.add(
        _GlanceItem('🔥', snapshot.caloriesBurned.toStringAsFixed(0), 'kcal'),
      );
    }
    if (snapshot.temperatureC != null) {
      items.add(
        _GlanceItem(
          '🌡️',
          '${snapshot.temperatureC!.toStringAsFixed(0)}°',
          'C',
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items
            .map((item) => _GlanceCell(item: item, dark: dark))
            .toList(),
      ),
    );
  }
}

class _GlanceItem {
  final String emoji;
  final String value;
  final String unit;
  const _GlanceItem(this.emoji, this.value, this.unit);
}

class _GlanceCell extends StatelessWidget {
  const _GlanceCell({required this.item, required this.dark});
  final _GlanceItem item;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          item.value,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          item.unit,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: dark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TAG CHIP
// ═════════════════════════════════════════════════════════════════════════════

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: dark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  DATE-AWARE NAVIGATION BAR
// ═════════════════════════════════════════════════════════════════════════════

class _DateNav extends StatelessWidget {
  const _DateNav({
    required this.entries,
    required this.current,
    required this.onPrev,
    required this.onNext,
  });

  final List<BodyBlogEntry> entries;
  final int current;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final hasNewer = current > 0;
    final hasOlder = current < entries.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: Row(
        children: [
          // ── Left arrow: show target date ─────────────────
          Expanded(
            child: _DateArrow(
              enabled: hasNewer,
              onTap: onPrev,
              label: hasNewer ? _shortDate(entries[current - 1].date) : '',
              icon: Icons.chevron_left_rounded,
              alignment: Alignment.centerLeft,
            ),
          ),

          // ── Center: current date with relative label ────
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _relativeLabel(entries[current].date),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('MMM d, y').format(entries[current].date),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: dark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),

          // ── Right arrow: show target date ────────────────
          Expanded(
            child: _DateArrow(
              enabled: hasOlder,
              onTap: onNext,
              label: hasOlder ? _shortDate(entries[current + 1].date) : '',
              icon: Icons.chevron_right_rounded,
              alignment: Alignment.centerRight,
            ),
          ),
        ],
      ),
    );
  }

  /// "Today", "Yesterday", or "Mon", "Tue" etc.
  String _relativeLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    if (diff < 7) return '$diff DAYS AGO';
    return '$diff DAYS AGO';
  }

  /// Compact date for the arrow labels: "Feb 24" or "Mon 24".
  String _shortDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEE d').format(d);
  }
}

class _DateArrow extends StatelessWidget {
  const _DateArrow({
    required this.enabled,
    required this.onTap,
    required this.label,
    required this.icon,
    required this.alignment,
  });

  final bool enabled;
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = enabled
        ? (dark ? Colors.white70 : Colors.black54)
        : Colors.transparent;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon == Icons.chevron_left_rounded)
                Icon(icon, color: color, size: 22),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
              if (icon == Icons.chevron_right_rounded)
                Icon(icon, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  "TODAY" FLOATING PILL
// ═════════════════════════════════════════════════════════════════════════════

class _TodayPill extends StatelessWidget {
  const _TodayPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      shadowColor: primary.withValues(alpha: 0.4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_upward_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                'Today',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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
//  GENERATED BADGE — small "✦ Generated" chip on generated entries
// ═════════════════════════════════════════════════════════════════════════════

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: dark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primary.withValues(alpha: dark ? 0.35 : 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 10, color: primary),
          const SizedBox(width: 3),
          Text(
            'Generated',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  ZEN LOADER — engaging rotating phrases with elapsed time
// ═════════════════════════════════════════════════════════════════════════════

const _zenPhrases = [
  'Sensing your rhythm…',
  'Reading between the heartbeats…',
  'Composing your story…',
  'Weaving your day together…',
  'Finding the thread…',
  'Listening to your body…',
];

class _ZenLoader extends StatefulWidget {
  const _ZenLoader();

  @override
  State<_ZenLoader> createState() => _ZenLoaderState();
}

class _ZenLoaderState extends State<_ZenLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Stopwatch _stopwatch;
  Timer? _timer;
  int _phraseIndex = 0;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _stopwatch = Stopwatch()..start();
    // Rotate phrase every 4 seconds and update elapsed time every second
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds = _stopwatch.elapsed.inSeconds;
        if (_elapsedSeconds > 0 && _elapsedSeconds % 4 == 0) {
          _phraseIndex = (_phraseIndex + 1) % _zenPhrases.length;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  String _formatElapsed(int seconds) {
    if (seconds < 5) return '';
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins}m ${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final elapsed = _formatElapsed(_elapsedSeconds);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.95 + _ctrl.value * 0.05,
              child: Opacity(
                opacity: 0.4 + _ctrl.value * 0.3,
                child: Icon(Icons.spa_outlined, size: 36, color: primary),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _zenPhrases[_phraseIndex],
                key: ValueKey<int>(_phraseIndex),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                  color: dark ? Colors.white38 : Colors.black38,
                ),
              ),
            ),
            if (elapsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                elapsed,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: dark ? Colors.white24 : Colors.black26,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  FULL JOURNAL DETAIL PAGE
// ═════════════════════════════════════════════════════════════════════════════

class _BlogDetailPage extends ConsumerStatefulWidget {
  const _BlogDetailPage({required this.entry});
  final BodyBlogEntry entry;

  @override
  ConsumerState<_BlogDetailPage> createState() => _BlogDetailPageState();
}

class _BlogDetailPageState extends ConsumerState<_BlogDetailPage> {
  late BodyBlogEntry _entry;
  late final _blogService = ref.read(bodyBlogServiceProvider);
  bool _aiRegenerating = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  /// True when this entry belongs to the current calendar day.
  /// Past entries are locked — only notes / mood can be edited.
  bool get _isEntryToday {
    final now = DateTime.now();
    final d = _entry.date;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> _regenerateWithAi() async {
    if (_aiRegenerating) return;
    setState(() => _aiRegenerating = true);
    try {
      final updated = await _blogService.regenerateWithAi(_entry.date);
      if (updated != null && mounted) {
        setState(() => _entry = updated);
      }
    } catch (_) {}
    if (mounted) setState(() => _aiRegenerating = false);
  }

  /// Return the label for a mood emoji, or the emoji itself as fallback.
  String _moodLabel(String emoji) {
    for (final option in _moodOptions) {
      if (option.$1 == emoji) return option.$2;
    }
    return emoji;
  }

  /// Mood options available to the user.
  static const _moodOptions = [
    ('😊', 'Great'),
    ('😌', 'Good'),
    ('😐', 'Meh'),
    ('😔', 'Low'),
    ('🤯', 'Stressed'),
    ('😴', 'Tired'),
  ];

  Future<void> _showNoteEditor() async {
    final controller = TextEditingController(text: _entry.userNote ?? '');
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    String? selectedMood = _entry.userMood;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: dark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'How are you feeling?',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: dark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      if ((_entry.userNote != null &&
                              _entry.userNote!.isNotEmpty) ||
                          _entry.userMood != null)
                        TextButton(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            final updated = await _blogService.saveUserNote(
                              _entry.date,
                              null,
                              mood: null,
                            );
                            if (updated != null && mounted) {
                              setState(() => _entry = updated);
                            }
                          },
                          child: Text(
                            'Clear',
                            style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── mood picker row ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: _moodOptions.map((option) {
                      final emoji = option.$1;
                      final label = option.$2;
                      final isSelected = selectedMood == emoji;
                      return GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            selectedMood = isSelected ? null : emoji;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primary.withValues(alpha: dark ? 0.25 : 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? primary : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                emoji,
                                style: TextStyle(
                                  fontSize: isSelected ? 28 : 24,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                label,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? primary
                                      : (dark
                                            ? Colors.white38
                                            : Colors.black38),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 5,
                    minLines: 2,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      height: 1.6,
                      color: dark ? Colors.white70 : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add a note (optional)',
                      hintStyle: GoogleFonts.inter(
                        color: dark ? Colors.white30 : Colors.black38,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: primary.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: dark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final note = controller.text.trim();
                        Navigator.of(ctx).pop();
                        final updated = await _blogService.saveUserNote(
                          _entry.date,
                          note.isEmpty ? null : note,
                          mood: selectedMood,
                        );
                        if (updated != null && mounted) {
                          setState(() => _entry = updated);
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        selectedMood != null ? '$selectedMood  Save' : 'Save',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    // Defer dispose until after the sheet's close animation finishes.
    // Disposing immediately causes "used after dispose" errors because
    // Flutter may still rebuild the TextField during the exit animation.
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // back button + date + note edit icon
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: dark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('MMMM d, y').format(_entry.date),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: dark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _entry.userMood != null
                        ? 'Edit mood & note'
                        : (_entry.userNote != null
                              ? 'Edit note'
                              : 'Add mood & note'),
                    onPressed: _showNoteEditor,
                    icon: _entry.userMood != null
                        ? Text(
                            _entry.userMood!,
                            style: const TextStyle(fontSize: 22),
                          )
                        : Icon(
                            _entry.userNote != null
                                ? Icons.edit_note_rounded
                                : Icons.add_comment_outlined,
                            size: 20,
                            color: _entry.userNote != null
                                ? primary
                                : (dark ? Colors.white38 : Colors.black38),
                          ),
                  ),
                  // AI regenerate button — today only; past entries are locked.
                  if (_isEntryToday)
                    _aiRegenerating
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Tooltip(
                            message: _entry.aiGenerated
                                ? 'Rewrite entry'
                                : 'Generate entry',
                            child: IconButton(
                              onPressed: _regenerateWithAi,
                              icon: Icon(
                                Icons.auto_awesome_rounded,
                                size: 20,
                                color: _entry.aiGenerated
                                    ? primary
                                    : (dark ? Colors.white38 : Colors.black38),
                              ),
                            ),
                          ),
                ],
              ),
            ),

            // content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // headline
                    Text(
                      _entry.headline,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Text(
                          _entry.moodEmoji,
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _entry.mood,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: primary.withValues(alpha: 0.7),
                          ),
                        ),
                        if (_aiRegenerating) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Writing…',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: primary.withValues(alpha: 0.6),
                            ),
                          ),
                        ] else if (_entry.aiGenerated) ...[
                          const SizedBox(width: 12),
                          const _AiBadge(),
                        ],
                      ],
                    ),

                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      height: 1,
                      color: dark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    const SizedBox(height: 24),

                    // full body
                    Text(
                      _entry.fullBody,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        height: 1.85,
                        fontWeight: FontWeight.w300,
                        color: dark ? Colors.white70 : Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // tags
                    if (_entry.tags.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _entry.tags
                            .map((t) => _Tag(label: t))
                            .toList(),
                      ),

                    // user note block
                    if ((_entry.userNote != null &&
                            _entry.userNote!.isNotEmpty) ||
                        _entry.userMood != null) ...[
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: dark ? 0.12 : 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(color: primary, width: 3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (_entry.userMood != null) ...[
                                  Text(
                                    _entry.userMood!,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(width: 8),
                                ] else ...[
                                  Icon(
                                    Icons.edit_note_rounded,
                                    size: 14,
                                    color: primary.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  _entry.userMood != null
                                      ? _moodLabel(_entry.userMood!)
                                      : 'Your note',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: primary.withValues(alpha: 0.7),
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _showNoteEditor,
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 14,
                                    color: dark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                            if (_entry.userNote != null &&
                                _entry.userNote!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                _entry.userNote!,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  height: 1.65,
                                  fontStyle: FontStyle.italic,
                                  color: dark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 32),
                      GestureDetector(
                        onTap: _showNoteEditor,
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_comment_outlined,
                              size: 16,
                              color: dark ? Colors.white24 : Colors.black26,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'How are you feeling today?',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: dark ? Colors.white24 : Colors.black26,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
