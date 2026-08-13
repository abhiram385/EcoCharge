import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/app_theme.dart';
import '../../models/station.dart';
import '../../providers/station_provider.dart';
import '../../providers/session_provider.dart';
import '../station/station_detail_screen.dart';
import '../session/active_session_screen.dart';
import '../../widgets/station_card.dart';
import '../../widgets/aero/aero_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _mapController;
  LatLng _center = const LatLng(23.2599, 77.4126); // Default: Bhopal
  bool _mapView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await context.read<SessionProvider>().refreshActiveSession();
    await _loadLocationAndStations();
  }

  Future<void> _loadLocationAndStations() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        _center = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {
      // Fall back to default center silently; user can still browse.
    }
    if (!mounted) return;
    context.read<StationProvider>().loadNearby(_center.latitude, _center.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final stationProvider = context.watch<StationProvider>();
    final session = context.watch<SessionProvider>().activeSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a station'),
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
          onRefresh: _loadLocationAndStations,
          child: Column(
            children: [
              if (session != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _ActiveSessionBanner(
                    stationName: session.stationName,
                    energyKwh: session.energyKwh,
                    cost: session.cost,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ActiveSessionScreen()),
                    ),
                  ),
                ),
              Expanded(
                child: _mapView ? _buildMap(stationProvider.stations) : _buildList(stationProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap(List<Station> stations) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _center, zoom: 13),
      onMapCreated: (c) => _mapController = c,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: stations
          .map((s) => Marker(
                markerId: MarkerId(s.id),
                position: LatLng(s.latitude, s.longitude),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                infoWindow: InfoWindow(
                  title: s.name,
                  snippet: '${s.rating} ★  •  ${s.distanceKm ?? '-'} km',
                  onTap: () => _openDetail(s.id),
                ),
              ))
          .toSet(),
    );
  }

  Widget _buildList(StationProvider provider) {
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
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      );
    }

    if (provider.stations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ev_station_rounded, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                'No stations found nearby. Pull to refresh.',
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
      itemCount: provider.stations.length,
      itemBuilder: (context, index) {
        final s = provider.stations[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: StationCard(station: s, onTap: () => _openDetail(s.id)),
        );
      },
    );
  }

  void _openDetail(String stationId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StationDetailScreen(stationId: stationId)),
    );
  }
}

class _ActiveSessionBanner extends StatelessWidget {
  final String stationName;
  final double energyKwh;
  final double cost;
  final VoidCallback onTap;

  const _ActiveSessionBanner({
    required this.stationName,
    required this.energyKwh,
    required this.cost,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.orbGradientGreen,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppColors.leafGreen.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Charging in progress', style: GoogleFonts.nunitoSans(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(stationName,
                      style: GoogleFonts.baloo2(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
            ),
            Text(
              '${energyKwh.toStringAsFixed(1)} kWh',
              style: GoogleFonts.baloo2(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
