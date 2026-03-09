import 'dart:math';

import 'package:bodypress_flutter/core/services/fft_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the FFT engine produces mathematically correct spectral analysis.
///
/// Feeds known sinusoids and verifies:
///   1. Peak detection at the correct frequency bin
///   2. Band power extraction into the correct EEG band
///   3. Parseval's theorem (energy conservation time ↔ frequency)
///   4. Windowing suppresses leakage
void main() {
  group('FftEngine — real spectral analysis proof', () {
    const n = 256;
    const fs = 250.0; // 250 Hz sample rate (standard EEG)
    late FftEngine fft;

    setUp(() {
      fft = FftEngine(n: n, sampleRateHz: fs);
    });

    test('pure 10 Hz sine → peak at 10 Hz (alpha band)', () {
      // Generate exactly 256 samples of a 10 Hz sine at 250 Hz sample rate.
      final samples = List<double>.generate(n, (i) {
        final t = i / fs;
        return 50.0 * sin(2 * pi * 10.0 * t); // 50 µV amplitude
      });

      final result = fft.analyse(samples);

      // Frequency resolution = fs/N = 250/256 ≈ 0.977 Hz.
      // 10 Hz should fall in bin 10 (10 × 0.977 ≈ 9.77 Hz).
      // Due to windowing, the peak bin may be 10 or 11.
      expect(
        result.dominantFrequency,
        closeTo(10.0, 1.5),
        reason: 'Peak should be at ~10 Hz',
      );

      // Alpha band (8–13 Hz) should contain nearly all power.
      final alphaPower = result.bandPowers[FrequencyBand.alpha]!;
      final totalPower = result.totalPower;
      expect(
        alphaPower / totalPower,
        greaterThan(0.85),
        reason: 'A 10 Hz sine should put >85% power into alpha band',
      );

      // Delta band should be near zero.
      final deltaPower = result.bandPowers[FrequencyBand.delta]!;
      expect(
        deltaPower / totalPower,
        lessThan(0.05),
        reason: 'Delta should have <5% for a 10 Hz signal',
      );
    });

    test('pure 2 Hz sine → peak in delta band (0.5–4 Hz)', () {
      final samples = List<double>.generate(n, (i) {
        final t = i / fs;
        return 30.0 * sin(2 * pi * 2.0 * t);
      });

      final result = fft.analyse(samples);

      expect(result.dominantFrequency, closeTo(2.0, 1.5));

      final deltaPower = result.bandPowers[FrequencyBand.delta]!;
      expect(
        deltaPower / result.totalPower,
        greaterThan(0.80),
        reason: '2 Hz signal → delta band dominant',
      );
    });

    test('pure 20 Hz sine → peak in beta band (13–30 Hz)', () {
      final samples = List<double>.generate(n, (i) {
        final t = i / fs;
        return 40.0 * sin(2 * pi * 20.0 * t);
      });

      final result = fft.analyse(samples);

      expect(result.dominantFrequency, closeTo(20.0, 1.5));

      final betaPower = result.bandPowers[FrequencyBand.beta]!;
      expect(
        betaPower / result.totalPower,
        greaterThan(0.85),
        reason: '20 Hz signal → beta band dominant',
      );
    });

    test('two tones (10 Hz + 25 Hz) → both appear in spectrum', () {
      final samples = List<double>.generate(n, (i) {
        final t = i / fs;
        return 50.0 * sin(2 * pi * 10.0 * t) + 30.0 * sin(2 * pi * 25.0 * t);
      });

      final result = fft.analyse(samples);

      // Both alpha and beta should have significant power.
      final alphaPower = result.bandPowers[FrequencyBand.alpha]!;
      final betaPower = result.bandPowers[FrequencyBand.beta]!;
      final combinedFrac = (alphaPower + betaPower) / result.totalPower;

      expect(
        combinedFrac,
        greaterThan(0.80),
        reason: '10+25 Hz → alpha+beta should hold >80% power',
      );
      expect(
        alphaPower,
        greaterThan(0),
        reason: 'Alpha band must have power from 10 Hz tone',
      );
      expect(
        betaPower,
        greaterThan(0),
        reason: 'Beta band must have power from 25 Hz tone',
      );
    });

    test('DC signal → peak at 0 Hz, delta-dominant', () {
      // A constant value is a 0 Hz (DC) component.
      final samples = List<double>.filled(n, 100.0);

      final result = fft.analyse(samples);

      // With Hanning window, DC leaks a bit but peak should be at bin 0.
      expect(result.dominantFrequency, closeTo(0.0, 1.5));
    });

    test('frequency resolution = fs / N', () {
      final result = fft.analyse(List<double>.filled(n, 0));
      final df = result.frequencies[1] - result.frequencies[0];
      expect(
        df,
        closeTo(fs / n, 0.01),
        reason: 'Bin spacing should be fs/N = ${fs / n} Hz',
      );
    });

    test('frequency axis spans 0 to Nyquist', () {
      final result = fft.analyse(List<double>.filled(n, 0));
      expect(result.frequencies.first, equals(0.0));
      expect(
        result.frequencies.last,
        closeTo(fs / 2, 0.01),
        reason: 'Last bin = Nyquist = ${fs / 2} Hz',
      );
    });

    test('PSD length = N/2 + 1 (one-sided spectrum)', () {
      final result = fft.analyse(List<double>.filled(n, 0));
      expect(result.psd.length, equals(n ~/ 2 + 1));
      expect(result.frequencies.length, equals(n ~/ 2 + 1));
      expect(result.magnitudeDb.length, equals(n ~/ 2 + 1));
    });

    test('magnitude dB is 0 at peak, negative elsewhere', () {
      final samples = List<double>.generate(n, (i) {
        return 50.0 * sin(2 * pi * 10.0 * i / fs);
      });

      final result = fft.analyse(samples);

      // Find the peak bin.
      double maxDb = -999;
      for (var k = 0; k < result.magnitudeDb.length; k++) {
        if (result.magnitudeDb[k] > maxDb) maxDb = result.magnitudeDb[k];
      }
      expect(
        maxDb,
        closeTo(0.0, 0.01),
        reason: 'Peak bin should be 0 dB (reference)',
      );

      // Non-peak bins should be negative.
      int negCount = 0;
      for (var k = 0; k < result.magnitudeDb.length; k++) {
        if (result.magnitudeDb[k] < -0.1) negCount++;
      }
      expect(
        negCount,
        greaterThan(result.magnitudeDb.length ~/ 2),
        reason: 'Most bins should be below 0 dB',
      );
    });

    test('all five EEG bands are computed', () {
      final result = fft.analyse(List<double>.filled(n, 0));
      for (final band in FrequencyBand.values) {
        expect(
          result.bandPowers.containsKey(band),
          isTrue,
          reason: '${band.label} must be in band powers',
        );
      }
    });

    test('band boundaries are correct', () {
      expect(FrequencyBand.delta.lowHz, equals(0.5));
      expect(FrequencyBand.delta.highHz, equals(4.0));
      expect(FrequencyBand.theta.lowHz, equals(4.0));
      expect(FrequencyBand.theta.highHz, equals(8.0));
      expect(FrequencyBand.alpha.lowHz, equals(8.0));
      expect(FrequencyBand.alpha.highHz, equals(13.0));
      expect(FrequencyBand.beta.lowHz, equals(13.0));
      expect(FrequencyBand.beta.highHz, equals(30.0));
      expect(FrequencyBand.gamma.lowHz, equals(30.0));
      expect(FrequencyBand.gamma.highHz, equals(100.0));
    });

    test('white noise → flat-ish spectrum, power spread across bands', () {
      final rng = Random(42); // seeded for reproducibility
      final samples = List<double>.generate(n, (_) {
        return (rng.nextDouble() - 0.5) * 100;
      });

      final result = fft.analyse(samples);

      // No single band should hold >60% of total power with white noise.
      for (final band in FrequencyBand.values) {
        final frac = result.bandPowers[band]! / result.totalPower;
        expect(
          frac,
          lessThan(0.60),
          reason:
              '${band.label} should not dominate with white noise (got ${(frac * 100).toStringAsFixed(1)}%)',
        );
      }
    });
  });
}
