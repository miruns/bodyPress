import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/capture_entry.dart';
import '../../../core/services/service_providers.dart';
import '../../shared/widgets/app_header.dart';

// ── Data providers ──────────────────────────────────────────────────────────

final _allCapturesProvider = FutureProvider.autoDispose<List<CaptureEntry>>(
  (ref) => ref.read(captureServiceProvider).getCaptures(),
);

// ── Aggregated patterns ─────────────────────────────────────────────────────

class _PatternSummary {
  final int totalCaptures;
  final int analyzedCaptures;
  final List<MapEntry<String, int>> topThemes;
  final List<MapEntry<String, int>> topTags;
  final List<MapEntry<String, int>> topSignals;
  final Map<String, int> energyBreakdown;
  final List<_MomentSnapshot> recentMoments;

  const _PatternSummary({
    required this.totalCaptures,
    required this.analyzedCaptures,
    required this.topThemes,
    required this.topTags,
    required this.topSignals,
    required this.energyBreakdown,
    required this.recentMoments,
  });
}

class _MomentSnapshot {
  final DateTime timestamp;
  final String summary;
  final String energyLevel;
  final List<String> tags;
  final String? userMood;

  const _MomentSnapshot({
    required this.timestamp,
    required this.summary,
    required this.energyLevel,
    required this.tags,
    this.userMood,
  });
}

_PatternSummary _buildSummary(List<CaptureEntry> captures) {
  final withMeta = captures.where((c) => c.aiMetadata != null).toList();

  final themeCount = <String, int>{};
  final tagCount = <String, int>{};
  final signalCount = <String, int>{};
  final energyCount = <String, int>{'high': 0, 'medium': 0, 'low': 0};

  for (final c in withMeta) {
    final m = c.aiMetadata!;
    for (final t in m.themes) {
      themeCount[t] = (themeCount[t] ?? 0) + 1;
    }
    for (final t in m.tags) {
      tagCount[t] = (tagCount[t] ?? 0) + 1;
    }
    for (final s in m.notableSignals) {
      signalCount[s] = (signalCount[s] ?? 0) + 1;
    }
    final level = m.energyLevel.toLowerCase();
    if (energyCount.containsKey(level)) {
      energyCount[level] = energyCount[level]! + 1;
    }
  }

  List<MapEntry<String, int>> top(Map<String, int> map, {int n = 12}) =>
      (map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(n)
          .toList();

  final recentMoments = withMeta
      .take(20)
      .map(
        (c) => _MomentSnapshot(
          timestamp: c.timestamp,
          summary: c.aiMetadata!.summary,
          energyLevel: c.aiMetadata!.energyLevel,
          tags: c.aiMetadata!.tags.take(3).toList(),
          userMood: c.userMood,
        ),
      )
      .toList();

  return _PatternSummary(
    totalCaptures: captures.length,
    analyzedCaptures: withMeta.length,
    topThemes: top(themeCount),
    topTags: top(tagCount),
    topSignals: top(signalCount, n: 8),
    energyBreakdown: energyCount,
    recentMoments: recentMoments,
  );
}

// ── Screen ──────────────────────────────────────────────────────────────────

/// Patterns tab — surfaces AI-derived trends from accumulated captures.
///
/// Each capture is analysed in the background by [CaptureMetadataService].
/// This screen aggregates the resulting metadata into themes, energy trends,
/// and notable signals growing over time.
class PatternsScreen extends ConsumerStatefulWidget {
  const PatternsScreen({super.key});

  @override
  ConsumerState<PatternsScreen> createState() => _PatternsScreenState();
}

class _PatternsScreenState extends ConsumerState<PatternsScreen> {
  // ── Analysis progress ───────────────────────────────────────────────────
  int _analyzingDone = 0;
  int _analyzingTotal = 0; // 0 = idle (not started), >0 = in progress or done
  bool _justFinished = false;

  bool get _isAnalyzing =>
      _analyzingTotal > 0 && _analyzingDone < _analyzingTotal;

  @override
  void initState() {
    super.initState();
    // Catch up on any captures that failed to process or pre-date this feature.
    Future.microtask(() {
      if (!mounted) return;
      final metaSvc = ref.read(captureMetadataServiceProvider);
      metaSvc.processAllPendingMetadata(
        onProgress: (done, total) {
          if (!mounted || total == 0) return;
          setState(() {
            _analyzingDone = done;
            _analyzingTotal = total;
          });
          // When the last item finishes, refresh the captures list
          // and show a brief “all done” confirmation.
          if (done >= total) {
            ref.invalidate(_allCapturesProvider);
            setState(() => _justFinished = true);
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _justFinished = false);
            });
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final capturesAsync = ref.watch(_allCapturesProvider);

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0D0D0F) : const Color(0xFFF6F6F8),
      body: SafeArea(
        child: capturesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load captures: $e',
              style: GoogleFonts.inter(fontSize: 14),
            ),
          ),
          data: (captures) {
            if (captures.isEmpty) {
              return _EmptyState(theme: theme);
            }
            final summary = _buildSummary(captures);
            return _PatternBody(
              summary: summary,
              theme: theme,
              dark: dark,
              isAnalyzing: _isAnalyzing,
              analyzingDone: _analyzingDone,
              analyzingTotal: _analyzingTotal,
              justFinished: _justFinished,
            );
          },
        ),
      ),
    );
  }
}

