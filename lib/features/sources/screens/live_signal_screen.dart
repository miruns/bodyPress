import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/live_signal_chart.dart';
import '../../../core/widgets/spectral_analysis_chart.dart';

/// Full-screen live signal monitor for a specific BLE source.
///
/// Flow: **Scan → Pick device → Connect → Stream + live chart**.
///
/// Reached via `/sources/:sourceId` — the source id is looked up in the
/// [BleSourceRegistry].
class LiveSignalScreen extends ConsumerStatefulWidget {
  final String sourceId;

  const LiveSignalScreen({super.key, required this.sourceId});

  @override
  ConsumerState<LiveSignalScreen> createState() => _LiveSignalScreenState();
}

class _LiveSignalScreenState extends ConsumerState<LiveSignalScreen> {
  late final BleSourceService _service;
  BleSourceProvider? _provider;

  // Discovered devices during scan.
  List<BleSourceDevice> _devices = [];
  StreamSubscription<List<BleSourceDevice>>? _devicesSub;
  StreamSubscription<BleSourceState>? _stateSub;

  BleSourceState _state = BleSourceState.idle;
  String? _errorMessage;

  // Recording
  final List<SignalSample> _recordedSamples = [];
  StreamSubscription<SignalSample>? _recordSub;
  bool _isRecording = false;

  // Spectral analysis toggle.
  bool _showSpectral = false;

  // Demo mode — synthetic signal without real hardware.
  bool _isDemoMode = false;
  Timer? _demoTimer;
  final _demoSignalController = StreamController<SignalSample>.broadcast();
  int _demoTick = 0;

  @override
  void initState() {
    super.initState();
    _service = ref.read(bleSourceServiceProvider);
    _provider = ref.read(bleSourceRegistryProvider).getById(widget.sourceId);

    _stateSub = _service.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _devicesSub = _service.devicesStream.listen((d) {
      if (mounted) setState(() => _devices = d);
    });

    // Auto-start scan if we have a provider.
    if (_provider != null) {
      Future.microtask(() => _startScan());
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _devicesSub?.cancel();
    _recordSub?.cancel();
    _stopDemo();
    _demoSignalController.close();
    // Don't dispose the service — it's owned by the provider.
    super.dispose();
  }

  Future<void> _startScan() async {
    _errorMessage = null;
    setState(() => _devices = []);
    try {
      await _service.startScan(_provider!);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _connectTo(BleSourceDevice dev) async {
    _errorMessage = null;
    try {
      await _service.connectAndStream(dev.device, _provider!);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _disconnect() async {
    _stopRecording();
    await _service.disconnect();
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _startRecording() {
    _recordedSamples.clear();
    _recordSub = _service.signalStream.listen((s) {
      _recordedSamples.add(s);
    });
    setState(() => _isRecording = true);
  }

  void _stopRecording() {
    _recordSub?.cancel();
    _recordSub = null;
    setState(() => _isRecording = false);
  }

  // ── Demo mode ───────────────────────────────────────────────────────

  void _startDemo() {
    _demoTick = 0;
    final rng = Random();
    final chCount = _provider!.channelCount;
    final hz = _provider!.sampleRateHz;

    // Emit synthetic samples at ~60 Hz (fast enough for smooth chart).
    _demoTimer = Timer.periodic(Duration(milliseconds: (1000 / 60).round()), (
      _,
    ) {
      _demoTick++;
      final t = _demoTick / hz;
      final channels = List<double>.generate(chCount, (ch) {
        // Blend of frequencies — each channel gets a slightly different mix.
        final base = 10.0 * sin(2 * pi * (3 + ch * 0.7) * t);
        final alpha = 8.0 * sin(2 * pi * (10 + ch) * t) * (ch.isEven ? 1 : 0.6);
        final noise = (rng.nextDouble() - 0.5) * 4;
        return double.parse((base + alpha + noise).toStringAsFixed(2));
      });
      if (!_demoSignalController.isClosed) {
        _demoSignalController.add(
          SignalSample(time: DateTime.now(), channels: channels),
        );
      }
    });
    setState(() {
      _isDemoMode = true;
      _state = BleSourceState.streaming;
    });
  }

  void _stopDemo() {
    _demoTimer?.cancel();
    _demoTimer = null;
    if (_isDemoMode && mounted) {
      setState(() {
        _isDemoMode = false;
        _state = BleSourceState.idle;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return Scaffold(
        backgroundColor: AppTheme.midnight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.moonbeam,
              size: 20,
            ),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Text(
            'Source "${widget.sourceId}" not found.',
            style: GoogleFonts.dmSans(fontSize: 16, color: AppTheme.fog),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.midnight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _provider!.displayName,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.moonbeam,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.moonbeam,
            size: 20,
          ),
          onPressed: () {
            if (_isDemoMode) _stopDemo();
            _disconnect();
            context.pop();
          },
        ),
        actions: [
          if (_isDemoMode)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.aurora.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'DEMO',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.aurora,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          if (_state == BleSourceState.streaming)
            IconButton(
              icon: Icon(
                _showSpectral
                    ? Icons.timeline_rounded
                    : Icons.graphic_eq_rounded,
                color: _showSpectral ? AppTheme.glow : AppTheme.aurora,
                size: 20,
              ),
              tooltip: _showSpectral ? 'Time domain' : 'Spectral analysis',
              onPressed: () => setState(() => _showSpectral = !_showSpectral),
            ),
          if (_state == BleSourceState.streaming && !_isDemoMode)
            IconButton(
              icon: Icon(
                _isRecording
                    ? Icons.stop_circle_rounded
                    : Icons.fiber_manual_record_rounded,
                color: _isRecording ? AppTheme.crimson : AppTheme.glow,
                size: 22,
              ),
              tooltip: _isRecording ? 'Stop recording' : 'Start recording',
              onPressed: _toggleRecording,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case BleSourceState.idle:
        return _buildScanResults();
      case BleSourceState.scanning:
        return _buildScanning();
      case BleSourceState.connecting:
        return _buildConnecting();
      case BleSourceState.streaming:
        return _buildStreaming();
      case BleSourceState.error:
        return _buildError();
    }
  }

  // ── Scan phase ────────────────────────────────────────────────────────

  Widget _buildScanning() {
    return Column(
      children: [
        const LinearProgressIndicator(
          color: AppTheme.glow,
          backgroundColor: AppTheme.deepSea,
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Scanning for ${_provider!.displayName} devices…',
            style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.fog),
          ),
        ),
        if (_devices.isNotEmpty) Expanded(child: _buildDeviceList()),
      ],
    );
  }

  Widget _buildScanResults() {
    return Column(
      children: [
        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            decoration: BoxDecoration(
              color: AppTheme.crimson.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _errorMessage!,
              style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.crimson),
            ),
          ),
        if (_devices.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bluetooth_searching_rounded,
                    size: 48,
                    color: AppTheme.fog.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No devices found',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      color: AppTheme.fog,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure your ${_provider!.displayName} board is powered on.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppTheme.fog.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildScanButton(),
                  const SizedBox(height: 12),
                  _buildDemoButton(),
                ],
              ),
            ),
          )
        else
          Expanded(child: _buildDeviceList()),
        if (_devices.isNotEmpty)
          Padding(padding: const EdgeInsets.all(16), child: _buildScanButton()),
      ],
    );
  }

  Widget _buildDeviceList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _DeviceTile(
        device: _devices[i],
        onTap: () => _connectTo(_devices[i]),
      ),
    );
  }

