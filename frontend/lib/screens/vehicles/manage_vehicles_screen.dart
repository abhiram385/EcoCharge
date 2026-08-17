import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/add_vehicle_sheet.dart';

/// Full vehicle management: view every saved vehicle with its persisted
/// battery level (kept in sync by charging sessions and battery swaps —
/// see backend/utils/sessionFinalize.js and routes/swap.js), add a
/// vehicle with a plate number, or remove one.
class ManageVehiclesScreen extends StatefulWidget {
  const ManageVehiclesScreen({super.key});

  @override
  State<ManageVehiclesScreen> createState() => _ManageVehiclesScreenState();
}

class _ManageVehiclesScreenState extends State<ManageVehiclesScreen> {
  final _api = ApiService();
  List<Vehicle> _vehicles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.getVehicles();
      setState(() => _vehicles = raw.map((v) => Vehicle.fromJson(v)).toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addVehicleSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => const AddVehicleSheet(),
    );
    if (added == true) _load();
  }

  Future<void> _editPlate(Vehicle v) async {
    final ctrl = TextEditingController(text: v.regNumber ?? '');
    final reg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Number plate'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. MP04 AB 1234'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (reg == null) return;
    await _api.updateVehicle(v.id, regNumber: reg.isEmpty ? '' : reg);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My vehicles'),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: _addVehicleSheet),
        ],
      ),
      body: AeroBackground(
        bubbleCount: 3,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.skyBlue))
            : _vehicles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_car_filled_rounded, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text('No vehicles added yet', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          _AddVehicleShortcutButton(onTap: _addVehicleSheet),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _vehicles.length,
                    itemBuilder: (context, i) {
                      final v = _vehicles[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _VehicleTile(
                          vehicle: v,
                          onEditPlate: () => _editPlate(v),
                          onDelete: () async {
                            await _api.deleteVehicle(v.id);
                            _load();
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _AddVehicleShortcutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddVehicleShortcutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(onPressed: onTap, icon: const Icon(Icons.add_rounded), label: const Text('Add a vehicle'));
  }
}

class _VehicleTile extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onEditPlate;
  final VoidCallback onDelete;

  const _VehicleTile({required this.vehicle, required this.onEditPlate, required this.onDelete});

  Color get _batteryColor {
    if (vehicle.batteryLevelPct >= 60) return AppColors.statusAvailable;
    if (vehicle.batteryLevelPct >= 25) return AppColors.sunGlow;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: vehicle.swapCapable ? AppColors.orbGradientGreen : AppColors.orbGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  vehicle.swapCapable ? Icons.two_wheeler_rounded : Icons.directions_car_filled_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(vehicle.displayName,
                              style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (vehicle.isDefault) const Chip(label: Text('Default', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    Text(
                      '${vehicle.connectorType} • ${vehicle.batteryCapacityKwh.toStringAsFixed(1)} kWh${vehicle.swapCapable ? ' • Swap-capable' : ''}',
                      style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Battery', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12.5)),
              const Spacer(),
              Text('${vehicle.batteryLevelPct}%', style: GoogleFonts.baloo2(color: _batteryColor, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: vehicle.batteryLevelPct / 100,
              minHeight: 8,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(_batteryColor),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEditPlate,
                  icon: const Icon(Icons.badge_outlined, size: 16),
                  label: Text(vehicle.regNumber ?? 'Add plate number', overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
                onPressed: vehicle.isDefault ? null : onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
