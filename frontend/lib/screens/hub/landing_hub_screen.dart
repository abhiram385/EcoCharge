import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../home/home_shell.dart';
import '../swap/battery_swap_home_screen.dart';
import '../vehicles/manage_vehicles_screen.dart';
import '../wallet/wallet_screen.dart';
import '../station/station_detail_screen.dart';

/// The screen shown right after login: a real dashboard rather than a bare
/// nav menu — balance, vehicles with their live battery level, a rough CO2
/// impact stat, and a nudge toward the station the user actually goes to
/// (or the nearest one if they have no history yet).
class LandingHubScreen extends StatefulWidget {
  const LandingHubScreen({super.key});

  @override
  State<LandingHubScreen> createState() => _LandingHubScreenState();
}

class _LandingHubScreenState extends State<LandingHubScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _settingDefaultId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    double? lat;
    double? lng;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      if (await Geolocator.isLocationServiceEnabled()) {
        final pos = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // Dashboard still works without location — just no "nearest" fallback.
    }
    try {
      final data = await _api.getDashboard(lat: lat, lng: lng);
      if (mounted) setState(() => _data = data);
    } catch (_) {
      // Leave _data null; the screen shows its own empty/error affordances.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setDefault(String vehicleId) async {
    setState(() => _settingDefaultId = vehicleId);
    try {
      await _api.updateVehicle(vehicleId, isDefault: true);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not set default: $e')));
    }
    if (mounted) setState(() => _settingDefaultId = null);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final greetingName = (user?.name?.isNotEmpty ?? false) ? user!.name! : (user?.phone ?? 'there');
    final vehicles = (_data?['vehicles'] as List?)?.map((v) => Vehicle.fromJson(v)).toList() ?? [];
    final balance = (_data?['walletBalance'] as num?)?.toDouble() ?? 0;
    final impact = _data?['impact'] as Map<String, dynamic>?;
    final suggestedStation = _data?['suggestedStation'] as Map<String, dynamic>?;

    return Scaffold(
      body: AeroBackground(
        bubbleCount: 6,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading && _data == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.skyBlue))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      Text(
                        'Hey $greetingName',
                        style: GoogleFonts.baloo2(color: AppColors.deepAzure, fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Here’s where things stand',
                        style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 20),

                      // Balance
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppColors.orbGradient,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: AppColors.skyBlue.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Wallet balance', style: GoogleFonts.nunitoSans(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.5)),
                                    const SizedBox(height: 4),
                                    Text('₹${balance.toStringAsFixed(2)}', style: GoogleFonts.baloo2(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Vehicles
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Your vehicles', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.deepAzure)),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageVehiclesScreen())).then((_) => _load()),
                            child: const Text('Manage'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (vehicles.isEmpty)
                        GlassPanel(
                          radius: 20,
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              const Icon(Icons.directions_car_filled_rounded, color: AppColors.textMuted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('No vehicles yet — add one to get started', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageVehiclesScreen())).then((_) => _load()),
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        )
                      else
                        SizedBox(
                          height: 128,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: vehicles.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, i) {
                              final v = vehicles[i];
                              return _VehicleMiniCard(
                                vehicle: v,
                                settingDefault: _settingDefaultId == v.id,
                                onSetDefault: () => _setDefault(v.id),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 22),

                      // CO2 impact
                      if (impact != null) _ImpactCard(impact: impact),
                      if (impact != null) const SizedBox(height: 22),

                      // Suggested station
                      if (suggestedStation != null)
                        _SuggestedStationCard(
                          station: suggestedStation,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => StationDetailScreen(stationId: suggestedStation['id'] as String)),
                          ),
                        ),
                      if (suggestedStation != null) const SizedBox(height: 22),

                      // Quick actions
                      Row(
                        children: [
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.ev_station_rounded,
                              gradient: AppColors.orbGradient,
                              glow: AppColors.skyBlue,
                              label: 'Charge Up',
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeShell())),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.battery_charging_full_rounded,
                              gradient: AppColors.orbGradientGreen,
                              glow: AppColors.leafGreen,
                              label: 'Battery Swap',
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BatterySwapHomeScreen())),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _VehicleMiniCard extends StatelessWidget {
  final Vehicle vehicle;
  final bool settingDefault;
  final VoidCallback onSetDefault;

  const _VehicleMiniCard({required this.vehicle, required this.settingDefault, required this.onSetDefault});

  Color get _batteryColor {
    if (vehicle.batteryLevelPct >= 60) return AppColors.statusAvailable;
    if (vehicle.batteryLevelPct >= 25) return AppColors.sunGlow;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: GlassPanel(
        radius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vehicle.displayName,
                    style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: settingDefault ? null : onSetDefault,
                  child: settingDefault
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sunGlow))
                      : Icon(
                          vehicle.isDefault ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: vehicle.isDefault ? AppColors.sunGlow : AppColors.textMuted,
                          size: 20,
                        ),
                ),
              ],
            ),
            const Spacer(),
            Text('${vehicle.batteryLevelPct}%', style: GoogleFonts.baloo2(color: _batteryColor, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: vehicle.batteryLevelPct / 100,
                minHeight: 6,
                backgroundColor: AppColors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation(_batteryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  final Map<String, dynamic> impact;
  const _ImpactCard({required this.impact});

  @override
  Widget build(BuildContext context) {
    final co2 = (impact['co2SavedKg'] as num).toDouble();
    final trees = (impact['treesEquivalent'] as num).toDouble();
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(gradient: AppColors.orbGradientGreen, shape: BoxShape.circle),
            child: const Icon(Icons.eco_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: co2 <= 0
                ? Text(
                    'Charge or swap once and we’ll start tracking your CO₂ savings 🌱',
                    style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${co2.toStringAsFixed(1)} kg CO₂ saved so far 🌱',
                        style: GoogleFonts.baloo2(color: AppColors.deepAzure, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'That’s like planting ${trees < 0.1 ? "a" : trees.toStringAsFixed(1)} tree${trees >= 1.05 ? 's' : ''} 🌳',
                        style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedStationCard extends StatelessWidget {
  final Map<String, dynamic> station;
  final VoidCallback onTap;
  const _SuggestedStationCard({required this.station, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFrequent = station['reason'] == 'frequent';
    final distanceKm = station['distanceKm'];
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(isFrequent ? Icons.favorite_rounded : Icons.near_me_rounded, color: AppColors.skyBlue),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFrequent ? 'Your usual spot' : 'Nearest to you',
                    style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  Text(
                    '${station['name']}${distanceKm != null ? ' • $distanceKm km' : ''}',
                    style: GoogleFonts.baloo2(color: AppColors.deepAzure, fontWeight: FontWeight.w800, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final Color glow;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({required this.icon, required this.gradient, required this.glow, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient, boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.4), blurRadius: 14)]),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 10),
            Text(label, style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.deepAzure)),
          ],
        ),
      ),
    );
  }
}
