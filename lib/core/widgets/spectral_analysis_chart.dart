import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/ble_source_provider.dart';
import '../services/fft_engine.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bioluminescent Spectrum — real-time spectral analysis visualisation.
//
// Three layers, one canvas:
//   1. Live frequency spectrum bars with glow + gradient fill
//   2. Scrolling waterfall spectrogram (time × frequency × power heatmap)
//   3. EEG band power meters (Delta → Gamma) with animated fill
//
// Designed to match the Midnight Ocean palette and the oscilloscope aesthetic
// of [LiveSignalChart]. Toggle between SPECTRUM, WATERFALL, and BANDS views.
// ─────────────────────────────────────────────────────────────────────────────

/// Spectral visualisation modes.
enum SpectralView {
  spectrum,
  waterfall,
  bands;

  String get label => switch (this) {
    SpectralView.spectrum => 'SPECTRUM',
    SpectralView.waterfall => 'WATERFALL',
    SpectralView.bands => 'BANDS',
  };

  IconData get icon => switch (this) {
    SpectralView.spectrum => Icons.equalizer_rounded,
    SpectralView.waterfall => Icons.waves_rounded,
    SpectralView.bands => Icons.bar_chart_rounded,
  };
}

/// Real-time multi-channel spectral analysis chart.
///
/// Subscribes to the same `Stream<SignalSample>` as [LiveSignalChart],
/// maintains its own internal FFT buffer, and renders one of three views.
class SpectralAnalysisChart extends StatefulWidget {
  /// The live signal stream to analyse.
  final Stream<SignalSample> signalStream;

  /// Channel layout — needed to know how many channels & labels.
  final List<ChannelDescriptor> channelDescriptors;

  /// Nominal sample rate (Hz), used for FFT frequency axis.
  final double sampleRateHz;

  /// Optional device / source names for header display.
  final String? deviceName;
  final String? sourceName;

  /// Called when user wants to switch back to time-domain view.
  final VoidCallback? onSwitchToTimeDomain;

  /// FFT window size — must be power of 2. Default 256 ≈ 1 s at 250 Hz.
  final int fftSize;

  /// Number of waterfall history rows to keep.
  final int waterfallRows;

  const SpectralAnalysisChart({
    super.key,
    required this.signalStream,
    required this.channelDescriptors,
    this.sampleRateHz = 250,
    this.deviceName,
    this.sourceName,
    this.onSwitchToTimeDomain,
    this.fftSize = 256,
    this.waterfallRows = 120,
  });

  @override
  State<SpectralAnalysisChart> createState() => _SpectralAnalysisChartState();
}

