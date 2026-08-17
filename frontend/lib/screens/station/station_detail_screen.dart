import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../models/station.dart';
import '../../providers/station_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../booking/booking_screen.dart';
import '../vehicles/manage_vehicles_screen.dart';
import '../session/active_session_screen.dart';

class StationDetailScreen extends StatefulWidget {
  final String stationId;
  const StationDetailScreen({super.key, required this.stationId});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StationProvider>().loadStationDetail(widget.stationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StationProvider>();
    final station = provider.selectedStation;

    return Scaffold(
      appBar: AppBar(title: const Text('Station details')),
      body: AeroBackground(
        bubbleCount: 3,
        child: provider.isLoadingDetail || station == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.skyBlue))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(station.name,
                      style: GoogleFonts.baloo2(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                  const SizedBox(height: 6),
                  Text(station.address ?? '',
                      style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _infoChip(Icons.star_rounded, '${station.rating} rating', AppColors.sunGlow, AppColors.sunPale),
                      const SizedBox(width: 10),
                      _infoChip(
                        Icons.access_time_filled_rounded,
                        station.isOpen24h ? 'Open 24/7' : 'Limited hours',
                        AppColors.leafDark,
                        AppColors.leafPale,
                      ),
                    ],
                  ),
                  if (station.amenities.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text('Amenities', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: station.amenities
                          .map((a) => Chip(label: Text(a), avatar: const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.leafDark)))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Chargers', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
                  const SizedBox(height: 10),
                  ...provider.selectedStationConnectors.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ConnectorTile(
                          connector: c,
                          onBook: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BookingScreen(station: station, connector: c),
                            ),
                          ),
                          onStartNow: () => _startChargingNow(context, station, c),
                        ),
                      )),
                ],
              ),
      ),
    );
  }

  Future<void> _startChargingNow(BuildContext context, Station station, Connector connector) async {
    final api = ApiService();
    final rawVehicles = await api.getVehicles();
    final vehicles = rawVehicles.map((v) => Vehicle.fromJson(v)).toList();
    final compatible = vehicles.where((v) => v.connectorType == connector.connectorType).toList();

    if (!context.mounted) return;

    if (compatible.isEmpty) {
      final wantsToAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add a compatible vehicle'),
          content: Text('You need a saved ${connector.connectorType} vehicle before charging here.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add vehicle')),
          ],
        ),
      );
      if (wantsToAdd != true || !context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageVehiclesScreen()));
      if (!context.mounted) return;
      return _startChargingNow(context, station, connector);
    }

    final result = await _showChargeSheet(context, compatible);
    if (result == null || !context.mounted) return; // user cancelled the sheet

    final sessionProvider = context.read<SessionProvider>();
    final ok = await sessionProvider.startCharging(
      stationId: station.id,
      connectorId: connector.id,
      vehicleId: result.vehicleId,
      autoStopPct: result.autoStopPct == 100 ? null : result.autoStopPct,
    );
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActiveSessionScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sessionProvider.error ?? 'Could not start charging')),
      );
    }
  }

  /// Shows a combined bottom sheet: pick which saved vehicle is charging
  /// (pre-selected if only one is compatible), then the Auto Stop battery
  /// target (10 steps of 10%, range 10–100%, default 100 = charge to
  /// full). Returns the chosen vehicle ID + percentage, or null if the
  /// user dismissed the sheet without confirming.
  Future<({String vehicleId, int autoStopPct})?> _showChargeSheet(
    BuildContext context,
    List<Vehicle> compatibleVehicles,
  ) async {
    Vehicle selectedVehicle = compatibleVehicles.firstWhere(
      (v) => v.isDefault,
      orElse: () => compatibleVehicles.first,
    );
    int selectedPct = 100;
    return showModalBottomSheet<({String vehicleId, int autoStopPct})>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.chromeMist,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              const SizedBox(height: 10),
              if (compatibleVehicles.length == 1)
                GlassPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  radius: 16,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.directions_car_filled_rounded, color: AppColors.skyBlue),
                    title: Text(selectedVehicle.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                    subtitle: Text('${selectedVehicle.batteryCapacityKwh.toStringAsFixed(1)} kWh'),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: compatibleVehicles.map((v) {
                    final sel = v.id == selectedVehicle.id;
                    return ChoiceChip(
                      label: Text(v.displayName),
                      selected: sel,
                      onSelected: (_) => setSheetState(() => selectedVehicle = v),
                      selectedColor: AppColors.skyBlue,
                      labelStyle: GoogleFonts.nunitoSans(color: sel ? Colors.white : AppColors.deepAzure, fontWeight: FontWeight.w700),
                      backgroundColor: Colors.white,
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),
              Text('Auto Stop charging at',
                  style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              const SizedBox(height: 4),
              Text('Charging stops automatically once the battery reaches this level.',
                  style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                radius: 20,
                child: Column(
                  children: [
                    Text('$selectedPct%',
                        style: GoogleFonts.baloo2(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.skyBlue)),
                    Slider(
                      value: selectedPct.toDouble(),
                      min: 10,
                      max: 100,
                      divisions: 9, // 10 steps of 10%: 10,20,...,100
                      activeColor: AppColors.skyBlue,
                      label: '$selectedPct%',
                      onChanged: (v) => setSheetState(() => selectedPct = v.round()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              EnergyOrbButton(
                label: 'Start charging',
                icon: Icons.bolt_rounded,
                width: double.infinity,
                onPressed: () => Navigator.pop(ctx, (vehicleId: selectedVehicle.id, autoStopPct: selectedPct)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.nunitoSans(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ConnectorTile extends StatelessWidget {
  final Connector connector;
  final VoidCallback onBook;
  final VoidCallback onStartNow;

  const _ConnectorTile({required this.connector, required this.onBook, required this.onStartNow});

  Color get _statusColor {
    switch (connector.status) {
      case 'available':
        return AppColors.statusAvailable;
      case 'occupied':
        return AppColors.statusOccupied;
      default:
        return AppColors.statusOffline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = connector.status == 'available';
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _statusColor.withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 8),
              Text(connector.connectorType, style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.deepAzure)),
              const Spacer(),
              Text(connector.status[0].toUpperCase() + connector.status.substring(1),
                  style: GoogleFonts.nunitoSans(color: _statusColor, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.flash_on_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text('${connector.powerKw.toStringAsFixed(0)} kW', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              const Icon(Icons.currency_rupee_rounded, size: 16, color: AppColors.textSecondary),
              Text('${connector.pricePerKwh.toStringAsFixed(2)}/kWh', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: available ? onBook : null,
                  child: const Text('Book a slot'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: EnergyOrbButton(
                  label: 'Charge now',
                  icon: Icons.bolt_rounded,
                  onPressed: available ? onStartNow : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