  Widget _buildScanButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _startScan,
        icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
        label: Text(
          'Scan for devices',
          style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.glow.withValues(alpha: 0.15),
          foregroundColor: AppTheme.glow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildDemoButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _startDemo,
        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
        label: Text(
          'Try demo mode',
          style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.aurora,
          side: BorderSide(color: AppTheme.aurora.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ── Connecting phase ──────────────────────────────────────────────────

  Widget _buildConnecting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppTheme.glow,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Connecting…',
            style: GoogleFonts.dmSans(fontSize: 16, color: AppTheme.moonbeam),
          ),
        ],
      ),
    );
  }

  // ── Streaming phase ───────────────────────────────────────────────────

  Widget _buildStreaming() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          // Recording indicator
          if (_isRecording)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.crimson.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.crimson,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recording — ${_recordedSamples.length} samples',
                    style: GoogleFonts.robotoMono(
                      fontSize: 11,
                      color: AppTheme.crimson,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Live chart / Spectral analysis — animated crossfade.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _showSpectral
                  ? SpectralAnalysisChart(
                      key: const ValueKey('spectral'),
                      signalStream: _isDemoMode
                          ? _demoSignalController.stream
                          : _service.signalStream,
                      channelDescriptors: _provider!.channelDescriptors,
                      sampleRateHz: _provider!.sampleRateHz,
                      deviceName: _isDemoMode
                          ? 'Demo'
                          : _service.connectedDevice?.platformName,
                      sourceName: _isDemoMode
                          ? '${_provider!.displayName} (Demo)'
                          : _provider!.displayName,
                      onSwitchToTimeDomain: () =>
                          setState(() => _showSpectral = false),
                    )
                  : LiveSignalChart(
                      key: const ValueKey('timedomain'),
                      signalStream: _isDemoMode
                          ? _demoSignalController.stream
                          : _service.signalStream,
                      channelDescriptors: _provider!.channelDescriptors,
                      deviceName: _isDemoMode
                          ? 'Demo'
                          : _service.connectedDevice?.platformName,
                      sourceName: _isDemoMode
                          ? '${_provider!.displayName} (Demo)'
                          : _provider!.displayName,
                      onDisconnect: _isDemoMode ? _stopDemo : _disconnect,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppTheme.crimson.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'Connection error',
            style: GoogleFonts.dmSans(fontSize: 16, color: AppTheme.crimson),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.fog),
              ),
            ),
          const SizedBox(height: 24),
          _buildScanButton(),
          const SizedBox(height: 12),
          _buildDemoButton(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final BleSourceDevice device;
  final VoidCallback onTap;

  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.bluetooth_rounded,
              color: AppTheme.glow.withValues(alpha: 0.6),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.moonbeam,
                    ),
                  ),
                  Text(
                    device.device.remoteId.str,
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      color: AppTheme.fog.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // RSSI badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _rssiColor(device.rssi).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${device.rssi} dBm',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _rssiColor(device.rssi),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return AppTheme.seaGreen;
    if (rssi >= -80) return AppTheme.amber;
    return AppTheme.crimson;
  }
}