// ── Body ────────────────────────────────────────────────────────────────────

class _PatternBody extends StatelessWidget {
  final _PatternSummary summary;
  final ThemeData theme;
  final bool dark;
  final bool isAnalyzing;
  final int analyzingDone;
  final int analyzingTotal;
  final bool justFinished;

  const _PatternBody({
    required this.summary,
    required this.theme,
    required this.dark,
    required this.isAnalyzing,
    required this.analyzingDone,
    required this.analyzingTotal,
    required this.justFinished,
  });

  @override
  Widget build(BuildContext context) {
    final showBanner = isAnalyzing || justFinished;

    return Column(
      children: [
        AppHeader(
          title: 'Patterns',
          subtitle:
              '${summary.analyzedCaptures} of ${summary.totalCaptures} captures analysed',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final container = ProviderScope.containerOf(context);
              container.invalidate(_allCapturesProvider);
            },
            color: theme.colorScheme.primary,
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                if (showBanner)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _AnalysisBanner(
                        done: analyzingDone,
                        total: analyzingTotal,
                        justFinished: justFinished,
                        theme: theme,
                      ),
                    ),
                  ),

                if (summary.analyzedCaptures > 0) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _sectionLabel('Energy Distribution', theme),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _EnergyBar(
                        breakdown: summary.energyBreakdown,
                        total: summary.analyzedCaptures,
                        theme: theme,
                        dark: dark,
                      ),
                    ),
                  ),
                ],

                if (summary.topThemes.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: _sectionLabel('Top Themes', theme),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _FrequencyChips(
                        entries: summary.topThemes,
                        color: theme.colorScheme.primary,
                        theme: theme,
                        dark: dark,
                      ),
                    ),
                  ),
                ],

                if (summary.topTags.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: _sectionLabel('Keywords', theme),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _FrequencyChips(
                        entries: summary.topTags,
                        color: Colors.teal,
                        theme: theme,
                        dark: dark,
                      ),
                    ),
                  ),
                ],

                if (summary.topSignals.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: _sectionLabel('Recurring Signals', theme),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _SignalList(
                        signals: summary.topSignals,
                        theme: theme,
                        dark: dark,
                      ),
                    ),
                  ),
                ],

                if (summary.recentMoments.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: _sectionLabel('Recent Moments', theme),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                        child: _MomentCard(
                          moment: summary.recentMoments[i],
                          theme: theme,
                          dark: dark,
                        ),
                      ),
                      childCount: summary.recentMoments.length,
                    ),
                  ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _AnalysisBanner extends StatelessWidget {
  final int done;
  final int total;
  final bool justFinished;
  final ThemeData theme;

  const _AnalysisBanner({
    required this.done,
    required this.total,
    required this.justFinished,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? done / total : 0.0;
    final remaining = total - done;

    if (justFinished) {
      // Done state — brief success confirmation
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 16,
              color: Color(0xFF4CAF50),
            ),
            const SizedBox(width: 10),
            Text(
              'Analysis complete — patterns updated',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4CAF50),
              ),
            ),
          ],
        ),
      );
    }

    // In-progress state
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  done == 0
                      ? 'Preparing to analyse $total capture${total == 1 ? '' : 's'}…'
                      : 'Analysing captures — $remaining left',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$done / $total',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Results appear below as each capture is processed.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sectionLabel(String label, ThemeData theme) => Text(
  label.toUpperCase(),
  style: GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
  ),
);

