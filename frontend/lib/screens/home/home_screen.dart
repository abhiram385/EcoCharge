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
  LatLng _center = const LatLng(17.3850, 78.4867); // Default: Hyderabad
  bool _mapView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final sessionProvider = context.read<SessionProvider>();
    await sessionProvider.refreshActiveSession();
    _showAutoStopMessageIfAny(sessionProvider);
    await _loadLocationAndStations();
  }

  // The home screen is very often the first thing a user sees after
  // reopening the app — which is exactly when a session that reached its
  // Auto Stop target while the app was backgrounded gets finalized (this
  // refreshActiveSession() call hits the same GET /active that performs
  // the auto-stop finalize). ActiveSessionScreen is the only other place
  // that reads autoStopMessage, so if it isn't mounted, nothing tells the
  // user their session just completed unless we handle it here too.
  void _showAutoStopMessageIfAny(SessionProvider sessionProvider) {
    final message = sessionProvider.autoStopMessage;
    if (message == null) return;
    sessionProvider.clearAutoStopMessage();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadLocationAndStations() async {
    // Show results immediately using the last-known (or default) position —
    // don't make the user wait on a fresh GPS fix, which can take several
    // seconds on a real device (instant on an emulator, which is why this
    // wasn't noticeable before).
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _center = LatLng(lastKnown.latitude, lastKnown.longitude);
      }
    } catch (_) {
      // Fall back to the default center silently.
    }
    if (!mounted) return;
    context.read<StationProvider>().loadNearby(_center.latitude, _center.longitude);

    // Refresh in the background once a precise fix is available.
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return;
      _center = LatLng(pos.latitude, pos.longitude);
      context.read<StationProvider>().loadNearby(_center.latitude, _center.longitude);
    } catch (_) {
      // Precise fix unavailable; the last-known/default result already loaded above stands.
    }
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
