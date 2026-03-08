import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/body_blog_entry.dart';
import '../../../core/models/body_blog_version.dart';
import '../../../core/services/service_providers.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/health_permission_card.dart';
import '../widgets/insight_reflection_card.dart';
import '../widgets/social_card.dart';

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
  bool _isFirstVisit = false;
  bool _sharing = false;
  int _refreshStage = 0; // 0=sensing, 1=drafting, 2=composing, 3=done
  String? _selectedToneName;
  Timer? _refreshStageTimer;
  static const int _pageSize = 7;

  @override
  void initState() {
    super.initState();
    _initWithFirstVisitCheck();
  }

  /// Check for first-time use (empty DB) before loading, so we can show
  /// the immersive bootstrap experience instead of the generic spinner.
  Future<void> _initWithFirstVisitCheck() async {
    try {
      final db = ref.read(localDbServiceProvider);
      final hasData = await db.hasAnyEntries();
      if (!hasData && mounted) {
        setState(() => _isFirstVisit = true);
      }
    } catch (_) {}
    await _load();
    if (mounted) setState(() => _isFirstVisit = false);
  }

  @override
  void dispose() {
    _refreshStageTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Normal load — always refreshes today's entry with fresh sensor data
  /// to ensure users see current information on app start, then loads
  /// past entries from DB.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Always refresh today's entry to show fresh data (good UX)
      final todayEntry = await _blogService.refreshTodayEntry();

      // Load past entries from DB (already persisted, no refresh needed)
      final now = DateTime.now();
      final pastEntries = <BodyBlogEntry>[];
      for (var i = 1; i < _pageSize; i++) {
        final date = now.subtract(Duration(days: i));
        final stored = await ref.read(localDbServiceProvider).loadEntry(date);
        if (stored != null) pastEntries.add(stored);
      }

      if (mounted) {
        setState(() {
          _entries = [todayEntry, ...pastEntries];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Explicit refresh — shows a tone selector bottom sheet, then collects fresh
  /// sensors + AI for today and refreshes the displayed list.
  ///
  /// The overlay pipeline tracks three visual stages:
  /// 0  Sensing  – collecting health / location / calendar
  /// 1  Drafting – saving local draft snapshot
  /// 2  Composing – AI writing the narrative
  /// 3  Done     – brief completion flourish
  Future<void> _refresh() async {
    if (_refreshing) return;

    // Show tone selector bottom sheet
    final tone = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ToneSelectorBottomSheet(),
    );

    // User cancelled (dismissed the sheet without picking a tone)
    if (!mounted || tone == null) return;

    setState(() {
      _refreshing = true;
      _refreshStage = 0;
      _selectedToneName = _toneDisplayName(tone);
    });

    // Start timer-based stage progression (approximate durations)
    _startRefreshStageProgression();

    try {
      // 'default' is a sentinel — the service expects null for the default tone.
      final effectiveTone = tone == 'default' ? null : tone;
      final fresh = await _blogService.refreshTodayEntry(tone: effectiveTone);
      _refreshStageTimer?.cancel();
      if (mounted) {
        // Show "done" stage briefly
        setState(() => _refreshStage = 3);
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        // Replace today's entry (index 0) with the refreshed version.
        setState(() {
          if (_entries.isNotEmpty) {
            _entries = [fresh, ..._entries.skip(1)];
          } else {
            _entries = [fresh];
          }
          _refreshing = false;
          _refreshStage = 0;
          _selectedToneName = null;
        });
      }
    } catch (_) {
      _refreshStageTimer?.cancel();
      if (mounted) {
        setState(() {
          _refreshing = false;
          _refreshStage = 0;
          _selectedToneName = null;
        });
      }
    }
  }

  /// Advance stages on approximate timers so the overlay feels alive even
  /// though the actual service call is a single Future.
  void _startRefreshStageProgression() {
    _refreshStageTimer?.cancel();
    // Stage 0 → 1 after ~4s (sensor reads finish fast)
    _refreshStageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_refreshing || _refreshStage != 0) return;
      setState(() => _refreshStage = 1);
      // Stage 1 → 2 after ~2s (local draft save)
      _refreshStageTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted || !_refreshing || _refreshStage != 1) return;
        setState(() => _refreshStage = 2);
      });
    });
  }

  /// Map tone key to a user-friendly display name.
  static String _toneDisplayName(String tone) {
    const map = {
      'default': 'Default',
      'motivational': 'Motivational',
      'poetic': 'Poetic',
      'scientific': 'Scientific',
      'humorous': 'Humorous',
      'philosophical': 'Philosophical',
      'minimal': 'Minimal',
    };
    return map[tone] ?? tone;
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
          // AppHeader is always rendered so chrome is visible immediately,
          // regardless of whether content is still loading.
          child: Column(
            children: [
              AppHeader(
                title: 'BodyPress',
                primaryAction: _refreshing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _refresh,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (dark
                                          ? Colors.white
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary)
                                      .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color:
                                    (dark
                                            ? Colors.white
                                            : Theme.of(
                                                context,
                                              ).colorScheme.primary)
                                        .withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ShimmerAiIcon(size: 18, dark: dark),
                                const SizedBox(width: 8),
                                Text(
                                  "Refresh",
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: dark
                                        ? Colors.white70
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              // Health permission banner — only visible when health access
              // is not granted on the current device.
              const HealthPermissionCard(),
              Expanded(
                child: Stack(
                  children: [
                    // ── Main content ──
                    _loading
                        ? (_isFirstVisit
                              ? const _FirstVisitBootstrap()
                              : const Center(child: _ZenLoader()))
                        : _entries.isEmpty
                        ? _emptyState(dark)
                        : Column(
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    PageView.builder(
                                      controller: _pageCtrl,
                                      itemCount: _entries.length,
                                      onPageChanged: (i) {
                                        setState(() => _currentPage = i);
                                        // Pre-fetch older entries when nearing the end
                                        if (i >= _entries.length - 3) {
                                          _loadMore();
                                        }
                                      },
                                      itemBuilder: (ctx, i) => _BlogPage(
                                        entry: _entries[i],
                                        onReadMore: () =>
                                            _openDetail(context, _entries[i]),
                                        isToday: i == 0,
                                        isRefreshing: _refreshing,
                                        onRefresh: _refresh,
                                        onViewHistory: () => _showHistory(
                                          context,
                                          _entries[i].date,
                                        ),
                                      ),
                                    ),

                                    // Floating "Today" pill — visible only when away from today
                                    if (_currentPage > 0)
                                      Positioned(
                                        bottom: 16,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: _TodayPill(onTap: _goToday),
                                        ),
                                      ),

                                    // Floating share FAB — bottom-right, clears DateNav
                                    Positioned(
                                      bottom: 16,
                                      right: 20,
                                      child: _ShareFab(
                                        sharing: _sharing,
                                        onShare: _entries.isNotEmpty
                                            ? _shareCurrentEntry
                                            : null,
                                      ),
                                    ),
                                  ],
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

                    // ── Refresh journey overlay ──
                    if (_refreshing)
                      _RefreshJourneyOverlay(
                        stage: _refreshStage,
                        toneName: _selectedToneName,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ready to check in?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap the chat icon above to start a conversation',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: dark ? Colors.white38 : Colors.black38,
                height: 1.6,
              ),
            ),
          ],
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

  /// Captures the current entry as a high-res editorial card and opens the
  /// native share sheet. The [SocialCard] is rendered off-screen — the user
  /// never sees it until it lands in their Stories / Twitter / iMessage.
  Future<void> _shareCurrentEntry() async {
    if (_sharing || _entries.isEmpty) return;
    setState(() => _sharing = true);
    try {
      await SocialCardCapture.captureAndShare(
        context: context,
        entry: _entries[_currentPage],
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _showHistory(BuildContext context, DateTime date) async {
    final versions = await _blogService.loadVersionsForDate(date);
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VersionHistorySheet(date: date, versions: versions),
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
    this.onViewHistory,
  });

  final BodyBlogEntry entry;
  final VoidCallback onReadMore;
  final bool isToday;
  final bool isRefreshing;
  final VoidCallback? onRefresh;
  final VoidCallback? onViewHistory;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dateLabel = _formatDate(entry.date);
    final primary = Theme.of(context).colorScheme.primary;
    final readTime = _estimateReadTime(
      entry.fullBody.isNotEmpty ? entry.fullBody : entry.summary,
    );
    final spotlightFacts = _buildJournalSpotlightFacts(entry);
    final metricItems = _buildJournalMetricItems(entry.snapshot);
    final contextItems = _buildJournalContextItems(entry.snapshot);
    final previewText = entry.fullBody.isNotEmpty
        ? _journalPreview(entry.fullBody)
        : entry.summary;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  const Color(0xFF09090B),
                  const Color(0xFF121218),
                  const Color(0xFF09090B),
                ]
              : [
                  Colors.white,
                  primary.withValues(alpha: 0.035),
                  const Color(0xFFF7F5F1),
                ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            _JournalHeroPanel(
              headline: entry.headline,
              previewText: previewText,
              dateLabel: dateLabel,
              moodEmoji: entry.moodEmoji,
              moodLabel: toBeginningOfSentenceCase(entry.mood),
              readTime: readTime,
              badge: entry.aiGenerated
                  ? const _AiBadge()
                  : const _RawDataBadge(),
              spotlightFacts: spotlightFacts,
              action: entry.fullBody.isNotEmpty
                  ? _JournalPrimaryButton(
                      label: 'Read full journal',
                      icon: Icons.menu_book_rounded,
                      onTap: onReadMore,
                    )
                  : null,
            ),
            const SizedBox(height: 18),
            _JournalGlassSection(
              eyebrow: 'The quick read',
              title: 'What mattered most today',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.summary,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      height: 1.8,
                      fontWeight: FontWeight.w400,
                      color: dark ? Colors.white70 : const Color(0xFF3A3A41),
                    ),
                  ),
                  if ((entry.userNote ?? '').trim().isNotEmpty ||
                      entry.userMood != null) ...[
                    const SizedBox(height: 18),
                    _JournalQuoteCallout(
                      label: entry.userMood != null
                          ? 'Your reflection ${entry.userMood!}'
                          : 'Your reflection',
                      text: (entry.userNote ?? '').trim().isNotEmpty
                          ? entry.userNote!.trim()
                          : 'You checked in on yourself today.',
                    ),
                  ],
                ],
              ),
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 18),
              _JournalGlassSection(
                eyebrow: 'Keywords',
                title: 'The themes shaping the day',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: entry.tags.map((t) => _Tag(label: t)).toList(),
                ),
              ),
            ],
            if (metricItems.isNotEmpty) ...[
              const SizedBox(height: 18),
              _JournalGlassSection(
                eyebrow: 'Body dashboard',
                title: 'Your signals, beautifully organized',
                child: _JournalMetricGrid(items: metricItems),
              ),
            ],
            if (_hasSnapshotData(entry.snapshot)) ...[
              const SizedBox(height: 18),
              _JournalGlassSection(
                eyebrow: 'At a glance',
                title: 'The rhythm underneath the story',
                child: _SnapshotGlance(snapshot: entry.snapshot),
              ),
            ],
            if (contextItems.isNotEmpty) ...[
              const SizedBox(height: 18),
              _JournalGlassSection(
                eyebrow: 'Context',
                title: 'Where your body spent the day',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: contextItems
                      .map((item) => _JournalContextChip(item: item))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _JournalGlassSection(
              eyebrow: 'Inputs used',
              title: 'Every journal is grounded in real signals',
              child: _SensorStatusRow(snapshot: entry.snapshot),
            ),
            const SizedBox(height: 18),
            InsightReflectionCard(entry: entry),
            if (isToday) ...[
              const SizedBox(height: 22),
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
                              color: primary.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Gathering a better draft…',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: dark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      )
                    : OutlinedButton.icon(
                        onPressed: onRefresh,
                        icon: _ShimmerAiIcon(size: 15, dark: dark),
                        label: Text(
                          'Rewrite today',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          side: BorderSide(
                            color: primary.withValues(alpha: 0.22),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
              ),
            ],
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: onViewHistory,
                icon: Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: dark ? Colors.white30 : Colors.black26,
                ),
                label: Text(
                  'Open day history',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
            ),
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

class _JournalSpotlightFact {
  final IconData icon;
  final String label;
  final String value;

  const _JournalSpotlightFact({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _JournalMetricItem {
  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  const _JournalMetricItem({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });
}

class _JournalContextItem {
  final IconData icon;
  final String label;
  final String value;

  const _JournalContextItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

bool _hasSnapshotData(BodySnapshot snapshot) =>
    snapshot.steps > 0 ||
    snapshot.sleepHours > 0 ||
    snapshot.avgHeartRate > 0 ||
    snapshot.caloriesBurned > 0 ||
    snapshot.distanceKm > 0 ||
    snapshot.workouts > 0 ||
    snapshot.temperatureC != null ||
    snapshot.aqiUs != null ||
    snapshot.uvIndex != null ||
    snapshot.city != null ||
    snapshot.calendarEvents.isNotEmpty;

String _estimateReadTime(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) return '1 min read';
  final words = normalized.split(RegExp(r'\s+')).length;
  final minutes = math.max(1, (words / 180).ceil());
  return '$minutes min read';
}

String _journalPreview(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 240) return normalized;
  final cut = normalized.lastIndexOf(' ', 240);
  final index = cut > 140 ? cut : 240;
  return '${normalized.substring(0, index).trim()}…';
}

List<String> _storyParagraphs(String text) {
  final paragraphs = text
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (paragraphs.isNotEmpty) return paragraphs;

  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];

  final sentences = normalized
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final chunks = <String>[];
  for (var i = 0; i < sentences.length; i += 2) {
    chunks.add(sentences.skip(i).take(2).join(' '));
  }
  return chunks;
}

List<_JournalSpotlightFact> _buildJournalSpotlightFacts(BodyBlogEntry entry) {
  final snapshot = entry.snapshot;
  final facts = <_JournalSpotlightFact>[
    _JournalSpotlightFact(
      icon: Icons.mood_rounded,
      label: 'Mood',
      value: '${entry.moodEmoji} ${toBeginningOfSentenceCase(entry.mood)}',
    ),
    if (snapshot.sleepHours > 0)
      _JournalSpotlightFact(
        icon: Icons.bedtime_rounded,
        label: 'Sleep',
        value: '${snapshot.sleepHours.toStringAsFixed(1)} hours',
      ),
    if (snapshot.steps > 0)
      _JournalSpotlightFact(
        icon: Icons.directions_walk_rounded,
        label: 'Movement',
        value: '${NumberFormat.decimalPattern().format(snapshot.steps)} steps',
      ),
    if (snapshot.avgHeartRate > 0)
      _JournalSpotlightFact(
        icon: Icons.favorite_rounded,
        label: 'Pulse',
        value: '${snapshot.avgHeartRate} bpm',
      ),
    if (snapshot.city != null && snapshot.city!.trim().isNotEmpty)
      _JournalSpotlightFact(
        icon: Icons.location_on_rounded,
        label: 'Place',
        value: snapshot.city!.trim(),
      ),
  ];
  return facts.take(4).toList();
}

List<_JournalMetricItem> _buildJournalMetricItems(BodySnapshot snapshot) {
  final items = <_JournalMetricItem>[];

  if (snapshot.steps > 0) {
    items.add(
      _JournalMetricItem(
        icon: Icons.directions_walk_rounded,
        label: 'Steps',
        value: NumberFormat.decimalPattern().format(snapshot.steps),
        caption: 'Movement through the day',
      ),
    );
  }
  if (snapshot.sleepHours > 0) {
    items.add(
      _JournalMetricItem(
        icon: Icons.bedtime_rounded,
        label: 'Sleep',
        value: '${snapshot.sleepHours.toStringAsFixed(1)} h',
        caption: 'Recovery window',
      ),
    );
  }
  if (snapshot.avgHeartRate > 0) {
    items.add(
      _JournalMetricItem(
        icon: Icons.favorite_rounded,
        label: 'Average heart rate',
        value: '${snapshot.avgHeartRate} bpm',
        caption: snapshot.restingHeartRate > 0
            ? 'Resting ${snapshot.restingHeartRate} bpm'
            : 'Cardio rhythm today',
      ),
    );
  }
  if (snapshot.caloriesBurned > 0) {
    items.add(
      _JournalMetricItem(
        icon: Icons.local_fire_department_rounded,
        label: 'Calories burned',
        value: snapshot.caloriesBurned.toStringAsFixed(0),
        caption: 'Energy expenditure',
      ),
    );
  }
  if (snapshot.distanceKm > 0) {
    items.add(
      _JournalMetricItem(
        icon: Icons.route_rounded,
        label: 'Distance',
        value: '${snapshot.distanceKm.toStringAsFixed(1)} km',
        caption: 'Ground covered',
      ),
    );
  }
  if (snapshot.workouts > 0) {
    items.add(
      _JournalMetricItem(
        icon: Icons.fitness_center_rounded,
        label: 'Workouts',
        value: '${snapshot.workouts}',
        caption: 'Training sessions logged',
      ),
    );
  }
  if (snapshot.temperatureC != null) {
    items.add(
      _JournalMetricItem(
        icon: Icons.thermostat_rounded,
        label: 'Temperature',
        value: '${snapshot.temperatureC!.toStringAsFixed(0)}°C',
        caption: snapshot.weatherDesc ?? 'Ambient conditions',
      ),
    );
  }
  if (snapshot.hrv != null) {
    items.add(
      _JournalMetricItem(
        icon: Icons.monitor_heart_rounded,
        label: 'HRV',
        value: snapshot.hrv!.toStringAsFixed(0),
        caption: 'Variability signal',
      ),
    );
  }

  return items;
}

List<_JournalContextItem> _buildJournalContextItems(BodySnapshot snapshot) {
  final items = <_JournalContextItem>[];

  if (snapshot.city != null && snapshot.city!.trim().isNotEmpty) {
    items.add(
      _JournalContextItem(
        icon: Icons.location_city_rounded,
        label: 'Location',
        value: snapshot.city!.trim(),
      ),
    );
  }
  if (snapshot.weatherDesc != null && snapshot.weatherDesc!.trim().isNotEmpty) {
    items.add(
      _JournalContextItem(
        icon: Icons.cloud_outlined,
        label: 'Weather',
        value: snapshot.weatherDesc!.trim(),
      ),
    );
  }
  if (snapshot.aqiUs != null) {
    items.add(
      _JournalContextItem(
        icon: Icons.air_rounded,
        label: 'Air quality',
        value: 'AQI ${snapshot.aqiUs}',
      ),
    );
  }
  if (snapshot.uvIndex != null) {
    items.add(
      _JournalContextItem(
        icon: Icons.wb_sunny_rounded,
        label: 'UV',
        value: snapshot.uvIndex!.toStringAsFixed(1),
      ),
    );
  }
  if (snapshot.calendarEvents.isNotEmpty) {
    items.add(
      _JournalContextItem(
        icon: Icons.event_note_rounded,
        label: 'Calendar',
        value: snapshot.calendarEvents.length == 1
            ? snapshot.calendarEvents.first
            : '${snapshot.calendarEvents.length} events on deck',
      ),
    );
  }

  return items;
}

class _JournalHeroPanel extends StatelessWidget {
  const _JournalHeroPanel({
    required this.headline,
    required this.previewText,
    required this.dateLabel,
    required this.moodEmoji,
    required this.moodLabel,
    required this.readTime,
    required this.badge,
    required this.spotlightFacts,
    this.action,
  });

  final String headline;
  final String previewText;
  final String dateLabel;
  final String moodEmoji;
  final String moodLabel;
  final String readTime;
  final Widget badge;
  final List<_JournalSpotlightFact> spotlightFacts;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  const Color(0xFF1A1B22),
                  primary.withValues(alpha: 0.18),
                  const Color(0xFF101117),
                ]
              : [
                  const Color(0xFFFFFCF8),
                  primary.withValues(alpha: 0.12),
                  Colors.white,
                ],
        ),
        border: Border.all(
          color: primary.withValues(alpha: dark ? 0.18 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: dark ? 0.18 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _JournalMetaPill(
                icon: Icons.auto_stories_rounded,
                text: dateLabel,
              ),
              _JournalMetaPill(icon: Icons.schedule_rounded, text: readTime),
              badge,
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: dark ? Colors.white : const Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      previewText,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        height: 1.7,
                        fontWeight: FontWeight.w400,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.74)
                            : const Color(0xFF3E3B3B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 74,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: (dark ? Colors.white : primary).withValues(
                    alpha: dark ? 0.06 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: primary.withValues(alpha: dark ? 0.18 : 0.12),
                  ),
                ),
                child: Column(
                  children: [
                    Text(moodEmoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 8),
                    Text(
                      moodLabel,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.7)
                            : primary.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (spotlightFacts.isNotEmpty) ...[
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: spotlightFacts
                  .map((fact) => _JournalSpotlightCard(fact: fact))
                  .toList(),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    );
  }
}

class _JournalMetaPill extends StatelessWidget {
  const _JournalMetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (dark ? Colors.white : primary).withValues(
          alpha: dark ? 0.06 : 0.08,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: primary.withValues(alpha: dark ? 0.16 : 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: dark ? Colors.white70 : primary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalSpotlightCard extends StatelessWidget {
  const _JournalSpotlightCard({required this.fact});

  final _JournalSpotlightFact fact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 136),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (dark ? Colors.white : primary).withValues(
            alpha: dark ? 0.08 : 0.10,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: dark ? 0.18 : 0.10),
            ),
            child: Icon(fact.icon, size: 18, color: primary),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fact.label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: dark ? Colors.white30 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fact.value,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalGlassSection extends StatelessWidget {
  const _JournalGlassSection({
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.035)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : primary.withValues(alpha: 0.08),
        ),
        boxShadow: [
          if (!dark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: dark ? Colors.white24 : Colors.black38,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: dark ? Colors.white : const Color(0xFF181818),
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _JournalQuoteCallout extends StatelessWidget {
  const _JournalQuoteCallout({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: dark ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: primary.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.7,
              fontStyle: FontStyle.italic,
              color: dark ? Colors.white70 : const Color(0xFF3B3B42),
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalMetricGrid extends StatelessWidget {
  const _JournalMetricGrid({required this.items});

  final List<_JournalMetricItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth > 640 ? 3 : 2;
        final itemWidth =
            (constraints.maxWidth - ((columnCount - 1) * 12)) / columnCount;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _JournalMetricCard(item: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _JournalMetricCard extends StatelessWidget {
  const _JournalMetricCard({required this.item});

  final _JournalMetricItem item;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : primary.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: dark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, size: 20, color: primary),
          ),
          const SizedBox(height: 14),
          Text(
            item.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: dark ? Colors.white30 : Colors.black38,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
          if (item.caption != null) ...[
            const SizedBox(height: 6),
            Text(
              item.caption!,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.5,
                color: dark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JournalContextChip extends StatelessWidget {
  const _JournalContextChip({required this.item});

  final _JournalContextItem item;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 16, color: primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: dark ? Colors.white30 : Colors.black38,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JournalPrimaryButton extends StatelessWidget {
  const _JournalPrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
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
//  SENSOR STATUS ROW — data-source indicators with present/missing state
// ═════════════════════════════════════════════════════════════════════════════

class _SensorSpec {
  final IconData icon;
  final String label;
  final bool present;
  final String? valueText;

  const _SensorSpec({
    required this.icon,
    required this.label,
    required this.present,
    this.valueText,
  });
}

List<_SensorSpec> _buildSensorSpecs(BodySnapshot s) => [
  _SensorSpec(
    icon: Icons.directions_walk_rounded,
    label: 'Steps',
    present: s.steps > 0,
    valueText: s.steps > 0 ? '${s.steps} steps' : null,
  ),
  _SensorSpec(
    icon: Icons.bedtime_rounded,
    label: 'Sleep',
    present: s.sleepHours > 0,
    valueText: s.sleepHours > 0 ? '${s.sleepHours.toStringAsFixed(1)} h' : null,
  ),
  _SensorSpec(
    icon: Icons.favorite_rounded,
    label: 'Heart rate',
    present: s.avgHeartRate > 0,
    valueText: s.avgHeartRate > 0 ? '${s.avgHeartRate} bpm' : null,
  ),
  _SensorSpec(
    icon: Icons.local_fire_department_rounded,
    label: 'Calories',
    present: s.caloriesBurned > 0,
    valueText: s.caloriesBurned > 0
        ? '${s.caloriesBurned.toStringAsFixed(0)} kcal'
        : null,
  ),
  _SensorSpec(
    icon: Icons.route_rounded,
    label: 'Distance',
    present: s.distanceKm > 0,
    valueText: s.distanceKm > 0
        ? '${s.distanceKm.toStringAsFixed(1)} km'
        : null,
  ),
  _SensorSpec(
    icon: Icons.fitness_center_rounded,
    label: 'Workouts',
    present: s.workouts > 0,
    valueText: s.workouts > 0
        ? '${s.workouts} session${s.workouts > 1 ? "s" : ""}'
        : null,
  ),
  _SensorSpec(
    icon: Icons.thermostat_rounded,
    label: 'Temperature',
    present: s.temperatureC != null,
    valueText: s.temperatureC != null
        ? '${s.temperatureC!.toStringAsFixed(0)} °C'
        : null,
  ),
  _SensorSpec(
    icon: Icons.air_rounded,
    label: 'Air quality',
    present: s.aqiUs != null,
    valueText: s.aqiUs != null ? 'AQI ${s.aqiUs}' : null,
  ),
  _SensorSpec(
    icon: Icons.wb_sunny_rounded,
    label: 'UV index',
    present: s.uvIndex != null,
    valueText: s.uvIndex != null ? 'UV ${s.uvIndex!.toStringAsFixed(1)}' : null,
  ),
  _SensorSpec(
    icon: Icons.location_on_rounded,
    label: 'Location',
    present: s.city != null,
    valueText: s.city,
  ),
  _SensorSpec(
    icon: Icons.event_rounded,
    label: 'Calendar',
    present: s.calendarEvents.isNotEmpty,
    valueText: s.calendarEvents.isNotEmpty
        ? '${s.calendarEvents.length} event${s.calendarEvents.length > 1 ? "s" : ""}'
        : null,
  ),
];

/// Compact strip of sensor-source pictos.
///
/// Coloured circles = data was available and used in this entry's story.
/// Muted outlines   = sensor was queried but returned no data.
class _SensorStatusRow extends StatelessWidget {
  const _SensorStatusRow({required this.snapshot});
  final BodySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final specs = _buildSensorSpecs(snapshot);

    // Skip render if the entire snapshot is empty.
    if (specs.every((s) => !s.present)) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DATA SOURCES',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            color: dark ? Colors.white24 : Colors.black26,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: specs
              .map(
                (spec) => _SensorDot(spec: spec, dark: dark, primary: primary),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _SensorDot extends StatelessWidget {
  const _SensorDot({
    required this.spec,
    required this.dark,
    required this.primary,
  });

  final _SensorSpec spec;
  final bool dark;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final tooltipMsg = spec.present
        ? '${spec.label}${spec.valueText != null ? ": ${spec.valueText!}" : ""}'
        : '${spec.label}: not available';

    return Tooltip(
      message: tooltipMsg,
      preferBelow: true,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: spec.present
              ? primary.withValues(alpha: dark ? 0.16 : 0.09)
              : Colors.transparent,
          border: Border.all(
            color: spec.present
                ? primary.withValues(alpha: dark ? 0.32 : 0.20)
                : (dark
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.black.withValues(alpha: 0.07)),
            width: 1,
          ),
        ),
        child: Icon(
          spec.icon,
          size: 15,
          color: spec.present
              ? primary.withValues(alpha: 0.80)
              : (dark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.16)),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Stylish separator: faint gradient rule + subtle glow ──────────
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                primary.withValues(alpha: dark ? 0.35 : 0.25),
                primary.withValues(alpha: dark ? 0.55 : 0.40),
                primary.withValues(alpha: dark ? 0.35 : 0.25),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const SizedBox(height: 1),
        // ── Soft glow blur beneath the line ───────────────────────────────
        Container(
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.0,
              colors: [
                primary.withValues(alpha: dark ? 0.12 : 0.08),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
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
        ),
      ],
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
//  SHARE FAB — floating share button, bottom-right of the content area
// ═════════════════════════════════════════════════════════════════════════════

class _ShareFab extends StatelessWidget {
  const _ShareFab({required this.sharing, required this.onShare});
  final bool sharing;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Solid pill: icon + label so thumb can't miss it
    final bg = dark ? const Color(0xFF2C2C2E) : const Color(0xFFE8E8ED);
    return AnimatedOpacity(
      opacity: onShare != null ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: sharing ? null : onShare,
          borderRadius: BorderRadius.circular(28),
          splashColor: (dark ? Colors.white : Colors.black).withValues(
            alpha: 0.12,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: sharing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: dark ? Colors.white60 : Colors.black45,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.ios_share_rounded,
                        size: 17,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Share',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: dark ? Colors.white : Colors.black87,
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

// ─────────────────────────────────────────────────────────────────────────────
//  RAW DATA BADGE — shown on cards when AI has not generated content yet
// ─────────────────────────────────────────────────────────────────────────────

class _RawDataBadge extends StatelessWidget {
  const _RawDataBadge();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? Colors.white38 : Colors.black38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.data_usage_rounded, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            'Raw data',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PENDING AI PANEL — shown in the detail view when fullBody is empty
// ─────────────────────────────────────────────────────────────────────────────

class _PendingAiPanel extends StatelessWidget {
  const _PendingAiPanel({required this.snapshot});
  final BodySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dimColor = dark ? Colors.white54 : Colors.black45;
    final labelStyle = GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      color: dimColor,
    );
    final valueStyle = GoogleFonts.inter(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: dark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
    );

    final hasAnyData =
        snapshot.steps > 0 ||
        snapshot.sleepHours > 0 ||
        snapshot.avgHeartRate > 0 ||
        snapshot.caloriesBurned > 0 ||
        snapshot.temperatureC != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasAnyData) ...[
          // ── no data state ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: (dark ? Colors.white : Colors.black).withValues(
                alpha: 0.04,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.sensors_off_rounded,
                  size: 32,
                  color: dimColor.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No health data collected yet',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Grant health permissions so the app can read your\nsteps, sleep and heart rate.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.6,
                    color: dimColor,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // ── raw data grid ──
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (snapshot.sleepHours > 0)
                _DataTile(
                  icon: Icons.bedtime_rounded,
                  label: 'Sleep',
                  value: '${snapshot.sleepHours.toStringAsFixed(1)} h',
                ),
              if (snapshot.steps > 0)
                _DataTile(
                  icon: Icons.directions_walk_rounded,
                  label: 'Steps',
                  value: snapshot.steps.toString(),
                ),
              if (snapshot.avgHeartRate > 0)
                _DataTile(
                  icon: Icons.favorite_rounded,
                  label: 'Heart rate',
                  value: '${snapshot.avgHeartRate} bpm',
                ),
              if (snapshot.caloriesBurned > 0)
                _DataTile(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Calories',
                  value: '${snapshot.caloriesBurned.toStringAsFixed(0)} kcal',
                ),
              if (snapshot.distanceKm > 0)
                _DataTile(
                  icon: Icons.route_rounded,
                  label: 'Distance',
                  value: '${snapshot.distanceKm.toStringAsFixed(1)} km',
                ),
              if (snapshot.temperatureC != null)
                _DataTile(
                  icon: Icons.thermostat_rounded,
                  label: snapshot.city ?? 'Temp',
                  value:
                      '${snapshot.temperatureC!.toStringAsFixed(0)}°C'
                      '${snapshot.weatherDesc != null ? "  ${snapshot.weatherDesc}" : ""}',
                ),
              if (snapshot.aqiUs != null)
                _DataTile(
                  icon: Icons.air_rounded,
                  label: 'AQI',
                  value: snapshot.aqiUs.toString(),
                ),
            ],
          ),
          if (snapshot.calendarEvents.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Events today', style: labelStyle),
            const SizedBox(height: 6),
            for (final ev in snapshot.calendarEvents)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: primary.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(ev, style: valueStyle)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 20),
          // ── AI pending note ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: dark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: primary.withValues(alpha: dark ? 0.20 : 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI insights not yet generated. Tap ✦ in the header to write your entry.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: dark ? Colors.white60 : Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DATA TILE — compact metric card used in _PendingAiPanel
// ─────────────────────────────────────────────────────────────────────────────

class _DataTile extends StatelessWidget {
  const _DataTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primary.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: dark ? Colors.white38 : Colors.black38,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: dark
                      ? Colors.white.withValues(alpha: 0.87)
                      : Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  REFRESH JOURNEY OVERLAY — immersive pipeline shown while regenerating
// ═════════════════════════════════════════════════════════════════════════════

/// Phrases that rotate during the AI composing stage to keep the user engaged.
const _refreshJourneyPhrases = [
  'Weaving your day together...',
  'Connecting the dots...',
  'Finding your narrative arc...',
  'Crafting every sentence...',
  'Almost ready to share...',
  'Putting the finishing touches...',
];

class _RefreshJourneyOverlay extends StatefulWidget {
  const _RefreshJourneyOverlay({required this.stage, this.toneName});

  /// 0 = sensing, 1 = drafting, 2 = composing, 3 = done
  final int stage;
  final String? toneName;

  @override
  State<_RefreshJourneyOverlay> createState() => _RefreshJourneyOverlayState();
}

class _RefreshJourneyOverlayState extends State<_RefreshJourneyOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _breatheCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _entryFade;
  late final AnimationController _progressCtrl;
  late final List<AnimationController> _stageFadeCtrls;
  late final List<Animation<double>> _stageFadeAnims;
  Timer? _phraseTimer;
  int _phraseIndex = 0;
  int _elapsed = 0;
  late final Stopwatch _sw;

  @override
  void initState() {
    super.initState();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _entryFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Fade controllers for each pipeline stage row
    _stageFadeCtrls = List.generate(
      4,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      ),
    );
    _stageFadeAnims = _stageFadeCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();

    // Stagger stage rows in
    for (var i = 0; i < _stageFadeCtrls.length; i++) {
      Future.delayed(Duration(milliseconds: 120 * i), () {
        if (mounted) _stageFadeCtrls[i].forward();
      });
    }

    _sw = Stopwatch()..start();
    _phraseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = _sw.elapsed.inSeconds;
        if (_elapsed > 0 && _elapsed % 4 == 0) {
          _phraseIndex = (_phraseIndex + 1) % _refreshJourneyPhrases.length;
        }
      });
    });
  }

  @override
  void dispose() {
    _phraseTimer?.cancel();
    _breatheCtrl.dispose();
    _shimmerCtrl.dispose();
    _entryFade.dispose();
    _progressCtrl.dispose();
    for (final c in _stageFadeCtrls) {
      c.dispose();
    }
    _sw.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final stage = widget.stage;
    final isDone = stage >= 3;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _entryFade, curve: Curves.easeOut),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedBuilder(
            animation: _breatheCtrl,
            builder: (context, _) => Container(
              color: dark
                  ? Colors.black.withValues(alpha: 0.82)
                  : Colors.white.withValues(alpha: 0.88),
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 1.2 + _breatheCtrl.value * 0.2,
                    colors: [
                      primary.withValues(
                        alpha:
                            (dark ? 0.05 : 0.03) +
                            _breatheCtrl.value * (dark ? 0.04 : 0.025),
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Breathing orb ──
                      Transform.scale(
                        scale: isDone ? 1.05 : 0.92 + _breatheCtrl.value * 0.08,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? primary.withValues(alpha: 0.15)
                                : primary.withValues(alpha: 0.06),
                            border: Border.all(
                              color: isDone
                                  ? primary.withValues(alpha: 0.5)
                                  : primary.withValues(
                                      alpha: 0.25 + _breatheCtrl.value * 0.2,
                                    ),
                              width: 1.5,
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: isDone
                                ? Icon(
                                    Icons.check_rounded,
                                    key: const ValueKey('done'),
                                    color: primary,
                                    size: 26,
                                  )
                                : Icon(
                                    Icons.auto_awesome_rounded,
                                    key: const ValueKey('loading'),
                                    color: primary.withValues(
                                      alpha: 0.5 + _breatheCtrl.value * 0.4,
                                    ),
                                    size: 24,
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Tone badge ──
                      if (widget.toneName != null)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: isDone ? 0.4 : 0.8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: primary.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              '${widget.toneName} voice',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: primary.withValues(alpha: 0.7),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 36),

                      // ── Pipeline stages ──
                      _RefreshPipelineRow(
                        index: 0,
                        activeStage: stage,
                        fade: _stageFadeAnims[0],
                        breathe: _breatheCtrl,
                        shimmer: _shimmerCtrl,
                        primary: primary,
                        dark: dark,
                        label: 'Reading your body',
                        description: 'Steps · Heart rate · Sleep · GPS',
                        icon: Icons.sensors_rounded,
                      ),
                      _RefreshPipelineConnector(primary: primary, dark: dark),
                      _RefreshPipelineRow(
                        index: 1,
                        activeStage: stage,
                        fade: _stageFadeAnims[1],
                        breathe: _breatheCtrl,
                        shimmer: _shimmerCtrl,
                        primary: primary,
                        dark: dark,
                        label: 'Saving snapshot',
                        description: 'Protecting your data first',
                        icon: Icons.save_outlined,
                      ),
                      _RefreshPipelineConnector(primary: primary, dark: dark),
                      _RefreshPipelineRow(
                        index: 2,
                        activeStage: stage,
                        fade: _stageFadeAnims[2],
                        breathe: _breatheCtrl,
                        shimmer: _shimmerCtrl,
                        primary: primary,
                        dark: dark,
                        label: 'AI composing',
                        description: 'Writing your personal narrative',
                        icon: Icons.auto_awesome_rounded,
                      ),
                      _RefreshPipelineConnector(primary: primary, dark: dark),
                      _RefreshPipelineRow(
                        index: 3,
                        activeStage: stage,
                        fade: _stageFadeAnims[3],
                        breathe: _breatheCtrl,
                        shimmer: _shimmerCtrl,
                        primary: primary,
                        dark: dark,
                        label: 'Ready',
                        description: 'Your story has been written',
                        icon: Icons.auto_stories_rounded,
                      ),

                      const SizedBox(height: 40),

                      // ── Rotating phrase ──
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        child: isDone
                            ? Text(
                                'Your entry is ready ✦',
                                key: const ValueKey('done-phrase'),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: primary.withValues(alpha: 0.7),
                                ),
                              )
                            : Text(
                                _refreshJourneyPhrases[_phraseIndex],
                                key: ValueKey<int>(_phraseIndex),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 0.3,
                                  color: dark
                                      ? Colors.white.withValues(alpha: 0.30)
                                      : Colors.black.withValues(alpha: 0.30),
                                ),
                              ),
                      ),

                      const SizedBox(height: 10),

                      // ── Elapsed time ──
                      if (_elapsed >= 5)
                        Text(
                          '${_elapsed}s',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: dark
                                ? Colors.white.withValues(alpha: 0.20)
                                : Colors.black.withValues(alpha: 0.20),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Refresh pipeline row ────────────────────────────────────────────────────

class _RefreshPipelineRow extends StatelessWidget {
  const _RefreshPipelineRow({
    required this.index,
    required this.activeStage,
    required this.fade,
    required this.breathe,
    required this.shimmer,
    required this.primary,
    required this.dark,
    required this.label,
    required this.description,
    required this.icon,
  });

  final int index;
  final int activeStage;
  final Animation<double> fade;
  final Animation<double> breathe;
  final Animation<double> shimmer;
  final Color primary;
  final bool dark;
  final String label;
  final String description;
  final IconData icon;

  bool get _isDone => index < activeStage;
  bool get _isActive => index == activeStage;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: AnimatedBuilder(
        animation: Listenable.merge([breathe, shimmer]),
        builder: (context, _) {
          final labelColor = _isDone
              ? primary
              : _isActive
              ? (dark ? Colors.white.withValues(alpha: 0.85) : Colors.black87)
              : (dark ? Colors.white24 : Colors.black26);
          final subColor = _isDone
              ? primary.withValues(alpha: 0.55)
              : _isActive
              ? (dark ? Colors.white54 : Colors.black45)
              : (dark ? Colors.white12 : Colors.black12);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                // ── Status indicator ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isDone
                        ? primary.withValues(alpha: 0.12)
                        : _isActive
                        ? primary.withValues(alpha: 0.07 + breathe.value * 0.06)
                        : Colors.transparent,
                    border: Border.all(
                      color: _isDone
                          ? primary.withValues(alpha: 0.5)
                          : _isActive
                          ? primary.withValues(alpha: 0.4 + breathe.value * 0.5)
                          : (dark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.10)),
                      width: _isActive ? 2 : 1.2,
                    ),
                  ),
                  child: _isDone
                      ? Icon(Icons.check_rounded, size: 14, color: primary)
                      : _isActive
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primary.withValues(
                                alpha: 0.45 + breathe.value * 0.55,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),

                const SizedBox(width: 14),

                // ── Icon ──
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isDone
                      ? 0.5
                      : _isActive
                      ? 0.35 + shimmer.value * 0.55
                      : 0.15,
                  child: Icon(
                    icon,
                    size: 16,
                    color: _isDone
                        ? primary
                        : (dark ? Colors.white70 : Colors.black54),
                  ),
                ),

                const SizedBox(width: 10),

                // ── Text ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: _isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: labelColor,
                        ),
                        child: Text(label),
                      ),
                      const SizedBox(height: 1),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                          color: subColor,
                        ),
                        child: Text(
                          _isActive ? '$description...' : description,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Refresh pipeline connector ──────────────────────────────────────────────

class _RefreshPipelineConnector extends StatelessWidget {
  const _RefreshPipelineConnector({required this.primary, required this.dark});
  final Color primary;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 13, top: 2, bottom: 2),
      child: Container(
        width: 1.5,
        height: 18,
        color: dark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  ZEN LOADER — engaging rotating phrases with elapsed time
// ═════════════════════════════════════════════════════════════════════════════

const _zenPhrases = [
  'Sensing your rhythm...',
  'Reading between the heartbeats...',
  'Composing your story...',
  'Weaving your day together...',
  'Finding the thread...',
  'Listening to your body...',
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
//  FIRST-VISIT BOOTSTRAP — immersive pipeline shown on very first app open
// ═════════════════════════════════════════════════════════════════════════════

enum _StageState { pending, active, done }

class _FirstVisitBootstrap extends StatefulWidget {
  const _FirstVisitBootstrap();

  @override
  State<_FirstVisitBootstrap> createState() => _FirstVisitBootstrapState();
}

class _FirstVisitBootstrapState extends State<_FirstVisitBootstrap>
    with TickerProviderStateMixin {
  late final AnimationController _breatheCtrl;
  late final AnimationController _shimmerCtrl;
  late final List<AnimationController> _fadeCtrls;
  late final List<Animation<double>> _fadeAnims;

  int _stageIndex = 0;
  Timer? _stageTimer;

  // Approx wall-clock for each stage before auto-advancing.
  static const _stageDurations = [
    Duration(seconds: 6), // Sensing  — sensor reads
    Duration(seconds: 28), // Writing  — AI call
    Duration(seconds: 60), // Patterns — belt-and-suspenders
  ];

  @override
  void initState() {
    super.initState();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    // One fade controller per stage — staggered entry animation.
    _fadeCtrls = List.generate(
      3,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
    );
    _fadeAnims = _fadeCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();

    _fadeCtrls[0].forward();
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _fadeCtrls[1].forward();
    });
    Future.delayed(const Duration(milliseconds: 360), () {
      if (mounted) _fadeCtrls[2].forward();
    });

    _scheduleStageAdvance();
  }

  void _scheduleStageAdvance() {
    if (_stageIndex >= _stageDurations.length - 1) return;
    _stageTimer = Timer(_stageDurations[_stageIndex], () {
      if (!mounted) return;
      setState(() => _stageIndex++);
      _scheduleStageAdvance();
    });
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _shimmerCtrl.dispose();
    for (final c in _fadeCtrls) {
      c.dispose();
    }
    _stageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _breatheCtrl,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.25),
              radius: 1.1 + _breatheCtrl.value * 0.25,
              colors: [
                primary.withValues(
                  alpha:
                      (dark ? 0.06 : 0.04) +
                      _breatheCtrl.value * (dark ? 0.05 : 0.03),
                ),
                Colors.transparent,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── breathing orb ──────────────────────────────────
                Center(
                  child: Transform.scale(
                    scale: 0.90 + _breatheCtrl.value * 0.10,
                    child: Opacity(
                      opacity: 0.3 + _breatheCtrl.value * 0.45,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: primary.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                          color: primary.withValues(alpha: 0.07),
                        ),
                        child: Icon(
                          Icons.spa_outlined,
                          color: primary,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 52),

                // ── pipeline ────────────────────────────────────────
                _PipelineStage(
                  index: 0,
                  activeIndex: _stageIndex,
                  fade: _fadeAnims[0],
                  breathe: _breatheCtrl,
                  shimmer: _shimmerCtrl,
                  primary: primary,
                  dark: dark,
                  label: 'Sensing',
                  description: 'GPS · Health · Calendar',
                  icons: const [
                    Icons.explore_outlined,
                    Icons.favorite_outline,
                    Icons.event_outlined,
                  ],
                ),

                _PipelineConnector(primary: primary, dark: dark),

                _PipelineStage(
                  index: 1,
                  activeIndex: _stageIndex,
                  fade: _fadeAnims[1],
                  breathe: _breatheCtrl,
                  shimmer: _shimmerCtrl,
                  primary: primary,
                  dark: dark,
                  label: 'Writing',
                  description: 'AI composing your first entry',
                  icons: const [Icons.auto_awesome_rounded],
                ),

                _PipelineConnector(primary: primary, dark: dark),

                _PipelineStage(
                  index: 2,
                  activeIndex: _stageIndex,
                  fade: _fadeAnims[2],
                  breathe: _breatheCtrl,
                  shimmer: _shimmerCtrl,
                  primary: primary,
                  dark: dark,
                  label: 'Patterns',
                  description: 'Building your personal baseline',
                  icons: const [Icons.bar_chart_rounded],
                ),

                const SizedBox(height: 52),

                // ── footnote ────────────────────────────────────────
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    child: Text(
                      _stageIndex == 0
                          ? 'Setting up · first run only'
                          : _stageIndex == 1
                          ? 'Composing your story...'
                          : 'Almost there...',
                      key: ValueKey<int>(_stageIndex),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.4,
                        color: dark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Pipeline stage ───────────────────────────────────────────────────────────

class _PipelineStage extends StatelessWidget {
  const _PipelineStage({
    required this.index,
    required this.activeIndex,
    required this.fade,
    required this.breathe,
    required this.shimmer,
    required this.primary,
    required this.dark,
    required this.label,
    required this.description,
    required this.icons,
  });

  final int index;
  final int activeIndex;
  final Animation<double> fade;
  final Animation<double> breathe;
  final Animation<double> shimmer;
  final Color primary;
  final bool dark;
  final String label;
  final String description;
  final List<IconData> icons;

  _StageState get _state {
    if (index < activeIndex) return _StageState.done;
    if (index == activeIndex) return _StageState.active;
    return _StageState.pending;
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _state == _StageState.active;
    final isDone = _state == _StageState.done;

    return FadeTransition(
      opacity: fade,
      child: AnimatedBuilder(
        animation: Listenable.merge([breathe, shimmer]),
        builder: (context, _) {
          final labelColor = isDone
              ? primary
              : isActive
              ? (dark ? Colors.white70 : Colors.black87)
              : (dark ? Colors.white24 : Colors.black26);
          final subColor = isDone
              ? primary.withValues(alpha: 0.65)
              : isActive
              ? (dark ? Colors.white54 : Colors.black45)
              : (dark ? Colors.white12 : Colors.black12);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── dot indicator ──
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone
                          ? primary.withValues(alpha: 0.15)
                          : isActive
                          ? primary.withValues(
                              alpha: 0.10 + breathe.value * 0.08,
                            )
                          : Colors.transparent,
                      border: Border.all(
                        color: isDone
                            ? primary
                            : isActive
                            ? primary.withValues(
                                alpha: 0.55 + breathe.value * 0.45,
                              )
                            : (dark ? Colors.white12 : Colors.black12),
                        width: isActive ? 2 : 1.5,
                      ),
                    ),
                    child: isDone
                        ? Icon(Icons.check, size: 12, color: primary)
                        : isActive
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primary.withValues(
                                  alpha: 0.5 + breathe.value * 0.5,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),

                // ── text + icons ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: labelColor,
                            ),
                            child: Text(label),
                          ),
                          const SizedBox(width: 8),
                          // Show sensor icons next to label
                          for (final ic in icons)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                opacity: isDone
                                    ? 0.5
                                    : isActive
                                    ? 0.35 + shimmer.value * 0.55
                                    : 0.15,
                                child: Icon(
                                  ic,
                                  size: 13,
                                  color: isDone
                                      ? primary
                                      : (dark ? Colors.white : Colors.black87),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          color: subColor,
                        ),
                        child: Text(isActive ? '$description...' : description),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Thin vertical connector between pipeline stages ─────────────────────────

class _PipelineConnector extends StatelessWidget {
  const _PipelineConnector({required this.primary, required this.dark});

  final Color primary;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
      child: Container(
        width: 1.5,
        height: 22,
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08),
      ),
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
    final metricItems = _buildJournalMetricItems(_entry.snapshot);
    final contextItems = _buildJournalContextItems(_entry.snapshot);
    final paragraphs = _storyParagraphs(_entry.fullBody);
    final hasReflection =
        (_entry.userNote != null && _entry.userNote!.trim().isNotEmpty) ||
        _entry.userMood != null;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF09090B) : const Color(0xFFF6F4EF),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [
                    const Color(0xFF09090B),
                    const Color(0xFF13131A),
                    const Color(0xFF09090B),
                  ]
                : [
                    const Color(0xFFFCFBF8),
                    primary.withValues(alpha: 0.05),
                    const Color(0xFFF4F1EA),
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    _DetailTopButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    _DetailTopButton(
                      icon: _entry.userMood != null
                          ? null
                          : ((_entry.userNote ?? '').trim().isNotEmpty
                                ? Icons.edit_note_rounded
                                : Icons.add_comment_outlined),
                      label: _entry.userMood != null
                          ? _entry.userMood!
                          : ((_entry.userNote ?? '').trim().isNotEmpty
                                ? 'Edit note'
                                : 'Add note'),
                      onTap: _showNoteEditor,
                      isPrimary:
                          (_entry.userNote ?? '').trim().isNotEmpty ||
                          _entry.userMood != null,
                    ),
                    if (_isEntryToday) ...[
                      const SizedBox(width: 10),
                      _DetailTopButton(
                        icon: _aiRegenerating
                            ? null
                            : Icons.auto_awesome_rounded,
                        label: _aiRegenerating ? 'Writing…' : 'Rewrite',
                        onTap: _aiRegenerating ? null : _regenerateWithAi,
                        isPrimary: _entry.aiGenerated,
                        trailing: _aiRegenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _JournalHeroPanel(
                        headline: _entry.headline,
                        previewText: _entry.summary,
                        dateLabel: DateFormat(
                          'EEEE · MMMM d, y',
                        ).format(_entry.date),
                        moodEmoji: _entry.moodEmoji,
                        moodLabel: toBeginningOfSentenceCase(_entry.mood),
                        readTime: _estimateReadTime(
                          _entry.fullBody.isNotEmpty
                              ? _entry.fullBody
                              : _entry.summary,
                        ),
                        badge: _entry.aiGenerated
                            ? const _AiBadge()
                            : const _RawDataBadge(),
                        spotlightFacts: _buildJournalSpotlightFacts(_entry),
                      ),
                      const SizedBox(height: 18),
                      if (_entry.fullBody.isNotEmpty)
                        _JournalGlassSection(
                          eyebrow: 'Full journal',
                          title: 'Settle in for the long read',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < paragraphs.length; i++) ...[
                                Text(
                                  paragraphs[i],
                                  style: i == 0
                                      ? GoogleFonts.playfairDisplay(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w500,
                                          height: 1.7,
                                          color: dark
                                              ? Colors.white
                                              : const Color(0xFF1A1A1A),
                                        )
                                      : GoogleFonts.inter(
                                          fontSize: 16,
                                          height: 1.95,
                                          fontWeight: FontWeight.w400,
                                          color: dark
                                              ? Colors.white70
                                              : const Color(0xFF3B3B42),
                                        ),
                                ),
                                if (i != paragraphs.length - 1)
                                  const SizedBox(height: 20),
                              ],
                            ],
                          ),
                        )
                      else
                        _JournalGlassSection(
                          eyebrow: 'Narrative pending',
                          title: 'The story is still taking shape',
                          child: _PendingAiPanel(snapshot: _entry.snapshot),
                        ),
                      if (_entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _JournalGlassSection(
                          eyebrow: 'Themes',
                          title: 'A map of what defined the day',
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _entry.tags
                                .map((tag) => _Tag(label: tag))
                                .toList(),
                          ),
                        ),
                      ],
                      if (metricItems.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _JournalGlassSection(
                          eyebrow: 'Signals',
                          title: 'The body data behind the prose',
                          child: _JournalMetricGrid(items: metricItems),
                        ),
                      ],
                      if (contextItems.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _JournalGlassSection(
                          eyebrow: 'Context',
                          title: 'Environment, schedule, and atmosphere',
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: contextItems
                                .map((item) => _JournalContextChip(item: item))
                                .toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _JournalGlassSection(
                        eyebrow: 'Data sources',
                        title: 'What informed this journal entry',
                        child: _SensorStatusRow(snapshot: _entry.snapshot),
                      ),
                      const SizedBox(height: 18),
                      _JournalGlassSection(
                        eyebrow: 'Your reflection',
                        title: hasReflection
                            ? 'How you answered the day back'
                            : 'Add your voice to the record',
                        child: hasReflection
                            ? _JournalQuoteCallout(
                                label: _entry.userMood != null
                                    ? _moodLabel(_entry.userMood!)
                                    : 'Your note',
                                text: (_entry.userNote ?? '').trim().isNotEmpty
                                    ? _entry.userNote!.trim()
                                    : 'You recorded a feeling, even without a written note.',
                              )
                            : Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: _showNoteEditor,
                                  icon: const Icon(Icons.add_comment_outlined),
                                  label: Text(
                                    'Add a private note',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    side: BorderSide(
                                      color: primary.withValues(alpha: 0.22),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (_isEntryToday) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _JournalPrimaryButton(
                                label: hasReflection
                                    ? 'Refine reflection'
                                    : 'Add reflection',
                                icon: Icons.edit_outlined,
                                onTap: _showNoteEditor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _aiRegenerating
                                    ? null
                                    : _regenerateWithAi,
                                icon: _aiRegenerating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome_rounded),
                                label: Text(
                                  _aiRegenerating
                                      ? 'Writing…'
                                      : 'Rewrite story',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  side: BorderSide(
                                    color: primary.withValues(alpha: 0.22),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
}

class _DetailTopButton extends StatelessWidget {
  const _DetailTopButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.isPrimary = false,
    this.trailing,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isPrimary;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isPrimary
                ? primary.withValues(alpha: dark ? 0.18 : 0.10)
                : (dark ? Colors.white : Colors.black).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isPrimary
                  ? primary.withValues(alpha: 0.22)
                  : (dark ? Colors.white : Colors.black).withValues(
                      alpha: 0.08,
                    ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isPrimary
                      ? primary
                      : (dark ? Colors.white70 : Colors.black54),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isPrimary
                      ? primary
                      : (dark ? Colors.white70 : Colors.black54),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  VERSION HISTORY — bottom sheet + tile
// ═════════════════════════════════════════════════════════════════════════════

/// Draggable bottom sheet that shows the full version history for a given day.
class _VersionHistorySheet extends StatelessWidget {
  const _VersionHistorySheet({required this.date, required this.versions});

  final DateTime date;
  final List<BodyBlogVersion> versions;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final bg = dark ? const Color(0xFF1A1A1A) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: dark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 18, color: primary),
                  const SizedBox(width: 8),
                  Text(
                    'Day history  ·  ${DateFormat('MMM d').format(date)}',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: dark
                          ? Colors.white.withValues(alpha: 0.87)
                          : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${versions.length} version${versions.length != 1 ? 's' : ''}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: dark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: versions.isEmpty
                  ? Center(
                      child: Text(
                        'No history recorded yet.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: dark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: versions.length,
                      itemBuilder: (_, i) => _VersionTile(
                        version: versions[i],
                        isLatest: i == 0,
                        isLast: i == versions.length - 1,
                        dark: dark,
                        primary: primary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single row in the version history timeline.
class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.version,
    required this.isLatest,
    required this.isLast,
    required this.dark,
    required this.primary,
  });

  final BodyBlogVersion version;
  final bool isLatest;
  final bool isLast;
  final bool dark;
  final Color primary;

  String get _triggerLabel {
    switch (version.trigger) {
      case 'draft':
        return 'Draft saved';
      case 'ai_enriched':
        return 'AI written';
      case 'refresh':
        return 'Refreshed';
      case 'incremental':
        return 'Updated';
      case 'regen':
        return 'Regenerated';
      default:
        return version.trigger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(version.generatedAt.toLocal());

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // timeline track
          SizedBox(
            width: 32,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLatest
                        ? primary
                        : (dark ? Colors.white24 : Colors.black26),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.only(top: 4),
                      color: dark
                          ? Colors.white12
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // content card
          Expanded(
            child: GestureDetector(
              onTap: () => _showDetail(context),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: isLatest
                      ? Border.all(
                          color: primary.withValues(alpha: 0.18),
                          width: 1,
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          timeStr,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isLatest
                                ? primary
                                : (dark ? Colors.white54 : Colors.black45),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isLatest
                                ? primary.withValues(alpha: 0.12)
                                : (dark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _triggerLabel.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: isLatest
                                  ? primary
                                  : (dark ? Colors.white54 : Colors.black45),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          version.moodEmoji,
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (version.aiGenerated) ...[
                          const SizedBox(width: 4),
                          const _AiBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      version.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.87)
                            : Colors.black87,
                      ),
                    ),
                    if (version.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        version.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: dark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormat('HH:mm').format(version.generatedAt.toLocal()),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _triggerLabel.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: dark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${version.moodEmoji}  ${version.mood.toUpperCase()}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: dark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  version.headline,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  version.summary,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.65,
                    color: dark ? Colors.white70 : Colors.black54,
                  ),
                ),
                if (version.fullBody.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: 32,
                    height: 1.5,
                    color: primary.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    version.fullBody,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.7,
                      fontWeight: FontWeight.w300,
                      color: dark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(
                      'Close',
                      style: GoogleFonts.inter(fontSize: 13),
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

// ═════════════════════════════════════════════════════════════════════════════
//  TONE SELECTOR BOTTOM SHEET — chat-like interface to generate new entry
// ═════════════════════════════════════════════════════════════════════════════

class _ToneSelectorBottomSheet extends StatelessWidget {
  const _ToneSelectorBottomSheet();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final bgColor = dark ? const Color(0xFF1C1C1E) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Material(
        elevation: 16,
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: 0.2,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Header with icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: _ShimmerAiIcon(size: 28, dark: dark)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Generate a New Entry',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Collect fresh data from your body and create a new story with your chosen tone',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: dark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Tone options label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose Your Tone',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white54 : Colors.black45,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Tone options (scrollable)
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).padding.bottom + 100,
                ),
                children: [
                  _ToneOption(
                    icon: Icons.auto_awesome,
                    label: 'Default',
                    description: 'Warm, wise, intimate narrator',
                    tone: 'default',
                    dark: dark,
                  ),
                  const SizedBox(height: 12),
                  _ToneOption(
                    icon: Icons.rocket_launch,
                    label: 'Motivational',
                    description: 'Energizing, encouraging coach',
                    tone: 'motivational',
                    dark: dark,
                  ),
                  const SizedBox(height: 12),
                  _ToneOption(
                    icon: Icons.auto_stories,
                    label: 'Poetic',
                    description: 'Lyrical, metaphorical, artistic',
                    tone: 'poetic',
                    dark: dark,
                  ),
                  const SizedBox(height: 12),
                  _ToneOption(
                    icon: Icons.science,
                    label: 'Scientific',
                    description: 'Precise, analytical, data-focused',
                    tone: 'scientific',
                    dark: dark,
                  ),
                  const SizedBox(height: 12),
                  _ToneOption(
                    icon: Icons.sentiment_very_satisfied,
                    label: 'Humorous',
                    description: 'Playful, lighthearted, witty',
                    tone: 'humorous',
                    dark: dark,
                  ),
                  const SizedBox(height: 12),
                  _ToneOption(
                    icon: Icons.spa,
                    label: 'Minimalist',
                    description: 'Concise, direct, zen-like',
                    tone: 'minimalist',
                    dark: dark,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneOption extends StatelessWidget {
  const _ToneOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.tone,
    required this.dark,
  });

  final IconData icon;
  final String label;
  final String description;
  final String tone;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () => Navigator.of(context).pop(tone),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dark ? Colors.white10 : Colors.black12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: dark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: dark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SHIMMER AI ICON — subtle color-cycling sparkle icon for AI actions
// ═════════════════════════════════════════════════════════════════════════════

class _ShimmerAiIcon extends StatefulWidget {
  const _ShimmerAiIcon({required this.size, required this.dark});
  final double size;
  final bool dark;

  @override
  State<_ShimmerAiIcon> createState() => _ShimmerAiIconState();
}

class _ShimmerAiIconState extends State<_ShimmerAiIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  /// Palette: soft gold → primary → lavender → soft gold (loop)
  static const _colors = [
    Color(0xFFD4A853), // warm gold
    Color(0xFFB388FF), // soft lavender
    Color(0xFF82B1FF), // light periwinkle
    Color(0xFFD4A853), // back to gold for smooth loop
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        // Smooth sine-based oscillation for an organic feel
        final t = (math.sin(_ctrl.value * math.pi * 2) + 1) / 2;

        // Interpolate through the colour stops
        final colorIndex = (_ctrl.value * (_colors.length - 1)).floor();
        final localT = (_ctrl.value * (_colors.length - 1)) - colorIndex;
        final color = Color.lerp(
          _colors[colorIndex],
          _colors[(colorIndex + 1).clamp(0, _colors.length - 1)],
          localT,
        )!;

        // Gentle opacity pulse (0.45 → 0.75) so it breathes
        final alpha = 0.45 + t * 0.30;

        return Icon(
          Icons.auto_awesome_rounded,
          size: widget.size,
          color: color.withValues(alpha: alpha),
        );
      },
    );
  }
}