class _EnergyBar extends StatelessWidget {
  final Map<String, int> breakdown;
  final int total;
  final ThemeData theme;
  final bool dark;

  const _EnergyBar({
    required this.breakdown,
    required this.total,
    required this.theme,
    required this.dark,
  });

  Color _color(String level) => switch (level) {
    'high' => const Color(0xFF4CAF50),
    'medium' => const Color(0xFFFF9800),
    'low' => const Color(0xFF2196F3),
    _ => Colors.grey,
  };

  IconData _icon(String level) => switch (level) {
    'high' => Icons.bolt_rounded,
    'medium' => Icons.water_drop_outlined,
    'low' => Icons.nights_stay_rounded,
    _ => Icons.circle,
  };

  @override
  Widget build(BuildContext context) {
    final surfaceColor = dark
        ? const Color(0xFF1A1A1E)
        : theme.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final level in ['high', 'medium', 'low'])
                      if ((breakdown[level] ?? 0) > 0)
                        Flexible(
                          flex: breakdown[level]!,
                          child: Container(color: _color(level)),
                        ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final level in ['high', 'medium', 'low'])
                _EnergyLegendItem(
                  label: level[0].toUpperCase() + level.substring(1),
                  count: breakdown[level] ?? 0,
                  color: _color(level),
                  icon: _icon(level),
                  theme: theme,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnergyLegendItem extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final ThemeData theme;

  const _EnergyLegendItem({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _FrequencyChips extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final Color color;
  final ThemeData theme;
  final bool dark;

  const _FrequencyChips({
    required this.entries,
    required this.color,
    required this.theme,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = entries.isEmpty ? 1 : entries.first.value;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((e) {
        final intensity = (e.value / maxCount).clamp(0.15, 1.0);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: intensity * 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: intensity * 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.key,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: dark ? 0.9 : 0.85),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: intensity * 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  e.value.toString(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SignalList extends StatelessWidget {
  final List<MapEntry<String, int>> signals;
  final ThemeData theme;
  final bool dark;

  const _SignalList({
    required this.signals,
    required this.theme,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = dark
        ? const Color(0xFF1A1A1E)
        : theme.colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: signals.asMap().entries.map((entry) {
          final i = entry.key;
          final signal = entry.value;
          final isLast = i == signals.length - 1;
          return Container(
            decoration: isLast
                ? null
                : BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.06,
                        ),
                      ),
                    ),
                  ),
            child: ListTile(
              dense: true,
              leading: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: Colors.orange.shade400,
                ),
              ),
              title: Text(
                signal.key,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              trailing: Text(
                '×${signal.value}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.orange.shade400,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  final _MomentSnapshot moment;
  final ThemeData theme;
  final bool dark;

  const _MomentCard({
    required this.moment,
    required this.theme,
    required this.dark,
  });

  Color _energyColor(String level) => switch (level.toLowerCase()) {
    'high' => const Color(0xFF4CAF50),
    'medium' => const Color(0xFFFF9800),
    'low' => const Color(0xFF2196F3),
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final ec = _energyColor(moment.energyLevel);
    final surfaceColor = dark
        ? const Color(0xFF1A1A1E)
        : theme.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4, right: 10),
            decoration: BoxDecoration(
              color: ec,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ec.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormat('MMM d, h:mm a').format(moment.timestamp),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                    if (moment.userMood != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        moment.userMood!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: ec.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        moment.energyLevel,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: ec,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  moment.summary,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                if (moment.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    children: moment.tags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.06,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '#$t',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 20),
            Text(
              'No captures yet',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Take your first capture and patterns will start building here automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