class _SpectralAnalysisChartState extends State<SpectralAnalysisChart>
    with SingleTickerProviderStateMixin {
  // ── FFT engine ──────────────────────────────────────────────────────
  late final FftEngine _fft;
  late final List<ListQueue<double>> _sampleBuffers;

  // ── Latest spectrum per channel ─────────────────────────────────────
  late List<SpectrumResult?> _spectra;

  // ── Smoothed spectrum bars (for animation) ──────────────────────────
  late List<Float64List?> _smoothedPsd;

  // ── Waterfall history (per channel, most recent row = index 0) ──────
  late List<ListQueue<Float64List>> _waterfallHistory;

  // ── State ───────────────────────────────────────────────────────────
  int _activeChannel = 0;
  SpectralView _view = SpectralView.spectrum;
  int _sampleCount = 0;
  bool _connected = false;

  late final Ticker _ticker;
  StreamSubscription<SignalSample>? _sub;

  // ── Colour palette for the waterfall / spectrum ─────────────────────
  static const _spectralGradientColors = [
    Color(0xFF060A14), // abyss
    Color(0xFF0B253A), // deep sea glow
    Color(0xFF125C6D), // teal dark
    Color(0xFF4DD4C8), // bioluminescent teal
    Color(0xFF8B78F5), // aurora violet
    Color(0xFFD4A0FF), // light violet
    Color(0xFFFFFFFF), // white hot
  ];

  static const _spectralGradientStops = [
    0.0,
    0.15,
    0.30,
    0.50,
    0.70,
    0.85,
    1.0,
  ];

  @override
  void initState() {
    super.initState();
    final n = widget.channelDescriptors.length;

    _fft = FftEngine(n: widget.fftSize, sampleRateHz: widget.sampleRateHz);
    _sampleBuffers = List.generate(
      n,
      (_) => ListQueue<double>.from(List<double>.filled(widget.fftSize, 0.0)),
    );
    _spectra = List<SpectrumResult?>.filled(n, null);
    _smoothedPsd = List<Float64List?>.filled(n, null);
    _waterfallHistory = List.generate(n, (_) => ListQueue<Float64List>());

    _sub = widget.signalStream.listen(_onSample);
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    super.dispose();
  }

  void _onSample(SignalSample sample) {
    _connected = true;
    _sampleCount++;

    for (
      var ch = 0;
      ch < sample.channels.length && ch < _sampleBuffers.length;
      ch++
    ) {
      _sampleBuffers[ch].removeFirst();
      _sampleBuffers[ch].addLast(sample.channels[ch]);
    }

    // Run FFT every ~fftSize/4 samples (75% overlap) for smooth updates.
    if (_sampleCount % (widget.fftSize ~/ 4) == 0) {
      _computeSpectra();
    }
  }

  void _computeSpectra() {
    for (var ch = 0; ch < _sampleBuffers.length; ch++) {
      final samples = _sampleBuffers[ch].toList();
      if (samples.length < widget.fftSize) continue;

      final result = _fft.analyse(samples);
      _spectra[ch] = result;

      // Smooth the PSD for animated bars (exponential moving average).
      if (_smoothedPsd[ch] == null) {
        _smoothedPsd[ch] = Float64List.fromList(result.psd);
      } else {
        final prev = _smoothedPsd[ch]!;
        final curr = result.psd;
        const alpha = 0.3; // smoothing factor
        for (var k = 0; k < prev.length && k < curr.length; k++) {
          prev[k] = prev[k] * (1 - alpha) + curr[k] * alpha;
        }
      }

      // Push to waterfall history.
      _waterfallHistory[ch].addFirst(Float64List.fromList(result.psd));
      while (_waterfallHistory[ch].length > widget.waterfallRows) {
        _waterfallHistory[ch].removeLast();
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF060B0F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.aurora.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildChannelSelector(),
          _buildViewTabs(),
          Expanded(child: _buildActiveView()),
          _buildInfoFooter(),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          // Animated pulsing spectral icon
          _PulsingIcon(
            icon: Icons.graphic_eq_rounded,
            color: AppTheme.aurora,
            connected: _connected,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPECTRAL ANALYSIS',
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.aurora.withValues(alpha: 0.9),
                    letterSpacing: 1.5,
                  ),
                ),
                if (widget.sourceName != null)
                  Text(
                    widget.sourceName!,
                    style: GoogleFonts.robotoMono(
                      fontSize: 9,
                      color: AppTheme.fog.withValues(alpha: 0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ),
          // Dominant frequency badge
          if (_spectra[_activeChannel] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.aurora.withValues(alpha: 0.15),
                    AppTheme.glow.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.aurora.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                '${_spectra[_activeChannel]!.dominantFrequency.toStringAsFixed(1)} Hz',
                style: GoogleFonts.robotoMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.aurora,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          const SizedBox(width: 8),
          if (widget.onSwitchToTimeDomain != null)
            GestureDetector(
              onTap: widget.onSwitchToTimeDomain,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.glow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.timeline_rounded,
                  color: AppTheme.glow.withValues(alpha: 0.5),
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Channel selector ──────────────────────────────────────────────────

  Widget _buildChannelSelector() {
    final descriptors = widget.channelDescriptors;
    if (descriptors.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 32,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: descriptors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final isActive = _activeChannel == i;
          final color = _channelColor(i);
          return GestureDetector(
            onTap: () => setState(() => _activeChannel = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? color.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? color.withValues(alpha: 0.6)
                      : AppTheme.fog.withValues(alpha: 0.15),
                  width: isActive ? 1.5 : 0.7,
                ),
              ),
              child: Center(
                child: Text(
                  descriptors[i].label,
                  style: GoogleFonts.robotoMono(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive
                        ? color
                        : AppTheme.fog.withValues(alpha: 0.4),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── View switching tabs ───────────────────────────────────────────────

  Widget _buildViewTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: SpectralView.values.map((v) {
          final isActive = _view == v;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _view = v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.aurora.withValues(alpha: 0.15),
                            AppTheme.glow.withValues(alpha: 0.08),
                          ],
                        )
                      : null,
                  color: isActive ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.aurora.withValues(alpha: 0.3)
                        : AppTheme.shimmer.withValues(alpha: 0.2),
                    width: isActive ? 1.2 : 0.6,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      v.icon,
                      size: 13,
                      color: isActive
                          ? AppTheme.aurora
                          : AppTheme.fog.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      v.label,
                      style: GoogleFonts.robotoMono(
                        fontSize: 9,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isActive
                            ? AppTheme.aurora
                            : AppTheme.fog.withValues(alpha: 0.4),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Active view ───────────────────────────────────────────────────────

  Widget _buildActiveView() {
    final spectrum = _spectra[_activeChannel];
    if (spectrum == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 40,
              color: AppTheme.aurora.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'Collecting samples…',
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                color: AppTheme.fog.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.fftSize - _sampleCount.clamp(0, widget.fftSize)} remaining',
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                color: AppTheme.fog.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
    }

    return switch (_view) {
      SpectralView.spectrum => _buildSpectrumView(spectrum),
      SpectralView.waterfall => _buildWaterfallView(),
      SpectralView.bands => _buildBandsView(spectrum),
    };
  }

  // ── SPECTRUM VIEW ─────────────────────────────────────────────────────

  Widget _buildSpectrumView(SpectrumResult spectrum) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _SpectrumPainter(
            psd: _smoothedPsd[_activeChannel] ?? spectrum.psd,
            frequencies: spectrum.frequencies,
            channelColor: _channelColor(_activeChannel),
            maxFrequency: math.min(widget.sampleRateHz / 2, 60),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // ── WATERFALL VIEW ────────────────────────────────────────────────────

  Widget _buildWaterfallView() {
    final history = _waterfallHistory[_activeChannel];
    final spectrum = _spectra[_activeChannel];
    if (history.isEmpty || spectrum == null) {
      return Center(
        child: Text(
          'Building waterfall…',
          style: GoogleFonts.robotoMono(
            fontSize: 12,
            color: AppTheme.fog.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _WaterfallPainter(
            history: history.toList(),
            frequencies: spectrum.frequencies,
            maxFrequency: math.min(widget.sampleRateHz / 2, 60),
            gradientColors: _spectralGradientColors,
            gradientStops: _spectralGradientStops,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // ── BANDS VIEW ────────────────────────────────────────────────────────

  Widget _buildBandsView(SpectrumResult spectrum) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: FrequencyBand.values.map((band) {
          final power = spectrum.bandPowers[band] ?? 0;
          final total = spectrum.totalPower;
          final fraction = total > 0 ? (power / total).clamp(0.0, 1.0) : 0.0;
          return Expanded(
            child: _BandMeter(
              band: band,
              fraction: fraction,
              power: power,
              color: _bandColor(band),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────

  Widget _buildInfoFooter() {
    final spectrum = _spectra[_activeChannel];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'FFT ${widget.fftSize} · ${widget.sampleRateHz.toInt()} Hz · '
            '${(widget.sampleRateHz / widget.fftSize).toStringAsFixed(1)} Hz/bin',
            style: GoogleFonts.robotoMono(
              fontSize: 8,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          if (spectrum != null)
            Text(
              'Σ ${spectrum.totalPower.toStringAsFixed(1)} µV²',
              style: GoogleFonts.robotoMono(
                fontSize: 8,
                color: AppTheme.aurora.withValues(alpha: 0.3),
              ),
            ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Color _channelColor(int index) {
    const palette = [
      Color(0xFF00E676),
      Color(0xFF40C4FF),
      Color(0xFFFF5252),
      Color(0xFFFFD740),
      Color(0xFFE040FB),
      Color(0xFF00E5FF),
      Color(0xFFFF6E40),
      Color(0xFF69F0AE),
    ];
    return palette[index % palette.length];
  }

  Color _bandColor(FrequencyBand band) => switch (band) {
    FrequencyBand.delta => const Color(0xFF4DD4C8), // teal — deep, slow
    FrequencyBand.theta => const Color(0xFF40C4FF), // blue — meditative
    FrequencyBand.alpha => const Color(0xFF8B78F5), // aurora — the star
    FrequencyBand.beta => const Color(0xFFFFD740), // amber — active mind
    FrequencyBand.gamma => const Color(0xFFFF5252), // red-hot — high freq
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═════════════════════════════════════════════════════════════════════════════

// ── SPECTRUM BAR PAINTER ────────────────────────────────────────────────────

class _SpectrumPainter extends CustomPainter {
  final Float64List psd;
  final Float64List frequencies;
  final Color channelColor;
  final double maxFrequency;

  const _SpectrumPainter({
    required this.psd,
    required this.frequencies,
    required this.channelColor,
    required this.maxFrequency,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (psd.isEmpty) return;

    _drawBackground(canvas, size);
    _drawFrequencyGrid(canvas, size);
    _drawSpectrum(canvas, size);
    _drawFrequencyLabels(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Subtle radial gradient background for depth.
    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height),
        size.height * 1.2,
        [const Color(0xFF0A1020), const Color(0xFF060B0F)],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);
  }

  void _drawFrequencyGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;

    // Vertical lines at key frequencies.
    for (final hz in [5.0, 10.0, 15.0, 20.0, 30.0, 40.0, 50.0]) {
      if (hz > maxFrequency) break;
      final x = (hz / maxFrequency) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal amplitude reference lines.
    for (var i = 1; i <= 4; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint..color = Colors.white.withValues(alpha: 0.025),
      );
    }
  }

  void _drawSpectrum(Canvas canvas, Size size) {
    // Find max PSD for normalisation within view range.
    double maxPsd = 0;
    int maxBin = 0;
    for (var k = 0; k < psd.length && k < frequencies.length; k++) {
      if (frequencies[k] > maxFrequency) break;
      if (psd[k] > maxPsd) {
        maxPsd = psd[k];
        maxBin = k;
      }
    }
    if (maxPsd == 0) maxPsd = 1;

    // Build the spectrum path.
    final spectrumPath = Path();
    final fillPath = Path();
    bool first = true;

    for (var k = 1; k < psd.length && k < frequencies.length; k++) {
      if (frequencies[k] > maxFrequency) break;
      final x = (frequencies[k] / maxFrequency) * size.width;
      final norm = (psd[k] / maxPsd).clamp(0.0, 1.0);
      // Non-linear mapping for visual impact (sqrt gives more range to low values).
      final y = size.height * (1.0 - math.sqrt(norm));

      if (first) {
        spectrumPath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        first = false;
      } else {
        spectrumPath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill path.
    final lastX =
        (math.min(frequencies.last.toDouble(), maxFrequency) / maxFrequency) *
        size.width;
    fillPath.lineTo(lastX, size.height);
    fillPath.close();

    // ── Gradient fill beneath the curve ──────────────────────────────
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          channelColor.withValues(alpha: 0.25),
          channelColor.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        [0.0, 0.5, 1.0],
      );
    canvas.drawPath(fillPath, fillPaint);

    // ── Glow pass (diffuse bioluminescence) ─────────────────────────
    canvas.drawPath(
      spectrumPath,
      Paint()
        ..color = channelColor.withValues(alpha: 0.2)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // ── Mid glow pass ───────────────────────────────────────────────
    canvas.drawPath(
      spectrumPath,
      Paint()
        ..color = channelColor.withValues(alpha: 0.4)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // ── Crisp trace ─────────────────────────────────────────────────
    canvas.drawPath(
      spectrumPath,
      Paint()
        ..color = channelColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // ── Peak marker ─────────────────────────────────────────────────
    if (maxBin > 0 && maxBin < frequencies.length) {
      final peakX = (frequencies[maxBin] / maxFrequency) * size.width;
      final peakY = size.height * (1.0 - math.sqrt(1.0)); // top
      // Glow dot at peak.
      canvas.drawCircle(
        Offset(peakX, peakY + 2),
        5,
        Paint()
          ..color = channelColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        Offset(peakX, peakY + 2),
        2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawFrequencyLabels(Canvas canvas, Size size) {
    for (final hz in [5.0, 10.0, 20.0, 30.0, 50.0]) {
      if (hz > maxFrequency) break;
      final x = (hz / maxFrequency) * size.width;
      final tp = TextPainter(
        text: TextSpan(
          text: '${hz.toInt()}',
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 8,
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => true;
}

// ── WATERFALL SPECTROGRAM PAINTER ───────────────────────────────────────────

class _WaterfallPainter extends CustomPainter {
  final List<Float64List> history;
  final Float64List frequencies;
  final double maxFrequency;
  final List<Color> gradientColors;
  final List<double> gradientStops;

  const _WaterfallPainter({
    required this.history,
    required this.frequencies,
    required this.maxFrequency,
    required this.gradientColors,
    required this.gradientStops,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    // Find global max across all history for consistent colour mapping.
    double globalMax = 0;
    for (final row in history) {
      for (var k = 1; k < row.length && k < frequencies.length; k++) {
        if (frequencies[k] > maxFrequency) break;
        if (row[k] > globalMax) globalMax = row[k];
      }
    }
    if (globalMax == 0) globalMax = 1;

    final rowHeight = size.height / history.length.clamp(1, 999);

    // Find max frequency bin index.
    int maxBinIdx = frequencies.length;
    for (var k = 0; k < frequencies.length; k++) {
      if (frequencies[k] > maxFrequency) {
        maxBinIdx = k;
        break;
      }
    }

    final binWidth = size.width / (maxBinIdx - 1).clamp(1, 999);

    for (var row = 0; row < history.length; row++) {
      final psd = history[row];
      final y = row * rowHeight;

      for (var k = 1; k < maxBinIdx && k < psd.length; k++) {
        final norm = (psd[k] / globalMax).clamp(0.0, 1.0);
        // Non-linear mapping: pow(norm, 0.5) for better contrast.
        final mapped = math.pow(norm, 0.45).toDouble();
        final color = _sampleGradient(mapped);

        final x = (k - 1) * binWidth;
        canvas.drawRect(
          Rect.fromLTWH(x, y, binWidth + 0.5, rowHeight + 0.5),
          Paint()..color = color,
        );
      }
    }

    // Overlay frequency labels.
    for (final hz in [5.0, 10.0, 20.0, 30.0, 50.0]) {
      if (hz > maxFrequency) break;
      final x = (hz / maxFrequency) * size.width;
      // Subtle vertical line.
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..strokeWidth = 0.5,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${hz.toInt()} Hz',
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 8,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 4));
    }

    // Time axis label.
    final tp = TextPainter(
      text: TextSpan(
        text: '← now',
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: 7,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(4, size.height - tp.height - 4));
  }

  Color _sampleGradient(double t) {
    if (t <= 0) return gradientColors.first;
    if (t >= 1) return gradientColors.last;

    for (var i = 0; i < gradientStops.length - 1; i++) {
      if (t >= gradientStops[i] && t <= gradientStops[i + 1]) {
        final segT =
            (t - gradientStops[i]) / (gradientStops[i + 1] - gradientStops[i]);
        return Color.lerp(gradientColors[i], gradientColors[i + 1], segT)!;
      }
    }
    return gradientColors.last;
  }

  @override
  bool shouldRepaint(_WaterfallPainter old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// SUPPORTING WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

// ── Band power meter ────────────────────────────────────────────────────────

class _BandMeter extends StatelessWidget {
  final FrequencyBand band;
  final double fraction; // 0..1
  final double power;
  final Color color;

  const _BandMeter({
    required this.band,
    required this.fraction,
    required this.power,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Band label + range.
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  band.label,
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '${band.lowHz.toStringAsFixed(0)}–${band.highHz.toStringAsFixed(0)} Hz',
                  style: GoogleFonts.robotoMono(
                    fontSize: 8,
                    color: AppTheme.fog.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Animated bar.
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final barWidth = constraints.maxWidth;
                return Stack(
                  children: [
                    // Track.
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: color.withValues(alpha: 0.1),
                          width: 0.5,
                        ),
                      ),
                    ),
                    // Fill.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      width: barWidth * fraction.clamp(0.0, 1.0),
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.15),
                            color.withValues(alpha: 0.4),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                    // Glow edge.
                    Positioned(
                      left: barWidth * fraction.clamp(0.0, 1.0) - 2,
                      top: 0,
                      bottom: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: fraction > 0.01 ? 1.0 : 0.0,
                        child: Container(
                          width: 4,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),

          // Percentage + power value.
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(fraction * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  power.toStringAsFixed(1),
                  style: GoogleFonts.robotoMono(
                    fontSize: 8,
                    color: AppTheme.fog.withValues(alpha: 0.4),
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

// ── Pulsing icon ────────────────────────────────────────────────────────────

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool connected;

  const _PulsingIcon({
    required this.icon,
    required this.color,
    required this.connected,
  });

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final glow = widget.connected ? 0.3 + _ctrl.value * 0.5 : 0.15;
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.08),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glow * 0.4),
                blurRadius: 8 + _ctrl.value * 4,
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: widget.color.withValues(alpha: 0.5 + glow * 0.5),
          ),
        );
      },
    );
  }
}
