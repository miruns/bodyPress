import 'dart:math';
import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────────────────────
// FFT Engine — Pure Dart Cooley-Tukey radix-2 FFT with spectral analysis.
//
// Designed for real-time EEG / biosignal spectral analysis:
//   • 256-sample window (≈1 s at 250 Hz) → 1 Hz frequency resolution
//   • Hanning window to suppress spectral leakage
//   • Power Spectral Density (PSD) in µV²/Hz
//   • EEG frequency band extraction (Delta → Gamma)
// ─────────────────────────────────────────────────────────────────────────────

/// Standard EEG frequency bands.
enum FrequencyBand {
  delta('δ Delta', 0.5, 4.0),
  theta('θ Theta', 4.0, 8.0),
  alpha('α Alpha', 8.0, 13.0),
  beta('β Beta', 13.0, 30.0),
  gamma('γ Gamma', 30.0, 100.0);

  final String label;
  final double lowHz;
  final double highHz;

  const FrequencyBand(this.label, this.lowHz, this.highHz);
}

/// Result of a single-channel spectral analysis.
class SpectrumResult {
  /// Frequency axis values in Hz (length = N/2 + 1).
  final Float64List frequencies;

  /// Power Spectral Density in µV²/Hz (same length as [frequencies]).
  final Float64List psd;

  /// Magnitude spectrum (dB relative to peak, same length as [frequencies]).
  final Float64List magnitudeDb;

  /// Band power map — total power in each EEG band.
  final Map<FrequencyBand, double> bandPowers;

  /// Dominant frequency (Hz) — the bin with highest power.
  final double dominantFrequency;

  /// Total power across all bins.
  final double totalPower;

  const SpectrumResult({
    required this.frequencies,
    required this.psd,
    required this.magnitudeDb,
    required this.bandPowers,
    required this.dominantFrequency,
    required this.totalPower,
  });
}

/// Pure-Dart Cooley-Tukey FFT engine, optimised for real-time signal analysis.
class FftEngine {
  /// FFT size — must be a power of 2.
  final int n;

  /// Sample rate of the incoming signal (Hz).
  final double sampleRateHz;

  // Pre-computed resources.
  late final Float64List _window;
  late final Float64List _frequencies;
  late final List<int> _bitReversed;
  late final List<double> _twiddleReal;
  late final List<double> _twiddleImag;

  FftEngine({required this.n, required this.sampleRateHz})
    : assert(n > 0 && (n & (n - 1)) == 0, 'n must be a power of 2') {
    _precompute();
  }

  void _precompute() {
    // ── Hanning window ──────────────────────────────────────────────────
    _window = Float64List(n);
    for (var i = 0; i < n; i++) {
      _window[i] = 0.5 * (1.0 - cos(2.0 * pi * i / (n - 1)));
    }

    // ── Frequency axis ──────────────────────────────────────────────────
    final bins = n ~/ 2 + 1;
    _frequencies = Float64List(bins);
    final df = sampleRateHz / n;
    for (var i = 0; i < bins; i++) {
      _frequencies[i] = i * df;
    }

    // ── Bit-reversal permutation ────────────────────────────────────────
    _bitReversed = List<int>.filled(n, 0);
    final logN = _log2(n);
    for (var i = 0; i < n; i++) {
      _bitReversed[i] = _reverseBits(i, logN);
    }

    // ── Twiddle factors exp(-j·2π·k/N) ─────────────────────────────────
    _twiddleReal = List<double>.filled(n ~/ 2, 0);
    _twiddleImag = List<double>.filled(n ~/ 2, 0);
    for (var k = 0; k < n ~/ 2; k++) {
      final angle = -2.0 * pi * k / n;
      _twiddleReal[k] = cos(angle);
      _twiddleImag[k] = sin(angle);
    }
  }

