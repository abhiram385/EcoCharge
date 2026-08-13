import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/station.dart';
import '../../providers/station_provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../booking/booking_screen.dart';
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
    final sessionProvider = context.read<SessionProvider>();
    final ok = await sessionProvider.startCharging(
      stationId: station.id,
      connectorId: connector.id,
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
