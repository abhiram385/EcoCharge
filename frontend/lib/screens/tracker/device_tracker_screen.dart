import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/glass_panel.dart';

/// PoC: shows the live position of the Atlanta EL-440 tracker on a map.
/// Positions reach the backend from GETGPS SMS replies (via tools/pollEl440.js
/// + the /api/tracker/sms-hook webhook) today, and from the GPRS decoder once
/// Atlanta provides the ATL protocol spec — this screen doesn't change either
/// way. The device is keyed by its IMEI.
const kDemoTrackerDeviceId = '864688053456114';

class DeviceTrackerScreen extends StatefulWidget {
  final String deviceId;
  const DeviceTrackerScreen({super.key, this.deviceId = kDemoTrackerDeviceId});

  @override
  State<DeviceTrackerScreen> createState() => _DeviceTrackerScreenState();
}

class _DeviceTrackerScreenState extends State<DeviceTrackerScreen> {
  final _api = ApiService();
  GoogleMapController? _map;
  Timer? _poll;

  Map<String, dynamic>? _position;
  String? _error;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final pos = await _api.trackerLatest(widget.deviceId).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _position = pos;
        _error = null;
        _loadedOnce = true;
      });
      if (pos != null && _map != null) {
        _map!.animateCamera(CameraUpdate.newLatLng(LatLng(pos['lat'] as double, pos['lng'] as double)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadedOnce = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    final target = pos != null
        ? LatLng(pos['lat'] as double, pos['lng'] as double)
        : const LatLng(17.3850, 78.4867); // Hyderabad fallback

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle tracker')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: target, zoom: 14),
            onMapCreated: (c) {
              _map = c;
              if (pos != null) {
                c.animateCamera(CameraUpdate.newLatLng(target));
              }
            },
            markers: pos == null
                ? {}
                : {
                    Marker(
                      markerId: const MarkerId('device'),
                      position: target,
                      rotation: (pos['headingDeg'] as num?)?.toDouble() ?? 0,
                      flat: true,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                    ),
                  },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _StatusPanel(deviceId: widget.deviceId, position: pos, error: _error, loadedOnce: _loadedOnce),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final String deviceId;
  final Map<String, dynamic>? position;
  final String? error;
  final bool loadedOnce;

  const _StatusPanel({required this.deviceId, required this.position, required this.error, required this.loadedOnce});

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
      dot = (ageSec != null && ageSec <= 30) ? AppColors.statusAvailable : AppColors.sunGlow;
    }

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 12),
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
