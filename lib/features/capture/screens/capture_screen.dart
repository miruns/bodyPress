import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/capture_entry.dart';
import '../../../core/services/service_providers.dart';
import '../../shared/widgets/app_header.dart';

/// Capture tab — camera-inspired data capture.
/// Shutter button always visible at the bottom.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with TickerProviderStateMixin {
  late final _captureService = ref.read(captureServiceProvider);
  late final _metadataService = ref.read(captureMetadataServiceProvider);
  final TextEditingController _noteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isProcessing = false;

  bool _includeHealth = true;
  bool _includeEnvironment = true;
  bool _includeLocation = true;
  bool _includeCalendar = true;

  bool _isCapturing = false;
  String? _userNote;
  String? _userMood;
  bool _noteExpanded = false;

  List<CaptureEntry>? _recentCaptures;
  int _unprocessedCount = 0;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _captureAnimController;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _captureScaleAnim;

  static const _moodOptions = ['😊', '😎', '😴', '😤', '😌', '🤔', '💪', '😔'];

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _captureAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _captureScaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _captureAnimController, curve: Curves.easeIn),
    );

    _fadeController.forward();
    _loadRecentCaptures();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    _captureAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCaptures() async {
    try {
      final captures = await _captureService.getCaptures(limit: 10);
      final unprocessed = await _captureService.getUnprocessedCount();
      if (mounted) {
        setState(() {
          _recentCaptures = captures;
          _unprocessedCount = unprocessed;
        });
      }
    } catch (e) {
      debugPrint('Error loading recent captures: $e');
    }
  }

  /// Process a single unprocessed capture via the AI metadata service.
  Future<void> _processCapture(String captureId, {VoidCallback? onDone}) async {
    if (_isProcessing) return;
    HapticFeedback.lightImpact();
    setState(() => _isProcessing = true);
    try {
      await _metadataService.processCapture(captureId);
      await _loadRecentCaptures();
      if (mounted) {
        // Check whether it actually got processed (service swallows errors).
        final updated = _recentCaptures
            ?.where((c) => c.id == captureId)
            .firstOrNull;
        final succeeded = updated?.aiMetadata != null;
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              succeeded
                  ? 'Capture processed successfully'
                  : 'Processing failed — check your AI service key',
            ),
            backgroundColor: succeeded
                ? Colors.green.shade600
                : Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        if (succeeded) onDone?.call();
      }
    } catch (e) {
      debugPrint('Error processing capture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processing error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Process all pending captures in sequence.
  Future<void> _processAllPending() async {
    if (_isProcessing) return;
    HapticFeedback.lightImpact();
    setState(() => _isProcessing = true);
    try {
      final processed = await _metadataService.processAllPendingMetadata();
      await _loadRecentCaptures();
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              processed > 0
                  ? '$processed capture${processed == 1 ? '' : 's'} processed'
                  : 'No captures could be processed — check AI service',
            ),
            backgroundColor: processed > 0
                ? Colors.green.shade600
                : Colors.amber.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing pending captures: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processing error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _createCapture() async {
    if (_isCapturing) return;
    HapticFeedback.lightImpact();

    await _captureAnimController.forward();
    await _captureAnimController.reverse();

    setState(() => _isCapturing = true);

    try {
      await _captureService.createCapture(
        includeHealth: _includeHealth,
        includeEnvironment: _includeEnvironment,
        includeLocation: _includeLocation,
        includeCalendar: _includeCalendar,
        userNote: _userNote,
        userMood: _userMood,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        _showCaptureSuccessFlash();
        _noteController.clear();
        _userNote = null;
        _userMood = null;
        setState(() => _noteExpanded = false);
        await _loadRecentCaptures();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _showCaptureSuccessFlash() {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) => const _CaptureSuccessFlash());
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 400), entry.remove);
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: dark
            ? const Color(0xFF0D0D0F)
            : const Color(0xFFF6F6F8),
        body: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              // ── Pinned header ─────────────────────────────────────────
              SafeArea(
                bottom: false,
                child: AppHeader(
                  title: 'Capture',
                  primaryAction: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_recentCaptures != null) ...[
                        _buildMiniBadge(
                          dark,
                          '${_recentCaptures!.length}',
                          Icons.layers_outlined,
                          theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        if (_unprocessedCount > 0)
                          _buildMiniBadge(
                            dark,
                            '$_unprocessedCount',
                            Icons.hourglass_empty_rounded,
                            Colors.amber.shade600,
                          ),
                      ],
                      IconButton(
                        onPressed: _loadRecentCaptures,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
              ),
              // ── Scrollable content ──────────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadRecentCaptures,
                  color: theme.colorScheme.primary,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // Viewfinder
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: _buildViewfinder(theme, dark),
                        ),
                      ),

                      // Sensor chip row
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 0, 0),
                          child: _buildSensorChips(theme, dark),
                        ),
                      ),

                      // Mood + note
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: _buildContextRow(theme, dark),
                        ),
                      ),

                      // Recent captures section
                      if (_recentCaptures != null &&
                          _recentCaptures!.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                            child: _buildRecentHeader(theme, dark),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildCaptureCard(
                              theme,
                              dark,
                              _recentCaptures![index],
                            ),
                            childCount: _recentCaptures!.length,
                          ),
                        ),
                      ],

                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                  ),
                ),
              ),

              // ── Fixed bottom shutter bar — always visible ───────────
              _buildCaptureBar(theme, dark),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildMiniBadge(bool dark, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // VIEWFINDER — camera-like primed data preview
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildViewfinder(ThemeData theme, bool dark) {
    final activeSources = [
      if (_includeHealth) (Icons.favorite_rounded, 'Health', Colors.redAccent),
      if (_includeEnvironment)
        (Icons.wb_sunny_rounded, 'Weather', Colors.orange),
      if (_includeLocation)
        (Icons.location_on_rounded, 'Location', Colors.blue),
      if (_includeCalendar) (Icons.event_rounded, 'Calendar', Colors.purple),
    ];

    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A1D) : const Color(0xFFEEEEF2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          // Corner brackets (camera viewfinder corners)
          Positioned(top: 10, left: 10, child: _cornerBracket(theme, 0)),
          Positioned(
            top: 10,
            right: 10,
            child: _cornerBracket(theme, math.pi / 2),
          ),
          Positioned(
            bottom: 10,
            right: 10,
            child: _cornerBracket(theme, math.pi),
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: _cornerBracket(theme, -math.pi / 2),
          ),

          // Center content
          Center(
            child: activeSources.isEmpty
                ? Text(
                    'No sources selected',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: dark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.3),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing ready indicator
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => Transform.scale(
                          scale: _isCapturing ? 1.0 : _pulseAnim.value,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isCapturing
                                  ? Colors.red
                                  : theme.colorScheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (_isCapturing
                                              ? Colors.red
                                              : theme.colorScheme.primary)
                                          .withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: activeSources.map((s) {
                          final (icon, label, color) = s;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, color: color, size: 22),
                                const SizedBox(height: 4),
                                Text(
                                  label,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                    color: dark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
          ),

          // REC indicator (only while capturing)
          Positioned(
            top: 14,
            right: 34,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isCapturing ? _recLabel() : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerBracket(ThemeData theme, double rotation) {
    return Transform.rotate(
      angle: rotation,
      child: CustomPaint(
        size: const Size(16, 16),
        painter: _CornerBracketPainter(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _recLabel() {
    return Container(
      key: const ValueKey('rec'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'REC',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // SENSOR CHIP ROW — horizontal scrollable toggles, like lens modes
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildSensorChips(ThemeData theme, bool dark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        children: [
          _sensorChip(
            theme,
            dark,
            Icons.favorite_rounded,
            'Health',
            _includeHealth,
            () => setState(() => _includeHealth = !_includeHealth),
            Colors.redAccent,
          ),
          const SizedBox(width: 8),
          _sensorChip(
            theme,
            dark,
            Icons.wb_sunny_rounded,
            'Weather',
            _includeEnvironment,
            () => setState(() => _includeEnvironment = !_includeEnvironment),
            Colors.orange,
          ),
          const SizedBox(width: 8),
          _sensorChip(
            theme,
            dark,
            Icons.location_on_rounded,
            'Location',
            _includeLocation,
            () => setState(() => _includeLocation = !_includeLocation),
            Colors.blue,
          ),
          const SizedBox(width: 8),
          _sensorChip(
            theme,
            dark,
            Icons.event_rounded,
            'Calendar',
            _includeCalendar,
            () => setState(() => _includeCalendar = !_includeCalendar),
            Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _sensorChip(
    ThemeData theme,
    bool dark,
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap,
    Color accentColor,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? accentColor.withValues(alpha: 0.15)
              : (dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: active
                ? accentColor.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? accentColor
                  : (dark ? Colors.white38 : Colors.black38),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? accentColor
                    : (dark ? Colors.white54 : Colors.black45),
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // CONTEXT ROW — mood quick-select + expandable note
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildContextRow(ThemeData theme, bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mood quick-select row
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _moodOptions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final emoji = _moodOptions[i];
              final selected = _userMood == emoji;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _userMood = selected ? null : emoji);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : (dark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04)),
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary.withValues(alpha: 0.6)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // Expandable note input
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _noteExpanded
                  ? theme.colorScheme.primary.withValues(alpha: 0.4)
                  : (dark ? Colors.white : Colors.black).withValues(
                      alpha: 0.08,
                    ),
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _noteController,
            maxLines: _noteExpanded ? 4 : 1,
            decoration: InputDecoration(
              hintText: _noteExpanded
                  ? 'How are you feeling? What\'s on your mind?'
                  : 'Add a note...',
              hintStyle: GoogleFonts.inter(
                fontSize: 14,
                color: dark ? Colors.white24 : Colors.black26,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              prefixIcon: Icon(
                Icons.edit_note_rounded,
                size: 20,
                color: dark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.black26,
              ),
              suffixIcon: _userNote != null && _userNote!.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.black26,
                      ),
                      onPressed: () {
                        _noteController.clear();
                        setState(() {
                          _userNote = null;
                          _noteExpanded = false;
                        });
                      },
                    )
                  : null,
            ),
            style: GoogleFonts.inter(
              fontSize: 14,
              color: dark
                  ? Colors.white.withValues(alpha: 0.87)
                  : Colors.black87,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
            onTap: () => setState(() => _noteExpanded = true),
            onChanged: (v) => setState(() => _userNote = v.isEmpty ? null : v),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // RECENT CAPTURES HEADER
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildRecentHeader(ThemeData theme, bool dark) {
    return Row(
      children: [
        Text(
          'RECENT',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
          ),
        ),
        if (_unprocessedCount > 0) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isProcessing ? null : _processAllPending,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isProcessing)
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.amber.shade600,
                    ),
                  )
                else
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 14,
                    color: Colors.amber.shade600,
                  ),
                const SizedBox(width: 4),
                Text(
                  _isProcessing ? 'PROCESSING…' : 'PROCESS ALL',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Colors.amber.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // CAPTURE CARD — compact list item
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildCaptureCard(ThemeData theme, bool dark, CaptureEntry capture) {
    final dateFormat = DateFormat('MMM d · h:mm a');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCaptureDetails(capture),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: 0.06,
                ),
              ),
            ),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: capture.isProcessed
                        ? Colors.green.shade400
                        : Colors.amber.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            dateFormat.format(capture.timestamp),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: dark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          const Spacer(),
                          if (capture.userMood != null)
                            Text(
                              capture.userMood!,
                              style: const TextStyle(fontSize: 18),
                            ),
                        ],
                      ),
                      if (capture.userNote != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          capture.userNote!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: dark ? Colors.white70 : Colors.black87,
                            height: 1.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (capture.healthData != null)
                            _microBadge(
                              Icons.favorite_rounded,
                              Colors.redAccent,
                            ),
                          if (capture.environmentData != null)
                            _microBadge(Icons.wb_sunny_rounded, Colors.orange),
                          if (capture.locationData != null)
                            _microBadge(Icons.location_on_rounded, Colors.blue),
                          if (capture.calendarEvents.isNotEmpty)
                            _microBadge(Icons.event_rounded, Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: dark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _microBadge(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // CAPTURE BAR — always-visible shutter at the bottom
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildCaptureBar(ThemeData theme, bool dark) {
    final bg = dark ? const Color(0xFF141416) : Colors.white;
    final border = (dark ? Colors.white : Colors.black).withValues(alpha: 0.07);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Left stat — total
              _shutterStat(
                dark,
                '${_recentCaptures?.length ?? 0}',
                'captured',
                theme.colorScheme.primary,
              ),

              const Spacer(),

              // Shutter button
              ScaleTransition(
                scale: _captureScaleAnim,
                child: GestureDetector(
                  onTap: _isCapturing ? null : _createCapture,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isCapturing
                          ? (dark ? Colors.white12 : Colors.black12)
                          : theme.colorScheme.primary,
                      boxShadow: _isCapturing
                          ? null
                          : [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                    ),
                    child: _isCapturing
                        ? Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  dark ? Colors.white60 : Colors.black38,
                                ),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                  ),
                ),
              ),

              const Spacer(),

              // Right stat — pending AI
              _shutterStat(
                dark,
                '$_unprocessedCount',
                'pending',
                _unprocessedCount > 0
                    ? Colors.amber.shade600
                    : (dark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shutterStat(bool dark, String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w300,
            color: color,
            letterSpacing: -0.5,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: dark
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // DETAIL MODAL
  // ─────────────────────────────────────────────────────────────────────

  void _showCaptureDetails(CaptureEntry capture) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          final dateFormat = DateFormat('EEEE, MMMM d · h:mm a');

          return Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (dark ? Colors.white : Colors.black).withValues(
                      alpha: 0.2,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Capture Details',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: dark ? Colors.white : Colors.black87,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: dark ? Colors.white38 : Colors.black26,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildDetailSection(
                        theme,
                        dark,
                        'Timestamp',
                        dateFormat.format(capture.timestamp),
                        Icons.access_time_rounded,
                      ),
                      _buildDetailSection(
                        theme,
                        dark,
                        'Status',
                        capture.isProcessed
                            ? 'Processed by AI'
                            : 'Awaiting processing',
                        capture.isProcessed
                            ? Icons.check_circle_rounded
                            : Icons.hourglass_empty_rounded,
                        valueColor: capture.isProcessed
                            ? Colors.green.shade400
                            : Colors.amber.shade600,
                      ),
                      if (!capture.isProcessed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing
                                  ? null
                                  : () => _processCapture(
                                      capture.id,
                                      onDone: () => Navigator.pop(context),
                                    ),
                              icon: _isProcessing
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.amber.shade600,
                                      ),
                                    )
                                  : Icon(
                                      Icons.psychology_rounded,
                                      size: 18,
                                      color: Colors.amber.shade600,
                                    ),
                              label: Text(
                                _isProcessing ? 'Processing…' : 'Process Now',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.amber.shade600.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (capture.userMood != null)
                        _buildDetailSection(
                          theme,
                          dark,
                          'Mood',
                          capture.userMood!,
                          Icons.emoji_emotions_rounded,
                        ),
                      if (capture.userNote != null)
                        _buildDetailSection(
                          theme,
                          dark,
                          'Note',
                          capture.userNote!,
                          Icons.note_rounded,
                        ),
                      if (capture.healthData != null) ...[
                        const SizedBox(height: 24),
                        _buildHealthData(theme, dark, capture.healthData!),
                      ],
                      if (capture.environmentData != null) ...[
                        const SizedBox(height: 24),
                        _buildEnvironmentData(
                          theme,
                          dark,
                          capture.environmentData!,
                        ),
                      ],
                      if (capture.locationData != null) ...[
                        const SizedBox(height: 24),
                        _buildLocationData(theme, dark, capture.locationData!),
                      ],
                      if (capture.calendarEvents.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildCalendarData(theme, dark, capture.calendarEvents),
                      ],
                      if (capture.aiInsights != null) ...[
                        const SizedBox(height: 24),
                        _buildDetailSection(
                          theme,
                          dark,
                          'AI Insights',
                          capture.aiInsights!,
                          Icons.psychology_rounded,
                        ),
                      ],
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

  Widget _buildDetailSection(
    ThemeData theme,
    bool dark,
    String title,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: dark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color:
                  valueColor ??
                  (dark
                      ? Colors.white.withValues(alpha: 0.87)
                      : Colors.black87),
              height: 1.6,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthData(ThemeData theme, bool dark, CaptureHealthData data) =>
      _buildDataGroup(theme, dark, 'HEALTH DATA', Icons.favorite, [
        if (data.steps != null) ('Steps', '${data.steps}'),
        if (data.calories != null)
          ('Calories', '${data.calories?.toStringAsFixed(0)} kcal'),
        if (data.distance != null)
          ('Distance', '${data.distance!.toStringAsFixed(0)} m'),
        if (data.heartRate != null) ('Heart Rate', '${data.heartRate} bpm'),
        if (data.sleepHours != null)
          ('Sleep', '${data.sleepHours?.toStringAsFixed(1)} hours'),
        if (data.workouts != null) ('Workouts', '${data.workouts}'),
      ]);

  Widget _buildEnvironmentData(
    ThemeData theme,
    bool dark,
    CaptureEnvironmentData data,
  ) => _buildDataGroup(theme, dark, 'ENVIRONMENT', Icons.wb_sunny, [
    if (data.temperature != null)
      ('Temperature', '${data.temperature?.toStringAsFixed(1)}°C'),
    if (data.aqi != null) ('Air Quality', '${data.aqi}'),
    if (data.uvIndex != null)
      ('UV Index', '${data.uvIndex?.toStringAsFixed(1)}'),
    if (data.weatherDescription != null) ('Weather', data.weatherDescription!),
    if (data.humidity != null) ('Humidity', '${data.humidity}%'),
    if (data.windSpeed != null)
      ('Wind Speed', '${data.windSpeed?.toStringAsFixed(1)} km/h'),
  ]);

  Widget _buildLocationData(
    ThemeData theme,
    bool dark,
    CaptureLocationData data,
  ) => _buildDataGroup(theme, dark, 'LOCATION', Icons.location_on, [
    (
      'Coordinates',
      '${data.latitude.toStringAsFixed(4)}, ${data.longitude.toStringAsFixed(4)}',
    ),
    if (data.altitude != null)
      ('Altitude', '${data.altitude?.toStringAsFixed(0)} m'),
    if (data.city != null) ('City', data.city!),
    if (data.region != null) ('Region', data.region!),
    if (data.country != null) ('Country', data.country!),
  ]);

  Widget _buildCalendarData(ThemeData theme, bool dark, List<String> events) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.event,
              size: 18,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Text(
              'CALENDAR EVENTS',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: dark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: events
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '•  ',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: dark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: dark
                                  ? Colors.white.withValues(alpha: 0.87)
                                  : Colors.black87,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDataGroup(
    ThemeData theme,
    bool dark,
    String title,
    IconData icon,
    List<(String, String)> metrics,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: dark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: metrics.map((m) {
              final (label, value) = m;
              return _buildMetric(dark, label, value);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMetric(bool dark, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: dark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: dark
                    ? Colors.white.withValues(alpha: 0.87)
                    : Colors.black87,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CORNER BRACKET PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _CornerBracketPainter extends CustomPainter {
  final Color color;
  const _CornerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;

    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(0, 0)
        ..lineTo(size.width, 0),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerBracketPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// CAPTURE SUCCESS FLASH OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _CaptureSuccessFlash extends StatefulWidget {
  const _CaptureSuccessFlash();

  @override
  State<_CaptureSuccessFlash> createState() => _CaptureSuccessFlashState();
}

class _CaptureSuccessFlashState extends State<_CaptureSuccessFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => IgnorePointer(
        child: Opacity(
          opacity: (1 - _ctrl.value).clamp(0.0, 0.25),
          child: Container(color: Colors.white),
        ),
      ),
    );
  }
}
