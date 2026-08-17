import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/app_theme.dart';
import '../../models/swap.dart';
import '../../providers/swap_provider.dart';
import '../../widgets/swap_point_card.dart';
import '../../widgets/aero/aero_background.dart';
import 'swap_point_detail_screen.dart';

class BatterySwapHomeScreen extends StatefulWidget {
  const BatterySwapHomeScreen({super.key});

  @override
  State<BatterySwapHomeScreen> createState() => _BatterySwapHomeScreenState();
}

class _BatterySwapHomeScreenState extends State<BatterySwapHomeScreen> {
  GoogleMapController? _mapController;
  LatLng _center = const LatLng(23.2599, 77.4126); // Default: Bhopal
  bool _mapView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocationAndPoints());
  }

  Future<void> _loadLocationAndPoints() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        _center = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {
      // Fall back to default center silently; user can still browse.
    }
    if (!mounted) return;
    context.read<SwapProvider>().loadNearby(_center.latitude, _center.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final swapProvider = context.watch<SwapProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery swap'),
        actions: [
          IconButton(
            icon: Icon(_mapView ? Icons.list_rounded : Icons.map_rounded),
            onPressed: () => setState(() => _mapView = !_mapView),
          ),
        ],
      ),
      body: AeroBackground(
        bubbleCount: 4,
        child: RefreshIndicator(
          onRefresh: _loadLocationAndPoints,
          child: _mapView ? _buildMap(swapProvider.swapPoints) : _buildList(swapProvider),
        ),
      ),
    );
  }

  Widget _buildMap(List<SwapPoint> points) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _center, zoom: 13),
      onMapCreated: (c) => _mapController = c,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: points
          .map((p) => Marker(
                markerId: MarkerId(p.id),
                position: LatLng(p.latitude, p.longitude),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                infoWindow: InfoWindow(
                  title: p.name,
                  snippet: '${p.rating} ★  •  ${p.distanceKm ?? '-'} km',
                  onTap: () => _openDetail(p.id),
                ),
              ))
          .toSet(),
    );
  }

  Widget _buildList(SwapProvider provider) {
    if (provider.isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Shimmer.fromColors(
            baseColor: AppColors.surfaceMuted,
            highlightColor: AppColors.surface,
            child: Container(
              height: 110,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
      );
    }

    if (provider.swapPoints.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.battery_charging_full_rounded, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                'No swap points found nearby. Pull to refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.swapPoints.length,
      itemBuilder: (context, index) {
        final p = provider.swapPoints[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SwapPointCard(point: p, onTap: () => _openDetail(p.id)),
        );
      },
    );
  }

  void _openDetail(String swapPointId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SwapPointDetailScreen(swapPointId: swapPointId)),
    );
  }
}
