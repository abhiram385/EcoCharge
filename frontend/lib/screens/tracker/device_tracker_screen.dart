import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/glass_panel.dart';

/// Live position of the Atlanta EL-440 tracker on a map. Positions reach the
/// backend from tools/atlTcpServer.js (the device streams over GPRS — real
/// fixes land roughly every 60-70s, a firmware-enforced floor on the device
/// itself) with tools/pollEl440.js + the SMS webhook as a fallback path. The
/// marker glides and pulses continuously between real fixes purely as a
/// presentation smoothing — it never invents a position, only interpolates
/// between two it actually received. The device is keyed by its IMEI.
const kDemoTrackerDeviceId = '864688053456114';

class DeviceTrackerScreen extends StatefulWidget {
  final String deviceId;
  const DeviceTrackerScreen({super.key, this.deviceId = kDemoTrackerDeviceId});

  @override
  State<DeviceTrackerScreen> createState() => _DeviceTrackerScreenState();
}

class _DeviceTrackerScreenState extends State<DeviceTrackerScreen> with TickerProviderStateMixin {
  final _api = ApiService();
  GoogleMapController? _map;
  Timer? _poll;

  // Glides the marker from the last displayed spot to each newly-fetched fix.
  late final AnimationController _moveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  // A continuous "radar ping" halo so the marker reads as live even in the
  // gap between real fixes — never claims a new position, just breathes.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  LatLng? _fromLatLng;
  LatLng? _toLatLng;
  double _fromHeading = 0;
  double _toHeading = 0;

  BitmapDescriptor? _markerIcon;
  Map<String, dynamic>? _position;
  String? _error;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _buildMarkerIcon().then((icon) {
      if (mounted) setState(() => _markerIcon = icon);
    });
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _moveController.dispose();
    _pulseController.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final pos = await _api.trackerLatest(widget.deviceId).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      final isNewFix = pos != null &&
          (_position == null || pos['recordedAt'] != _position!['recordedAt']);

      setState(() {
        _position = pos;
        _error = null;
        _loadedOnce = true;
      });