  /// Perform spectral analysis on a single channel of [samples].
  ///
  /// Input length must be ≥ [n]. Only the last [n] samples are used.
  SpectrumResult analyse(List<double> samples) {
    assert(samples.length >= n, 'Need at least $n samples');

    // Take last N samples and apply window.
    final offset = samples.length - n;
    final re = Float64List(n);
    final im = Float64List(n);
    for (var i = 0; i < n; i++) {
      re[i] = samples[offset + i] * _window[i];
      im[i] = 0.0;
    }

    // In-place FFT.
    _fft(re, im);

    // Compute one-sided PSD and magnitude.
    final bins = n ~/ 2 + 1;
    final psd = Float64List(bins);
    final magDb = Float64List(bins);
    final df = sampleRateHz / n;
    // Normalisation: PSD = 2·|X[k]|² / (fs·S₂) where S₂ = Σ w[i]²
    double s2 = 0;
    for (var i = 0; i < n; i++) {
      s2 += _window[i] * _window[i];
    }
    final norm = 2.0 / (sampleRateHz * s2);

    double peakPower = 0;
    double totalPower = 0;
    int peakBin = 0;

    for (var k = 0; k < bins; k++) {
      final power = re[k] * re[k] + im[k] * im[k];
      // DC and Nyquist are not doubled.
      final scale = (k == 0 || k == bins - 1) ? 0.5 : 1.0;
      psd[k] = power * norm * scale;
      totalPower += psd[k] * df;
      if (psd[k] > peakPower) {
        peakPower = psd[k];
        peakBin = k;
      }
    }

    // Magnitude in dB (relative to peak).
    final peakRef = peakPower > 0 ? peakPower : 1e-30;
    for (var k = 0; k < bins; k++) {
      magDb[k] = 10.0 * log(psd[k] / peakRef) / ln10;
      if (magDb[k] < -80) magDb[k] = -80;
    }

    // Band powers.
    final bandPowers = <FrequencyBand, double>{};
    for (final band in FrequencyBand.values) {
      double bp = 0;
      for (var k = 0; k < bins; k++) {
        if (_frequencies[k] >= band.lowHz && _frequencies[k] < band.highHz) {
          bp += psd[k] * df;
        }
      }
      bandPowers[band] = bp;
    }

    return SpectrumResult(
      frequencies: _frequencies,
      psd: psd,
      magnitudeDb: magDb,
      bandPowers: bandPowers,
      dominantFrequency: _frequencies[peakBin],
      totalPower: totalPower,
    );
  }

  // ── Cooley-Tukey in-place radix-2 FFT ─────────────────────────────────

  void _fft(Float64List re, Float64List im) {
    // Bit-reversal reorder.
    for (var i = 0; i < n; i++) {
      final j = _bitReversed[i];
      if (j > i) {
        final tmpR = re[i];
        re[i] = re[j];
        re[j] = tmpR;
        final tmpI = im[i];
        im[i] = im[j];
        im[j] = tmpI;
      }
    }

    // Butterfly stages.
    for (var size = 2; size <= n; size *= 2) {
      final halfSize = size ~/ 2;
      final step = n ~/ size;
      for (var i = 0; i < n; i += size) {
        for (var j = 0; j < halfSize; j++) {
          final twIdx = j * step;
          final wr = _twiddleReal[twIdx];
          final wi = _twiddleImag[twIdx];

          final evenIdx = i + j;
          final oddIdx = i + j + halfSize;

          final tr = wr * re[oddIdx] - wi * im[oddIdx];
          final ti = wr * im[oddIdx] + wi * re[oddIdx];

          re[oddIdx] = re[evenIdx] - tr;
          im[oddIdx] = im[evenIdx] - ti;
          re[evenIdx] = re[evenIdx] + tr;
          im[evenIdx] = im[evenIdx] + ti;
        }
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static int _log2(int v) {
    int r = 0;
    var val = v;
    while (val > 1) {
      val >>= 1;
      r++;
    }
    return r;
  }

  static int _reverseBits(int x, int bits) {
    int result = 0;
    var val = x;
    for (var i = 0; i < bits; i++) {
      result = (result << 1) | (val & 1);
      val >>= 1;
    }
    return result;
  }
}