      if (isNewFix) _startGlideTo(pos);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadedOnce = true;
      });
    }
  }

  void _startGlideTo(Map<String, dynamic> pos) {
    final target = LatLng(pos['lat'] as double, pos['lng'] as double);
    final targetHeading = (pos['headingDeg'] as num?)?.toDouble();

    final current = _currentInterpolatedLatLng() ?? target;
    _fromLatLng = current;
    _toLatLng = target;
    _fromHeading = _currentInterpolatedHeading();
    _toHeading = targetHeading ?? _fromHeading; // keep facing if this fix has no heading

    _moveController.forward(from: 0);
  }

  LatLng? _currentInterpolatedLatLng() {
    if (_fromLatLng == null || _toLatLng == null) return _toLatLng;
    final t = Curves.easeInOut.transform(_moveController.value);
    return LatLng(
      ui.lerpDouble(_fromLatLng!.latitude, _toLatLng!.latitude, t)!,
      ui.lerpDouble(_fromLatLng!.longitude, _toLatLng!.longitude, t)!,
    );
  }

  double _currentInterpolatedHeading() {
    final t = Curves.easeInOut.transform(_moveController.value);
    // Shortest angular path so a 350deg -> 10deg turn doesn't spin the long way.
    final delta = ((_toHeading - _fromHeading + 540) % 360) - 180;
    return (_fromHeading + delta * t) % 360;
  }

  /// A small rich circular marker (gradient fill, white ring, soft shadow,
  /// heading chevron) drawn once and reused — Marker.rotation turns it live.
  Future<BitmapDescriptor> _buildMarkerIcon() async {
    const size = 120.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    const center = Offset(size / 2, size / 2);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(center.translate(0, 5), 30, shadowPaint);

    canvas.drawCircle(center, 33, Paint()..color = Colors.white);

    final gradient = ui.Gradient.linear(
      const Offset(size / 2, size / 2 - 27),
      const Offset(size / 2, size / 2 + 27),
      [const Color(0xFF5AC8FA), const Color(0xFF1E6FD9)],
    );
    canvas.drawCircle(center, 27, Paint()..shader = gradient);

    final chevron = Path()
      ..moveTo(center.dx, center.dy - 13)
      ..lineTo(center.dx - 8, center.dy + 8)
      ..lineTo(center.dx, center.dy + 2)
      ..lineTo(center.dx + 8, center.dy + 8)
      ..close();
    canvas.drawPath(
      chevron,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final hasFix = _toLatLng != null;
    const fallback = LatLng(17.3850, 78.4867); // Hyderabad, before any fix arrives

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle tracker')),
      body: AnimatedBuilder(
        animation: Listenable.merge([_moveController, _pulseController]),
        builder: (context, _) {
          final display = _currentInterpolatedLatLng() ?? fallback;
          final heading = _currentInterpolatedHeading();
          final pulseT = _pulseController.value;

          // Light continuous camera follow, synced to the same glide.
          if (hasFix) _map?.moveCamera(CameraUpdate.newLatLng(display));

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: display, zoom: 15),
                onMapCreated: (c) {
                  _map = c;
                  if (hasFix) c.moveCamera(CameraUpdate.newLatLng(display));
                },
                markers: !hasFix || _markerIcon == null
                    ? {}
                    : {
                        Marker(
                          markerId: const MarkerId('device'),
                          position: display,
                          rotation: heading,
                          flat: true,
                          anchor: const Offset(0.5, 0.5),
                          icon: _markerIcon!,
                        ),
                      },
                circles: !hasFix
                    ? {}
                    : {
                        // Radar-ping halo: expands and fades, then loops —
                        // keeps the marker feeling alive between real fixes.
                        Circle(
                          circleId: const CircleId('pulse'),
                          center: display,
                          radius: ui.lerpDouble(18, 70, pulseT)!,
                          fillColor: AppColors.skyBlue.withValues(alpha: (1 - pulseT) * 0.28),
                          strokeWidth: 0,
                        ),
                        Circle(
                          circleId: const CircleId('core'),
                          center: display,
                          radius: 14,
                          fillColor: AppColors.skyBlue.withValues(alpha: 0.16),
                          strokeWidth: 1,
                          strokeColor: AppColors.skyBlue.withValues(alpha: 0.4),
                        ),
                      },
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: _StatusPanel(
                  deviceId: widget.deviceId,
                  position: _position,
                  error: _error,
                  loadedOnce: _loadedOnce,
                  pulse: pulseT,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}

class _StatusPanel extends StatelessWidget {
  final String deviceId;
  final Map<String, dynamic>? position;
  final String? error;
  final bool loadedOnce;
  final double pulse;

  const _StatusPanel({
    required this.deviceId,
    required this.position,
    required this.error,
    required this.loadedOnce,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final pos = position;

    String headline;
    String sub;
    Color dot;
    if (error != null) {
      headline = 'Connection problem';
      sub = error!;
      dot = AppColors.error;
    } else if (!loadedOnce) {
      headline = 'Connecting…';
      sub = deviceId;
      dot = AppColors.textMuted;
    } else if (pos == null) {
      headline = 'Waiting for the device';
      sub = "$deviceId hasn't reported a position yet";
      dot = AppColors.sunGlow;
    } else {
      final recorded = DateTime.tryParse(pos['recordedAt'] as String)?.toLocal();
      final ageSec = recorded == null ? null : DateTime.now().difference(recorded).inSeconds;
      final speed = (pos['speedKph'] as num?)?.toDouble();
      headline = speed == null ? 'Live' : '${speed.toStringAsFixed(0)} km/h';
      sub = [
        deviceId,
        if (recorded != null) 'updated ${_ago(ageSec!)} (${DateFormat.Hms().format(recorded)})',
      ].join('  •  ');
      // The device's own reporting floor is ~60-70s, so "fresh" means within
      // one reporting cycle, not seconds.
      dot = (ageSec != null && ageSec <= 90) ? AppColors.statusAvailable : AppColors.sunGlow;
    }

    final dotScale = error == null && loadedOnce && pos != null ? 0.85 + 0.3 * (1 - (pulse - 0.5).abs() * 2) : 1.0;

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            child: Transform.scale(
              scale: dotScale,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline,
                    style: GoogleFonts.baloo2(color: AppColors.deepAzure, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(int seconds) {
    if (seconds < 5) return 'just now';
    if (seconds < 60) return '${seconds}s ago';
    final m = (seconds / 60).floor();
    return '${m}m ago';
  }
}
